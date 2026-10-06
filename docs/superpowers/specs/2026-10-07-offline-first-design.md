# Offline-First Architecture — Design Spec

**Date:** 2026-10-07 · **Status:** approved at design level (brainstorm), pending spec review
**Authority chain:** user decisions 2026-10-06/07 → this spec → implementation plan (writing-plans)
**Related:** `docs/backlog.md` §0 · W3 spec (unchanged) · existing repo interfaces in `lib/infrastructure/repositories/`

---

## 1. Purpose & intent

More than 90% of production bugs live at the frontend↔backend seam: key-not-ready blocks
message fetch (`message_repository_impl.dart:2484` skips caching entirely → blank chat),
SSE races, screen-level HTTP bypasses, ad-hoc retry loops. This spec finishes and hardens
the offline-first spine that already exists (~60%: Drift watch streams, optimistic send,
SSE write-through) rather than rewriting it.

**Intended outcome:** the app is fully usable from the local database with zero network;
network is an ingest detail. **Success = §14.**

**Non-goals:** no server/PocketBase changes (§16 gate handles the one assumption);
no UI redesign (chat/home restructure is separate queued work); no new features.

## 2. Locked decisions (with provenance)

| Decision | Source |
|---|---|
| Approach **1 — Unified Ingest Pipeline** | user pick 2026-10-07 |
| Spec for all, implementation phased | Q1 = C |
| Success = §14 (B-mod: wide import gate, kill-mid-queue, long-gap) | Q2 |
| Media: metadata offline + on-demand bytes + blob FSM | Q3 = A + 4 rules |
| Cache: 300 MB **config constant**, deferred eviction (start + 85% watermark) | Q4 = A |
| Threat model: messages decrypt-on-read (no plaintext bodies at rest); media plaintext-at-rest **accepted with conditions** (§3) | amendment |
| 5 execution guards (order/single-boundary/ciphertext/gate-last/scope) | user, 2026-10-07 |
| Phase-0 custom-ID + fallback plan | §16 |
| 4xx carve-out, backoff connectivity reset, terminal-block UI, background cache clear | amendments, 2026-10-07 |

## 3. Threat model & data at rest

- **Message bodies:** no plaintext at rest. `decrypted_body` column is **dropped**;
  bodies decrypt on read into an **in-memory session cache** (see §8). DB stores
  ciphertext + `decrypt_state` + `key_id` only.
- **Media files (accepted residual risk, explicit):** decrypted media lives in the
  **app-private directory ONLY** — never shared storage, never the gallery. Covered by
  logout wipe (§11). Also wiped on logout: outbox rows, blob rows, temp files,
  in-memory decrypt cache, cursors. Decrypted in-memory body cache **also cleared on
  app backgrounding** (cheap, consistent with this model).
- **Encryption at rest for media cache** → `docs/backlog.md` (not planned now).
- Keys remain in secure storage (unchanged).

## 4. Architecture — disjoint single-writer domains

```
UI screens ──read──▶ Drift only          UI commands ──▶ Repos (existing interfaces)
                                                  │
                    ┌─────────────────────────────┼──────────────────────────────┐
                    ▼                             ▼                              ▼
             ┌─────────────┐   ┌──────────────────────────┐   ┌────────────────────┐
             │ OutboxWorker│──▶│  IngestBoundary (SINGLE) │   │  MediaBlobStore    │
             │ send FSM    │   │  sse | fetch | drain-ack │   │  bytes FSM + files │
             └─────────────┘   └────────────┬─────────────┘   └────────────────────┘
                                            │ same txn rules, session-epoch guarded
                                            ▼
              Drift (ciphertext + state + cursor) ──▶ DecryptPass (bg isolate) ──▶ memcache
```

**Two writers, disjoint tables, no third writer (the "two-gate rule"):**
1. **IngestBoundary** is the only writer of network-sourced *records* (messages,
   conversations, members, receipts, social). Sources: SSE events, pull fetches,
   outbox drain-acks — **one entry point, one transaction ruleset**. No fast path:
   an SSE handler that writes Drift directly is a bug (guard 2).
