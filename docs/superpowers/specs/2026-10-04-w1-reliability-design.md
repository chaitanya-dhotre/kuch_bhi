# W1 Reliability Core — Design ("Fix the spine")

Date: 2026-10-04. User-approved approach A (2026-10-04); approach B
(local-first rewrite) documented as future upgrade in D7.

## Context — evidence (live capture 2026-10-04, both phones + code)

1. **SSE churn**: every navigation → `getCurrentUser` → `_backgroundRefresh`
   → `authRefresh` → new token fires `authStore.onChange` → full SSE
   teardown+rebuild. 54 rebuilds/25min (Samsung). Events lost in every
   rebuild window → stale home, badges, messages (user bugs B6/B11/B12).
2. **Chat open cost**: full latest-40 refetch + serial per-row decrypt+upsert
   → first UI emit 6s after fetch. No incremental cursor (B4).
3. **Watch storm**: 1057 stream emits/25min; every DB write re-runs every
   open conversation's query (B4/B11/B12).
4. **Defunct-element crash** via `watchConversations().asyncMap` — kills
   provider chains → home blank/stale (regression of the Jul `defunct` fix).
5. **Redmi bg-isolate DNS race**: FCM pre-cache dies with `Failed host
   lookup` → stale-on-open (B6 on Redmi). (FCM itself works on Redmi now —
   memory was outdated.)
6. **Logout bleeds data**: `signOut` clears token/settings only, never
   Drift/keys (B1).
7. **Jump-to-message bails** silently when target not loaded (B3).
8. **Send path is fine**: bubble paints 12–60ms after tap, server ack ~0.7s
   (B8 delay is downstream of 1–4, not the send path).
9. **Dup bubbles**: FCM bg-isolate `localId=serverId` placeholder rows race
   main-isolate rows; `dedupByServerId` is a bandaid (B2).

## Decisions

- D1: No schema change beyond one index (serverId UNIQUE) — architecture
  stays; spine fixed.
- D2: Realtime stays the live path; poll fallback stays for real outages.
- D3: No new dependencies.
- D4: Standing rules carry over: no commit until user's 2-device PASS;
  `flutter analyze` 0 errors after every task; probes on live server for
  any rule/schema touch (none expected).

## Design

### D1. Auth/realtime spine

- Token refresh: resume + interval only. `getCurrentUser`'s cached path
  must NOT call `_backgroundRefresh` (keep it only for the no-cache path).
- `authStore.onChange` reconnects only on identity change: user id
  transition or valid↔invalid flip — never on token-string churn.
- SSE rebuild wrapped in existing `_serialize` + 1s debounce.
- Pass: a 10-min session with navigation shows ≤2 rebuilds in logcat
  (`Auth token changed` + `Realtime subscriptions established` lines).

### D2. Incremental sync

- Per-conversation cursor `lastSyncAt` = max server-`created` cached,
  stored as `sync_cursor_<convId>` in the existing Drift settings table
  (survives restart, no schema change).
- `_fetchAndCacheMessages`: fetch `created > cursor`; full-40 only when
  local cache empty.
- Row caching: `decryptBatch` (exists in encryption service) + Drift
  `batch()` insert — one round, not 40 serial awaits.
- Pass: warm open renders cache instantly, delta lands <1s; cold open <2s
  (timed in logcat: fetch→first-EMIT).

### D3. Throwaway-proof writes

- Drift migration: UNIQUE index on `messages.serverId` (nullable column —
  partial index on non-null only; pending rows with null serverId coexist).
- All message upserts become conflict-target on `serverId` (+ `localId`
  conflict-target for pending rows). bg-isolate placeholder writes become
  harmless (same row, updated in place).
- Remove `dedupByServerId` + tolerant multi-row getters (single-row
  lookups now safe).
- Pass: `flutter test` (new index migration test) + send/echo probe never
  shows two bubbles in logcat/UI.

### D4. Storm + crash

- `watchConversations().asyncMap` → synchronous mapping over cached joins
  (kills the defunct-element crash class).
- `_rowsToMessages`: per-conversation cached cutoff (invalidate on
  membership change); T2 visibility filter stays but costs no queries per
  emit.
- Pass: 10-min logcat shows emits only on real writes (no multi-conv
  re-emit per row write), no defunct exceptions.

### D5. Session hygiene

- `signOut`: close Drift, wipe all tables (or delete DB file), clear
  secure-storage keys, cancel poll/reconnect timers and in-flight chains.
- bg-isolate network calls: await connectivity / retry with backoff
  (kills the Redmi DNS race).
- Unread: fresh conversations (null `lastReadLocalId`) badge from the
  first message instead of never.
- Pass: logout→login-as-other shows zero old data (user check); Redmi
  cold-open-after-FCM shows the message within 5s (user check).

### D6. Jump-to-message

- All jump callers (search/star/reply/pin) use one path: ensure the row
  exists locally (server getOne + cache if missing), then precise
  `Scrollable.ensureVisible` with `alignment: 0.5`. Silent bail removed —
  failure shows a snackbar reason.
- Pass: 10/10 jumps land on the target (user check, old + new messages).

## D7. Future upgrade (approach B — recorded, not designed here)

If D1–D6's ceiling disappoints (heavy multi-device usage, offline-first
requirements), upgrade to a local-first sync engine: an outbox with
per-collection cursors and explicit conflict resolution, where realtime
becomes only an invalidation signal and `resyncOnResume` becomes a
backfill pass over cursors. This supersedes D2's ad-hoc cursor but reuses
D3's idempotent writes and D1's identity-gated connection lifecycle. Not
in scope for this plan.

## Out of scope (logged, unchanged from W2 spec)

- Rejoin history loss, key-archive, rotation-gap messages, media keyless
  placeholder, leaver-rotation banner copy, getList 30-row cap.
