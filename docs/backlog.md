# Backlog — Kuch Bhi

> Single source of truth: not-done, half-baked, and decided-for-future work.
> Status tags: `[DECIDED]` agreed direction · `[PARKED]` plan written, not started · `[BACKLOG]` known gap, no plan yet · `[MINOR]` deferred polish.
> Last updated: 2026-10-10.

## 0a. Brand & product assets `[BACKLOG]` (user-raised 2026-10-06)

- **Logo / wordmark** — none exists. Needed for: launcher app icon (currently default Flutter icon), splash/onboarding, About screen, store listing, GitHub README.
- **App icon set** — adaptive Android icon + iOS + favicon, all Warm Pop palette (Marigold/Capybara — mascot could BE the logo mark; decide when designing).
- **Store presence** — listing copy + screenshots (nothing exists yet).
- **PRODUCT.md** — impeccable expects it via `/impeccable init` (audience/voice record; spec Phase A noted it as "useful for later website copy" — never created).
- **Crash reporting** — none today; failures only surface via debug logs/device testing (user-confirmed genuine, 2026-10-07).
- **i18n / localization** — app is English-only hardcoded; adding later means touching every string — decide before UI freezes.
- **Onboarding / copy tone doc** — voice & tone for UI strings (pairs with PRODUCT.md).
- **Account data export** — GDPR-ish escape hatch, no export path exists.

## 0b. Future hardening tools `[NOT PLANNED]` — note only (2026-10-07)

*Not scheduled. If grep gate proves brittle or severe bugs/crash waves hit, reach for these:*

- **Dependency-rule enforcement via `import_lint` or `dart_code_linter`** — robust package-level version of the grep import gate (typed rules, no regex drift).
- **Fault-injection in CI** — fake network layer that throws on EVERY call, full test suite run against it. Catches runtime bypasses the import gate can't see (platform channels, third-party SDK phoning home).

## 0. NOW — Offline-first architecture `[DECIDED]`

**Decision (2026-10-06):** offline-first BEFORE any further UI work. Root cause: >90% of bugs are frontend↔backend seams (key-not-ready blocks fetch → "message loading" failures; SSE races; PB hook fragility). Server-side additions = highest bug rate; hardcoded single-task code = lowest.

**Shape (agreed sketch, needs brainstorm → spec → plan):**
1. **UI reads Drift ONLY** — no network in render path. Loading = DB emptiness, not requests.
2. **Ingest worker**: SSE/PB → decrypt → Drift → notify. Key-not-ready → retry queue + placeholder rows; NEVER blocks render.
3. **Outbox for sends**: local insert + queue → worker pushes → per-row status (column exists).
4. **No server/hook changes** in this phase — quarantine complexity, don't extend it.

**Mock-build strategy `[DECIDED]`:** new screens built standalone first — fully working UI, zero DB/network wiring (fake/in-memory data), iterate freely; wire to backend only after the screen works. Synergy: screens consume repository interfaces (already exist in `lib/infrastructure/repositories/`) → mock impls for dev, real impls = Drift ingest.

**Success criteria `[DECIDED 2026-10-07, B-mod]`:**
1. Airplane-mode matrix: every screen functional offline on a seeded device; sends queue → deliver on reconnect; key-delay → placeholders (never blanks).
2. **Production-failure cases in matrix:** kill app mid-queue → relaunch offline (queue survives); reconnect after long gap (hours) — these are where it actually fails/passes today.
3. Hard grep gate: ZERO network imports outside `lib/infrastructure/` — covers `http`/`Dio`, `dart:io HttpClient`, `WebSocket`, `web_socket_channel`, Firebase + any SDK that touches network (loophole-free; user-specified list).
4. Automated: full suite runs against fake repos (zero real network paths).