2. **MediaBlobStore** is the only writer of *blob rows and files* (§9).

Media blob commits do **not** route through IngestBoundary (different lifecycle);
the "no bypass" claim is per-domain. Both writers are session-epoch guarded (§11).

UI never performs network I/O in render paths. Commands go to repos; repos enqueue
(repositories become thin: read Drift + write outbox/commands).

## 5. Data model

### 5.1 `messages` (modified)
- `encrypted_body`, `iv` — unchanged (always written; commit never waits for keys).
- `decrypt_state ∈ {pending, ready, key_missing, failed}` — `failed` is **terminal**
  (corrupt/tampered ciphertext must not retry forever).
- `key_id` (text) — key/epoch reference so DecryptPass knows which key to await after
  rotation.
- **DROP** `decrypted_body` column (migration in Phase 4).
- `server_id` = client-generated uuid once custom-ID is live (§16); display `status`
  unchanged, but **only IngestBoundary and OutboxWorker may mutate it, in the same
  transaction as the matching `outbox.state` change** (dual-truth rule).
- **Own sent messages are never placeholders:** at enqueue, body is set from local
  input, `decrypt_state = ready`.
- FTS/search index covers `decrypt_state = ready` rows only.

### 5.2 `outbox` (new — Drift table IS the queue; survives kill)
Columns: `op_id (PK, client uuid)` · `kind ∈ {text_send, media_upload, reaction, pin,
star, delete, …}` · `ref` (local message/blob id) · `conversation_id` · `seq`
(monotonic per conversation) · `state ∈ {queued, sending, sent, failed_terminal}` ·
`attempts` · `next_attempt_at` (transient failures — 429/5xx/timeout — stay
`queued` with backoff metadata; there is deliberately NO `failed_retryable`
state, so "waiting" and "needs user action" can never be confused) · `created_at` ·
`last_error` + `error_class` · `depends_on` (op_id of a prerequisite op, e.g.
`message_send` → its `media_upload`).

**Idempotency (core):** `op_id` is client-generated and becomes the PocketBase record
`id` on create (§16). The boundary upserts by that id; a duplicate-id error on retry
**counts as success**. The three delivery paths — drain-ack, SSE echo of own message,
timeout-retry after a server-received-but-ack-lost — converge on the same id, so no
duplicate bubbles.

**Enqueue atomicity:** message/blob row + outbox row written in **one Drift
transaction**. A kill between them is impossible by construction.

**Two-step outgoing media:** `media_upload` op runs first; its dependent `message_send`
(`depends_on`) drains only after the upload op reaches `sent`. Discarding a terminal
`media_upload` **cascades: dependent `message_send` ops are discarded too.**

### 5.3 `media_blob` (new)
`blob_id (PK)` · `message_id` · `remote_ref` · `expected_size` / `expected_hash` (verify
download) · `local_path` (app-private) · `bytes` · `last_access` ·
`state ∈ {queued, downloading, ready, failed, evicted}` · `upload_pending` (bool).

**No `protected` column.** Protected = derived predicate:
`upload_pending ∨ message.starred ∨ message.pinned` — computed at eviction time so it
cannot drift.

## 6. Outbox policies (FSM)

- **Connectivity class → queued (auto-resume):** offline, timeout, 5xx, network errors.
  `state = queued`, `attempts++`, `next_attempt_at = now + min(cap, base·2^attempts) ± jitter`
  (cap 5 min).
- **4xx carve-out:** `401` → **pause the entire outbox** until re-auth succeeds (not
  terminal; preserves queued work across expired sessions). `429` → retryable,
  **honor `Retry-After`** when present. Terminal only: **400, 403, 404, 413**
  (dead link, expired, forbidden, too-large) → `failed_terminal` with error class.
- **Backoff reset:** attempts reset on **connectivity-restored events** (immediate —
  a user who just reconnected must not wait out a 5-minute backoff) and on successful
  send; elapsed time alone also decays but is not the only trigger.
- **Ordering:** per-conversation FIFO by `seq`. A `failed_terminal` op **blocks later
  ops in the same conversation** until the user retries or discards it; other
  conversations drain normally.
- **Terminal block must be visible:** the stuck message renders an in-bubble banner —
  error class + **Retry** + **Discard** actions. No silent stalls.
- **Stale `sending`:** on startup, `sending → queued` (safe: idempotency key makes
  re-send harmless).

## 7. IngestBoundary rules

- Sole entry for record data from network (§4). Sources tagged `sse | fetch |
  `drain-ack`.
- **One transaction per batch:** upsert rows (by server/op id) + advance the
  per-conversation sync cursor + mutate matching `outbox.state`/`messages.status` —
  atomically. An SSE gap plus pull fetch can neither skip nor double-apply.
- Batches may carry **edits and deletes (tombstones)**; tombstones upsert like any row.
- Session-epoch guard wraps every commit: epoch checked at start, re-checked before
  write (existing Review C1 pattern, extended in §11).
- Duplicate-id on create/retry → success (§5.2).
- Decrypt state on ingest: rows commit as `pending` (or `key_missing` when the key
  lookup throws) — **commit always succeeds regardless of key state**, killing the
  current fetch-path skip (defect at :2484).

## 8. DecryptPass

- Triggered: after each boundary commit and on key-arrival events (reuses the
  existing `groupKeyReadyProvider` signal).
- **Batched, off the UI isolate** (compute/worker isolate) so a large catch-up sync
  cannot jank the screen.
- Loads ciphertext rows where `decrypt_state ∈ {pending, key_missing}`, resolves key
  via `key_id`, writes result: `ready` (+ decrypted plaintext goes to the **in-memory
  cache only**), `failed` (terminal — bad MAC/parse), or stays `key_missing`.
- On rotation, `key_id` mismatch rows are re-queued for the new key; `failed` never
  retries.
- **Placeholder law (same as media):** any consumer of a body must handle
  `decrypt_state != ready` — chat bubbles, **conversation-list previews,
  notifications, and search** render placeholders (skeleton line + 🔒 hint), never
  blanks, never spinner-blocks. Search/FTS indexes `ready` rows only.
- Memcache eviction: LRU by message id, bounded; cleared on backgrounding and
  logout (§3, §11).

## 9. MediaBlobStore

- Sole writer of blob rows + files (§4).
- **States:** `queued → downloading → ready`; offline stays **`queued`** (auto-resume
  on reconnect — failed ≠ offline); `failed` only for dead URL/expired/verify-mismatch;
  `evicted` = bytes dropped, metadata retained (bubble re-renders placeholder, can
  re-download).
- **Startup janitor:** stale `downloading` rows → `queued`; orphan temp files deleted.
  Same treatment for stale `sending` lives in §6.
- **Download verify:** size/hash check before `ready`; mismatch → `failed(error_class:
  verify)`.
- **Eviction:** config constant `kMediaCacheMaxBytes = 300 * 1024 * 1024` (tunable via
  one constant). Trigger deferred: on app start + when watermark (85%) crossed —
  **never on the write/send path**. Eviction order = LRU over `last_access`, skipping
  the protected set (derived, §5.3). Evicted → state + delete file.
- Files: app-private dir only (§3).

## 10. UI mock/build seam (mock-build strategy)

- Screens consume repository interfaces only. `FakeRepo` implementations (in-memory,
  seeded data) selected by Riverpod override; a `--dart-define=USE_FAKES` dev entry
  wires them app-wide for standalone screen development.
- New/reworked screens ship fully working against fakes first; wiring to real repos is
  a final step (user's mock strategy).
- Fake impls also back the automated suite (§14 criterion 4).

## 11. Session, logout, backgrounding

- Session-epoch guard covers **all async writers**: boundary commits, DecryptPass,
  janitor, blob downloads (any in-flight write aborts if epoch changed).
- **Logout wipe set:** local DB (incl. outbox), blob rows, app-private media files
  (decrypted + temp), in-memory decrypt cache, sync cursors. Keys stay in secure
  storage. Existing epoch mechanism retained as the in-app gate.
- **Backgrounding:** clear in-memory decrypt cache (amendment 6, adopted).
- Login/auth flows remain online-only by nature (unchanged).

## 12. Network import gate (LAST — guard 4)

- Enabled only after Phase 5 moves all screen-level HTTP behind repos.
- Rule: **zero network imports outside `lib/infrastructure/`** covering:
  `package:http`, `Dio`, `dart:io HttpClient`, `dart:io WebSocket`,
  `web_socket_channel`, `firebase_*` / FCM, and any other SDK performing network I/O.
  (Future robustness: `import_lint`/`dart_code_linter` — `docs/backlog.md` §0b, not
  planned.)
- Two-gate rule from §4 is independent: writer-domain violations are code-review +
  architecture tests, not this import gate.

## 13. Characterization & testing strategy

- **Phase 0 characterization tests** (before any extraction) pin current behavior for:
  send flow, fetch flow, SSE write path, key-missing path, **and every message-body
  read path: bubbles, conversation-list previews, notifications, search** (amendment 1
  — these are exactly what Phase 4 changes).
- Per-extraction TDD: outbox FSM incl. **triple-delivery idempotency test**
  (drain-ack + SSE echo + timeout-retry → one bubble), fake clock for backoff,
  discard-cascade test, 401-pause test, janitor test, eviction protection test.
- Full suite runs against fake repos (zero real network).
- **Fault-injection CI** (network layer throws everywhere) → backlog §0b, not planned.

## 14. Success criteria (definition of done)

1. Airplane-mode matrix: every screen functional offline on a seeded device; sends
   queue → deliver on reconnect; key-delay → placeholders, never blanks.
2. Production-failure cases: **kill app mid-queue → relaunch offline** (queue and
   janitor states survive); **reconnect after a long gap** (hours) reconciles without
   duplicates or skips.
3. Import gate (§12) green in CI.
4. Full suite green against fake repos.

## 15. Phasing (each phase independently shippable; behavior changes in their own
commits; no mid-refactor broken states)

| Phase | Content | Risk note |
|---|---|---|
| **0** | §16 custom-ID verification + characterization tests (incl. read paths) | gate for everything else |
| **1** | Outbox FSM + enqueue transaction + client-id sends | data-loss risk first (guard 1) |
| **2** | MediaBlobStore FSM + startup janitor + deferred eviction | |
| **3** | IngestBoundary extraction (sse/fetch/drain-ack → one entry; cursor+tombstone txn) | behavior-preserving cut |
| **4** | Cache-policy flip: always-commit ciphertext, `decrypt_state`, DecryptPass, drop `decrypted_body`, placeholder UI | riskier than it looks — Phase 0 read-path tests are the safety net |
| **5** | Screen HTTP → repos (profile upload, group create, link preview) | |
| **6** | Import gate ON + offline matrix (§14) | gate last (guard 4) |

## 16. Phase 0 — custom-ID verification + fallback (decided now)

**Plan A (primary):** PocketBase accepts client-supplied record ids on create. Verify
against our `messages` collection with one authenticated, read-only inspection of
collection settings + one test create in a throwaway dev record (no superuser, no
password-file access — if a write test needs elevated rights, stop and ask the user).
Implementation: include `id: op_id` in every create body.

**Plan B (fallback, if collection rules reject custom ids):** **client dedupe key
inside the encrypted envelope** — ciphertext payload becomes
`{"cid": op_id, "body": …}`; on a timeout-retry, first query the collection by a
decrypting-scan of recent own messages for `cid` before creating; SSE echo decrypts
and dedupes by `cid`. Zero server changes. Cost: one extra query on retry paths and a
payload-envelope migration for new messages.

**Rejected:** server rule/schema change — breaks the no-server-changes lock (§1).

## 17. Explicitly out of scope / deferred (see `docs/backlog.md`)

Encrypted-at-rest media cache · fault-injection CI · import_lint package · server/hook
changes · FCM fixes · chat/home UI restructure · consistency sweep (end-game).

## 18. Open questions

None blocking. Deferred to the implementation plan: exact placeholder widget
styling, fake-repo seeding content, seq allocation mechanics (Drift-side monotonic
per conversation), FTS table migration details.