**Media offline policy `[DECIDED A+4, 2026-10-07]`:** metadata always offline (bubbles render from rows); bytes = on-demand download + disk cache with explicit per-blob states (queued/downloading/ready/failed). Four standing rules (user):
1. **Failed ≠ offline** — offline = stays `queued`, auto-resumes on reconnect; only dead URL/expired link = `failed` (manual retry).
2. **Startup recovery** — stale `downloading` rows → `queued` + orphan temp files cleaned (kill mid-download must self-heal).
3. **Size cap + eviction trigger decided up front**: 300 MB **default as config constant** (tunable when real usage data says so), deferred eviction (app start + 85% watermark — never on write path), protected set = un-uploaded outgoing + starred/pinned.
4. **Outgoing media protected** — local original never LRU-evicted until upload confirmed (it's the only copy).

**Approach `[DECIDED 2026-10-07]: 1 — Unified Ingest Pipeline`, with 5 execution guards (user):**
1. **Fixed extraction order + characterization tests first:** char tests → outbox state machine (data-loss risk first) → media states → ingest boundary → cache policy. Each cut shippable alone; never mid-refactor broken.
2. **Single boundary truly single:** SSE + fetch + outbox-drain share ONE entry point and one transaction ruleset; no SSE "fast path" (fast path = tangle renamed).
3. **Ciphertext rule decided up front:** model carries explicit not-yet-decrypted state; UI placeholder = same "placeholders never blanks" law as media.
4. **Grep gate LAST:** enable http/Dio gate only AFTER screens moved to repos (early gate = red CI for weeks = ignored gate).
5. **Scope guard:** extractions behavior-preserving; every behavior change = its own commit.

**Evidence:** `MissingKeyException` on group-key fetch gates message load; SSE-race root cause (2-device testing); pb-hook opaque-400 ladder; broken cron hooks (server-topology memory).

## 1. Parked plans (written, ready to execute)

- `[PARKED]` **W3 widget-gaps mini-plan** — `docs/superpowers/plans/2026-10-06-w3-widget-gaps.md`
  - T1 Font selector (P11 Jakarta, Drift clone of theme pattern, gates 11)
  - T2 Capybara Tier-1: squash-on-tap + success bounce (gates/keys `capy-scale`)
  - T3 Placements: profile header + StatusBanner leading (gate 12)
  - Rationale parked: offline-first first (user, 2026-10-06). T2 is a PREREQUISITE for mascot C4 (send bounce) — run it before chat restructure.
  - Skills section inside plan (executing-plans, TDD, verification, impeccable, taste, requesting-code-review).
  - Mockup gate waived → device proof + PASS per commit (ledgered ruling needed at start).

## 2. UI work queued

- `[DECIDED]` **Chat screen restructure** (mockup = ground truth; brainstorm first):
  - Meta hidden by default; **Instagram + mascot hybrid**: swipe-left reveals per-message time; delivery/seen status at thread end; header mini-mascot tap = info/x-ray mode (receipts/summary).
  - Seamless navbar+composer: one continuous surface container, no divider.
  - Pinned message: full-width band → floating compact pill (tap expand, swipe dismiss).
  - Inspiration: `docs/Inspiration/` folder.
- `[DECIDED]` **Home reconciliation** — mockup had no top navbar (floating title) + rounded-rect chat cards with gaps; current feels disconnected. Diff against `docs/mockups/2026-10-05-home-chat.html`, restore card treatment.
- `[DECIDED]` **Mascot shortlist (limited; more ⇒ Rive later):**
  - Chat: C1 header-buddy info mode · C2 swipe companion (clock reaction) · C4 send-success bounce (needs §1 T2) · C5 failed-send concerned pose · C7 empty-chat = static + text below (no animation).
  - Elsewhere: E1 offline banner sleepy (StatusBanner) · E4 cold-start sync-hold.
  - Spec law: never in bubbles, never behind text, never every screen. Tier 2 list = typing, offline-sleepy, key-rotation dance, PIN-restore celebration, sync-hold (spec "built on demand").
- `[BACKLOG]` **Media screens** — "no proper work at all": media boxes, photo/video viewer, docs grid need real design pass (viewer currently = chewie defaults). Inspiration: image-banner message style (`docs/Inspiration/Image_banner_that_looks_cool.png` — avatar overlap, header text, horizontal photo carousel in-bubble, facepile+🔥 reactions, 👍/👎 actions) + voice recorder UI (`Functional_and_visually_pleasing_Voice_note.png` — centered, timer, thin waveform, mic; **violet accent → recolor Marigold if adopted**).
- `[BACKLOG]` Voice-note bubble polish (current waveform acceptable; inspiration captured for redesign).

## 3. Architecture / backend (pre-existing)

- `[BACKLOG]` **Key-archive** — from W3/W1 audit findings (kuch-bhi-audit-findings memory); zombie-key lesson recorded.
- `[BACKLOG]` **FCM `FIS_AUTH_ERROR`** on Redmi `c7e9f10e` — notifications dead; messaging+ticks ride SSE (fcm-not-working memory).
- `[BACKLOG]` Server: broken cron hooks, schema gaps (server-topology memory). **Constraint:** never retry PB superuser password/record mutation without explicit ask.
- `[MINOR]` pb-hook pitfalls already documented (flat hooks, heredoc strips `$app`, opaque-400 ladder, no server date cutoffs).

## 4. Perf / dev tooling (W3 Phase C)

- `[DECIDED]` **Phase C** = frame-drop work (spec §Frame-drop, Redmi S2 before/after numbers) + **D5 dev options** (spec §D5: version ×7 → hidden panel: export logs, verbose toggle, clear image cache, perf HUD, copy diagnostics + 2000-line ring-buffer logger). Sequencing: after offline-first? relative order open — decide when Phase C approaches.

## 5. End-game

- `[DECIDED]` **UI consistency sweep LAST** (radius/buttons/menus/spacing/type across all screens) — only when ALL UI complete (media viewers still pending). Driven by impeccable audit checklist. Tokens already exist (Phase A); this is enforcement.
- `[DECIDED]` **Rive = spec-amendment option**, deferred until Tier 2 demands it (~max 10 animations needed now; native rig suffices). If revisited: layer the approved SVG (no redraw), State Machine, `rive` Flutter pkg.

## 6. Deferred minors (from W3-B final review)

- Gate 4 lacks `Color(0x` ban · gates lib-only (mockup `--error` stale `#C4402F` vs token `#E5484D`) · plan says `avatar`, code `avatarUrl` (plan text stale) · Inter font still bundled in pubspec (spec = system + optional Jakarta; needs cleanup commit) · requests badge `t.error` (semantic red, accepted).

## 6b. Offline-first post-plan (2026-10-10, user rulings)

*From the `feature/offline-first` plan close-out. I2 (seal previews) and keyless sealed-text outbox are NOT here — user overturned those to pre-merge blockers.*

- `[DECIDED]` **Delete + reaction offline wiring — priority 1.** Must mean defined offline behavior (server-confirmed delete, queued reaction), not silent failure. (user, 2026-10-10)
- `[DECIDED]` **Unwired offline kinds (pin etc.)**: disabled control or clear message offline — never silent failure. Star already gets local write pre-merge (protected-set depends on it).
- `[BACKLOG]` **FCM bg / receipt / social-sync / auth routing** — I3b/I4 §4 carve-out follow-up: route these writers through IngestBoundary (spec §4 text amended pre-merge to document current carve-outs).
- `[MINOR]` mediaFileProvider non-autoDispose caches null — bubble stuck placeholder after re-fetch until restart (M2, pre-plan).
- `[MINOR]` chat_screen ref-after-dispose StateError (:177/:230) + groupKeyReadyProvider defunct-element spam ~4s (M3, pre-plan bbb7d82).
- `[MINOR]` watchPinnedMessages one-shot stream — add broadcast ping when a pinned-consumer screen lands (T12).
- `[BACKLOG]` USE_FAKES + chat body reads hit `as MessageRepositoryImpl` cast → soft-fails to placeholder; chat fake work belongs to future fake-backed chat screens (T12 carry-1 residual).
- `[BACKLOG]` bodyCache LRU eviction unit test (bounded 500 — untested eviction order).
- `[BACKLOG]` onApplied pin (decrypt apply epoch race polish).
- `[BACKLOG]` DM key refetch path (key rotation while cached key stale).
- `[BACKLOG]` Matrix R3/R4 second-device re-runs — executed pre-merge P5 when 2 devices attached (2-device SSE echo + idempotency unverified).

## 7. Reference

- Specs: `docs/superpowers/specs/2026-10-05-w3-warm-pop-design-system.md` (binding), W1 reliability, group-invites.
- Plans: `docs/superpowers/plans/` (W1, W3-A, W3-B, widget-gaps parked).
- Inspiration: `docs/Inspiration/` — add screenshots here per element/design liked.
- Mockups (approved): `docs/mockups/2026-10-05-*.html`.
- `[BACKLOG]` Membership reconciliation false-positive: group CREATE racing an in-flight conversations fetch -> server list predates new group -> false "You were removed" + local role=left (W1 #17 path; observed 2026-10-11, conv r4-trig). Fix = require consecutive misses or refetch before removal verdict.
- `[MINOR]` Duplicate "X joined the group" system message (x2) on invite-accept.
- `[MINOR]` Stale outgoing-invite row persists in Group Info after invite is accepted.
- `[BACKLOG]` Fresh-group composer disabled on first open (user-reported 2026-10-11) — close+reopen works; root-cause the initial disabled state.
