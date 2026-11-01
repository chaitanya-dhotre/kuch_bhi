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
- `[VERIFIED 2026-10-17]` **FCM `FIS_AUTH_ERROR`** on Redmi `c7e9f10e` — RESOLVED (root cause 2026-07-27: user NextDNS blocking `firebaseinstallations.googleapis.com`; user allowlisted `*.firebaseinstallations.googleapis.com` on both devices). E2E tested today: both devices cold-start → token registered + permission authorized, zero FIS errors; server hook → webhook → Google 200s (also Oct 13/16 logs); synthetic push delivered to BOTH devices in <1s with posted notification (logcat `onNotificationPosted com.chai.kuch_bhi` + shade visible). No code defect. Dependency: the NextDNS allowlist rule must persist. Optional hardening only: in-app FIS-failure visibility banner (deferred from 2026-07).
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
- `[DECIDED]` **Disappearing-messages data loss (user-reported 2026-10-12, Samsung M52, Avium).** Root cause proven: `_companionFromRecord` stamps `expiresAt = createdAt + duration` RETROACTIVELY on all history (message_repository_impl.dart:3626); `watchMessages` purges expired rows on every chat open (:736 / messages_dao.dart:230); W1 cursor then blocks re-download → permanent local loss. Session 1 hides it (purge runs before first fetch; visibility gate ignores expiresAt). Turning the feature OFF does not clear existing stamps — surviving rows keep live fuses. User confirmed duration was ON, then turned it OFF; scroll-up test NEGATIVE (server cron also hard-deleted) → affected history unrecoverable; fix = prevention only. Scope: (1) stamp only messages created AFTER enable — never retroactive history; (2) duration→0 (and duration change) clears/restamps existing local `expiresAt`; (3) audit server `disappearing_messages.pb.js` cron for retroactive server-side deletion (SSH to VM unreachable 2026-10-12 — IP/connectivity suspect). User paused voluntarily; resume on request ("fix it").

## 8. Production readiness — group key/rotation hardening (2026-10-13)

*Source docs (both in repo root docs/, both UNCOMMITTED along with the code they describe):*
- `docs/2026-10-13-production-readiness-changes.md` — summary + repro + retest checklist
- `docs/2026-10-13-production-readiness-changes (2).md` — full detail: 14 client + 9 live root causes, changes, backups, invariants, limitations

*Status: applied to working tree (12 files, +610/−300) + live PocketBase rules hardened (backups `/opt/pocketbase/...20261013-group-hardening-pre`), targeted tests PASS, analyze 0 errors, debug APK installed on emulator-5554. NO commit created — user to review tree before committing (do not stage unrelated pre-existing files).*

- `[DECIDED]` **Incident**: post-rotation cold start hid all pre-rotation group history (cold fetch = newest key only → `pending` → visibility gate hid rows before lazy decrypt). Fixed via versioned key slots (`group_key_<convId>_<version>`), multi-key candidates through all fetch/decrypt/repair paths, fail-closed cutoff on missing membership, rotation no longer deletes old key rows, collision-retry, pubkey preflight on create, leave/removal cleanup, pubspec asset fix.
- `[ACTION]` **Required real-device retest** of the repro (doc 1 §"Live Test Result Before the Final Fix" / §"Required Retest"): stop + clear cache → reopen → pre- and post-rotation messages visible, no "group key missing". Plus two-device matrix (kill-before-rotation, cache-clear, join-during-offline, remove-while-offline, leave+rejoin, concurrent rotations).
- `[ACTION]` Run FULL flutter test suite on target toolchain before release (only targeted tests ran).
- `[BACKLOG]` Historical key rows deleted by OLD prod code unrecoverable (e.g. group `4chan`: only versions 16–17 retained, July messages stranded) — needs DB-backup restore or accepted loss.
- `[BACKLOG]` Server-side atomic key-publication endpoint (membership snapshot + one txn per version); current = prepare-all-then-write best effort.
- `[BACKLOG]` Rotation-pending message blocking (membership delete vs rotation = separate ops; offline gap keeps old member able to decrypt until rotation lands).
- `[BACKLOG]` Server-side history cutoff disabled by design (prior back-reference rule erased old-member history) — needs tested membership-epoch model before enabling; current boundary = client cutoff + E2E key possession.
- `[BACKLOG]` Group creation rollback is best-effort — orphan server rows possible after partial create + connectivity loss.
- `[MINOR]` Startup frame skips on emulator · FcmDebugHelper second AppDatabase Drift warning · Gradle/AGP/Kotlin future-compat warnings · repo not lint-clean (warnings/infos remain).

### 8.1 Code-review findings on the 2026-10-13 diff (pre-commit pass)

Fix-candidates ON this diff (edge combos — not touched, reported before commit):

- `[BACKLOG]` `clearCurrentGroupKey` (secure_storage_service.dart:121) deletes the NEWEST versioned slot on leave/removal → leaver loses recent entitled history; doc comment claims historical stays readable. Fix: clear base slot only, keep versioned slots.
- `[BACKLOG]` Optimistic enqueue seals with stale cached key (getCachedGroupKey) but drain unwraps only with CURRENT key → after rotation + process kill the send defers forever, silently (message_repository_impl.dart:4191). Fix: drain unwrap via row keyId fingerprint / candidate keys.
- `[BACKLOG]` `getOrFetchGroupKeyCandidates` ignores requireCurrent on transport failure (publishes under stale key → undecryptable for post-rotation members) and can demote base slot to an older version before throwing (encryption_service.dart:523).
- `[BACKLOG]` `_decryptBatch` multi-key: all-candidates-fail + keys.length>1 forces key_missing forever — corrupt rows never reach terminal failed (decrypt_pass.dart:389). Also: AesGcm/SecretKey built per item×candidate — hoist per-key setup (decrypt_pass.dart:369).
- `[BACKLOG]` Create-group rollback leaves orphan `group_key_*` secure-storage entries + 2×N getUserRecord round trips (create_group_screen.dart:330).
- `[BACKLOG]` getCachedGroupKey/candidates use secure-storage readAll() (all keys) on send/decrypt hot path — prefix-read or in-memory index (encryption_service.dart:428).

Pre-existing (offline-first era, NOT this diff — surfaced by same review):

- `[BACKLOG]` Pinned banner / ReplyQuote / context-menu Copy read session-cache-only decryptedBody → after background-clear show 🔒 / lose Copy until bubble decrypt re-runs (pinned_message_banner.dart:32).
- `[BACKLOG]` toggleStar writes message_preview from cold bodyCache → starred screen permanently blank row (message_repository_impl.dart:1909; `?? 🔒` never fires for -string).
- `[BACKLOG]` retryPendingMessages skips text rows when bodyCache cold → legacy pre-outbox pending rows stuck forever after restart (message_repository_impl.dart:1578).

- `[FIXED 2026-10-13]` **False "You were removed" on freshly-created group (live-repro 2026-10-12, emulator Pixel Chait / shreysaw76).** Created group "R0-retest" with 1 member; within seconds chat showed "You were removed from this group" + "no longer a member" composer block, group dropped from chat list, header member count fell 2 -> 1. Root cause: conversations list fetch predates new group -> reconcile verdict treated missing-from-list as removal. Fix = consecutive-miss (2) + confirmation point query before verdict (`message_repository_impl.dart` reconcile loop; `_removalMissCounts` + `_removalConfirmMisses`, cleared on identity change; probe error = no verdict). TDD: `test/offline/removal_reconcile_char_test.dart` RED×3 → GREEN×3, full suite 170/170, analyze 0 errors. NOTE: also blocked clean on-device rotation retest via a fresh group — Gate 2 ran on an existing group with retained key history instead.
- `[FIXED 2026-10-13]` **Chat open showed 🔒+bar 1–5s before messages rendered (user report: "offline app, should be instant like WhatsApp/Signal").** Root cause: DISPLAY decrypt path (`DecryptPass.runFor → _resolveKeys → getOrFetchGroupKeyCandidates`) was network-first for any logged-in user — every chat open blocked on a sequential per-conversation `group_keys.getFullList` roundtrip even with all keys cached (measured `runFor ids=9 total=4704ms`, `localCached=2` on every call). Fix: local-first return for `requireCurrent:false` callers + deduped background revalidation (`_scheduleGroupKeyRefresh`) + `onGroupKeysRefreshed(grew)` → DecryptPass re-queues rows the stale set could not open (incl. scoped `failed→key_missing` re-queue under a newly-grown key set) and re-runs them. Send/outbox path (`requireCurrent:true`) unchanged: network-authoritative, refuses stale-cache send. TDD: `test/offline/group_key_local_first_test.dart` (A/C/D RED → GREEN, B send-pin), full suite 174/174, analyze 0 errors. Live: all message texts render ≤700ms after cold open (was 1–5s).
- `[BACKLOG]` **Local-only system bubbles have no body source after process restart.** `_emitLocalSystemMessage` writes the text ONLY into session `bodyCache` (single caller: removal verdict); after restart the row renders 🔒+bar FOREVER (runFor skips empty ciphertext — nothing can re-derive it). Visible now as the stale "You were removed from this group" row in R0-retest (residue of the fixed §7 bug — won't regenerate). Constant, non-E2E text — candidates: persist label, render-side constant fallback, or cleanup migration for local-only system rows.
- `[FIXED 2026-10-13]` **D1+D2 follow-up to the #67 loading fix (M52 video review).** D1 — `hasUsableKey` (message_repository_impl.dart) was network-first (`getOrFetchGroupKey(requireCurrent)`) behind `groupKeyReadyProvider`'s 3s poll → the "Waiting for a group admin…" composer banner showed on every cold-process open even with warm keys (M52 probe). Now returns from `getOrFetchGroupKeyCandidates` local-first (background revalidate; cold cache still contacts server — D1-negative pins it). D2 — `prefetchGroupKeys()` (repo) hydrates any group whose key set is not resident after every conversation sync (resyncOnResume + post-login home watch; `_prefetchKeysInFlight` dedupe; `EncryptionService.hasLocalGroupKey` = single local storage scan, no network) so a chat open never pays the network — even first open after install. TDD: 4 new tests in group_key_local_first_test.dart (D1 / D1-negative / D2 / D2-skip) RED→GREEN, suite 178/178, analyze 0 errors. M52 live: cold-process open → decrypt ≤0.5s, NO banner, composer instant; prefetch log `warm=18 hydrated=0` (all convs warm post-Gate-2).
- `[BACKLOG]` **Stuck `pending` rows in historical convs = key-loss class (found while verifying D1/D2 on M52).** e.g. group `zrwszx3uifdjlkn` ("3 Oct Test"): all 8 rows `decrypt_state='pending'` forever — repair runs every open with the 3 locally-held keys and all fail (ciphertexts under historical key versions this device can no longer obtain: Gate-2 `pm clear` wiped the OLD keypair, so pre-relogin `group_keys` envelopes are unwrappable — same class as §8 "historical keys unrecoverable", worsened by relogin). UX today: home preview 🔒+bar; open → `isGroupRowVisible` hides all non-`ready` non-media rows → EMPTY chat ("Say hello 👋") with no explanation. Counts across M52 DB: zrws 8/8, hnj3 75, s0we 42, ajhv 21, d33o 15 pending. Recovery candidates: (a) admin re-wrap flow — an admin device that still holds K_old re-encrypts it to the member's CURRENT pubkey. **Fixes (b) + (c) DONE 2026-10-28** — see the `[FIXED]` line below.
- `[FIXED 2026-10-28]` **Key-loss UX — unrecoverable history no longer looks brand-new, and stops being retried every open (backlog §170 fixes b + c).** (b) `MessageRepository.countUndecryptable` returns how many rows exist but are hidden because their body cannot be decrypted, sharing the repair pass's query; the chat's empty state branches on it via `chatEmptyKind` (`chat_run_grouping.dart`) and shows "Older messages unavailable / Ask a group admin to re-share them" instead of "Say hello". The read path is UNCHANGED — spec D1, ciphertext still never reaches a bubble. (c) `_repairUndecrypted` has a per-conversation give-up budget (`_repairGiveUp` = 2 fruitless passes) so a row this device provably cannot heal stops costing an indexed query per open; the budget reopens on any membership/key change (folded into `_invalidateCutoff`), and its accounting runs from EVERY exit path — the `MissingKeyException` and error paths are fruitless too, and counting only the full loop left the budget permanently at zero. Also fixed the log line that printed `rows.length` (the number ATTEMPTED, so a pass that healed nothing claimed to have healed everything). Tests: `test/offline/undecryptable_state_test.dart` (count + give-up budget) and `test/chat_empty_kind_test.dart` (copy decision), both RED→GREEN. Suite 307/307, analyze 0 errors. Residual: the give-up budget has no seam through the repo's `late final` DAO accessor, so the "does it stop" proof rides `@visibleForTesting debugRepairRuns` rather than a query spy.
- `[BACKLOG]` **Backup-PIN skip window (7 days) — user ruling 2026-10-17 (keep 1+2 for later)**: no-backup accounts skip `needsSetup` for max 7 days (`encryption_sync_provider.dart` `pin_backup_skipped` + 7-day recheck); a device wipe INSIDE that window generates a fresh keypair → new pubkey published → old per-user envelopes unwrapable = same key-loss class, bounded to that user's pre-re-key history until an admin re-wrap (fix (a) above) or force-setup (remove skip). Paired with §8's atomic-publication endpoint (line above) as the two accepted residuals of the 3-Oct incident; both deferred by user 2026-10-17.
- `[BACKLOG]` **Riverpod defunct-element crash on chat navigation (observed M52 19:23:30).** `ConsumerStatefulElement.watch` → `markNeedsBuild(_ElementLifecycle.defunct)` Unhandled Exception, stack through `StreamProviderElement.onData` — a provider emits to an unmounted Consumer after route transition (receipt updates racing dispose). Debug-only assert (release continues) but leaves provider chain dead → chat can sit on empty/loading until rebuild.
- `[MINOR]` `prefetchGroupKeys` takes ~30s for 18 groups — `hasLocalGroupKey` does base-slot `read` + full `readAll` per conv over the platform channel (Samsung). Fix: one `readAll` per prefetch pass, filter prefixes in Dart (same shape as §8.1 hot-path readAll note).

- `[DIAGNOSED 2026-10-14]` **Reload-on-focus-loss + slow previews/chat-open (user 3-symptom report; DIAGNOSIS ONLY — fix decision deferred).** Root = architecture decisions, all deliberate: (1) spec §3 "no plaintext at rest" → DB holds ciphertext only → EVERY render is a decrypt; (2) `bodyCache.clear()` on `inactive`/`paused` (app.dart:61-69, spec §3 amend 6) → ANY focus loss (notification shade, recents, HOME) purges decrypted bodies; (3) `resyncOnResume` on every `resumed` (app.dart:58) → full refetch of ALL 18 convs in chunks-of-3 + per-conv key resolve + re-cache → `watchMessages EMIT` storms = "messages refresh"; (4) bodyCache is memory-only LRU 500 → process death wipes it → EVERY cold open = first-open cost (why reopen-after-kill never got cheaper). **Live proof (M52 2026-10-14):** one notification-shade pull → `resyncOnResume` + 18× `_fetchAndCacheMessages` + 17× `[Enc] local-first` key re-resolutions over ~15s; chat open + shade → screenshot at +0.4s shows ALL bubbles 🔒, local-first re-decrypt for open conv at +0.45s. **Symptom costs measured:** cold home = ~5s splash + skeleton + sequential per-conv `_resolveKeys` (each = secure-storage `read` + full `readAll` platform-channel pair, Samsung slow) serialized behind backfill/prefetch/bg-refresh → previews pop progressively 9-12s+, worst >10s; chat open after app open = fetch + repair + display runFor ≈1.3-2s (15:14:00→01.1 log delta). **Secondary finding F2:** delta filter `created >= cursor` inclusive (sync_cursor.dart:18) → boundary row re-fetches EVERY resume → every conv "fetched 1" even when idle → full decrypt+re-cache cascade with zero new activity (3/3 resumes logged 18×"fetched 1"). **Industry model (researched):** Telegram = plaintext local SQLite (`cache4.db`, MessagesStorage.java — no local encryption at all); WhatsApp = internal msgstore.db not encrypted (OS file-based encryption only); Signal = SQLCipher whole-DB, key in Keystore/TEE, unlocked ONCE per process; Instagram DMs = E2E opt-in, plain local cache. Common pattern: decrypt ONCE at ingest → durable local store → render = direct DB read; NONE purge decrypted content on focus loss. **Decision menu (user picks later):** (a) durable post-decrypt store (relax §3 to OS-FBE/SQLCipher protection — industry model); (b) clear only on `paused`, not `inactive` (shade pull stops flashing; recents/HOME still clear); (c) keep policy, make re-decrypt invisible (in-memory key cache — kills per-conv readAll; parallel key resolve; resume prewarm before widgets rebuild); (d) device-key-wrapped disk snapshot of decrypted bodies. F2 cursor `>` fix is independent + cheap (kills idle cascade in all options). Open item: exact Riverpod-level provider reset during the covered shade window bounded but not instrumented (invalidate vs autoDispose remount). Video refs: `docs/Screen_Recording_20261014_143119_Telegram.mp4` vs `docs/Screen_Recording_20261014_143215.mp4`. → **RESOLVED 2026-10-17 by §9** (menu options b + c + F2 executed; (a) rejected for now; (d) unnecessary once c landed).

## 9. Idle-cascade + cold-start arc (2026-10-14…17) `[DONE]` — commit `85579a5` (pushed)

Decision menu above executed as F2 + C + B + Prewarm, then hardened by adversarial review (workflow, 14 findings → 4 confirmed mediums, all fixed TDD RED→GREEN). Suite 204/204, analyze 0 errors.

- `[FIXED]` **F2 idempotent ingest** — unchanged rows classified no-op BEFORE key/decrypt work (`_filterUnresolvedOrChanged`, second-granularity compare; same-timestamp different-serverId rows retained). Star-sync skips already-starred rows.
- `[FIXED]` **F2b light resume <60s** — `_lightResumeCutoff` + `_deltaBackfillTargets` (one aggregate `created >= watermark` query, paginated max 10 pages/1000 rows, cap logged). Device: shade return → `path=light away=6s delta=0 fetch=0`.
- `[FIXED]` **C process-memory group keys** — `_memGroupKeys` (single storage scan per process, write-through `saveGroupKey`/`clearCurrentGroupKey`/`invalidateGroupKeyBase`/`clearAllGroupKeyCache`, wipe + session-epoch hooks); DecryptPass parallel key resolve. Chat open tap→text ≤0.9s (was ~2s locks). 5 raw-writer sites rerouted.
- `[FIXED]` **B purge only on paused** — `bodyCachePurgeSignal` (app.dart); shade = byte-identical frame; HOME/Recents/screen-off still purge (spec §3 intent kept).
- `[FIXED]` **Prewarm** — `prewarmHomePreviews(limit:15)`, newest-conv-first, local-only, single-flight, unawaited before sync/backfill; light path only when cache purged. M52: prewarm +2.2s ≪ first frame +5.1s ≪ backfill +7.4s; release build (user-confirmed 2026-10-17): home previews present at first frame.
- `[FIXED]` **Review C1a/C1b** — media ack + duplicate-create drain-ack recovery now stamp the SERVER `created` (device-clock + serverId rows poisoned the F2 watermark → quick resumes could silently miss rows when device leads PB VM). `server_created_watermark_test`.
- `[FIXED]` **Review C3** — `BodyCache.generation`; DecryptPass suppresses cache puts after a mid-pass purge (paused purge no longer repopulated by in-flight decrypts; DB verdict still lands).
- `[FIXED]` **Review C4** — delta discovery paginates (was single 100-row page).
- `[FIXED → a83e046]` **Review C2** (was accepted tradeoff, closed 2026-10-17) — light resume now runs user-scoped `_syncStarredMessagesUser`/`_syncDeletedForMeUser`/`_reconcileReceiptsUser` after the delta backfill: one query per table covers QUIET convs (tables user_id-keyed; only the conversation_id filter drops). Receipts use new DAO `messagesNeedingReceiptReconcile` (cap 100) + chunked-parallel execution (measured C2 segment ~0.9s on M52; serial was 1.8-2.1s). Resync end anchor added: `[Msg] resync done — path=... total=...ms`.
- `[MINOR]` Review K1 (killed): unguarded group-key background refresh can re-persist ENCRYPTED keys post-signOut — harmless (keypair retained by design; conv-id namespace disjoint); optional hardening = authStore check before refresh write.
- `[DONE → a70f020]` **In-chat decrypt still perceptible (user-confirmed on release build 2026-10-17)** → loading-UX work, executed as §10.

## 10. Loading-UX arc (2026-10-18) `[DONE]` — commit `a70f020` (pushed)

Lock→skeleton redesign per Astra recs §"Loading UX" (implemented by Astra, reviewed + verified by Claude Code). Attempt-1 rejected via change list (empty bubble, terminal+skeleton mix, text-revert after cache purge, permanent over-reserve, untouched pinned banner, T9.2 red); attempt-2 accepted.

- `[FIXED]` **MessageBodyText state machine** — cache fast-path; 150ms grace (invisible geometry reserve); 100ms `AnimatedSwitcher` fade; skeleton bars sized from ciphertext length (no layout shift); sticky resolved body (`_rememberBody` — purge never reverts text to placeholder); size-lock 100ms then `AnimatedSize` settles to natural layout (no permanent over-reserve).
- `[FIXED]` **Terminal state** — `key_missing`/`failed` = lock/error icon + "Can't decrypt" label, NEVER skeleton bars. Transient = bars, never a lock.
- `[FIXED]` **PinnedMessageBanner + ReplyQuote** — same state machine; blanket `'🔒 Encrypted'` fallbacks removed.
- `[SHIPPED]` Tests: `message_body_text_loading_test`, `pinned_message_banner_loading_test` (new); `placeholder_ui_test` + `read_paths_char_test` updated. Suite 209/209, analyze 0 errors. Device frames 13:46–13:47 confirm skeleton→text and skeleton→"Can't decrypt" (3-Oct class).
- `[NOTE]` User design note: expected whole-bubble skeleton (chrome skeletonized); accepted current text-inside-real-bubble; whole-bubble variant = optional polish in the UI/UX pass.
- `[RESIDUAL]` Media-card spinner can spin long (media pipeline, out of scope); 11:55 tofu = device emoji-font gap (out of scope); theoretical `""` body sticks on placeholder (composer blocks).
- `[DONE → a83e046]` **Tap-down predecrypt** (Astra recs) — `MessageRepository.predecryptConversation` warms the last 30 body-rendering rows (text/voice/system, cache-miss only, local-only); home tile kicks it via `Listener(onPointerDown)` (a parent `GestureDetector.onTapDown` never wins the arena against the tile's own tap — Listener is load-bearing). M52: TAPDOWN→chat open 514ms; cold n=15 decrypt 1.0-1.9s starting at press (overlaps transition); warm-cache repeat opens instant (`warm (0 misses)` log). First-ever cold open of a conv still decrypts live (~1-2s) — Astra's own doc: durable cure = SQLCipher store (measure-first, backlogged). Tests: `tap_predecrypt_test` (2).

## 11. Page 4 (Group info / create group) — open product decisions (2026-10-29) `[DEFERRED]`

Spec PASSed with these six at their defaults (`docs/design/pages/group-info.{html,md}`, "Deferred decisions"); Mimo/freebuff implemented the defaults while Omnirush is down (maintenance until 2026-11-02 17:30 IST). Parked here until the user revisits them; each override is a follow-up change, not a re-spec.

- `[DEFERRED]` **1. Create = direct add vs ＋ Add = invite.** Creating a group writes members straight away; adding from Group info sends invites. Default: keep both. Changing create to invites touches the repository + E2E key distribution — its own task.
- `[DEFERRED]` **2. Disappearing messages for non-admins.** Default: any member can change it (matches the chat menu). Alternative: admin-only in BOTH chat menu and Group info — needs a PocketBase rule check first.
- `[DEFERRED]` **3. Destructive colour.** `error` text is 3.91:1 on light surfaces (fails 4.5:1). Default: error-coloured icon + ink label. Alternative: a darker `errorText` token (foundation amendment).
- `[DEFERRED]` **4. Media & Docs after leaving.** Default: still visible to left members (media is local). Alternative: hide it.
- `[DEFERRED]` **5. Remove/Leave 30s UI bound.** Default: unlock after 30s with "Still working — this can take a moment." (repo call never cancelled/retried — it rotates the group key). Alternative: no UI bound on those two. **Concurrency risk FIXED 2026-10-29:** after the unlock, a second remove/leave in the same group could start a second key rotation alongside the first (and so could the join / key-gap background rotations). Every rotation now runs through one per-group queue in the repository (`SerialPerKey`, `lib/core/utils/serial_per_key.dart`); a stuck predecessor holds the queue for at most 2 min, after which the existing collision-retry in `_rotateGroupKeyNow` covers the rare overlap. Still per device: two admins on two phones rotating at once is handled only by that server-side collision retry.
- `[DEFERRED]` **6. Member row tap.** Default: admins can tap the whole row (not just ⋮) to open member actions. Alternative: ⋮ only.

## 12. Media + chat ideas (user, 2026-10-30) `[BACKLOG]`

Raised during the Page 9 (Media fullscreen) spec. Page 9 itself took only "where does the delete date show"
(viewer line, `docs/design/pages/media.md` B6). Everything else waits here. Suggested order for the media
tasks: Page 9 → 12.2 → 12.4 → 12.5 → 12.1 (12.2 reuses Page 9's blob-status provider; 12.5 needs Page 9's
viewer; 12.1 is independent and can go any time).

**Media tasks (from the Page 9 triage)**
- `[BACKLOG]` **12.1 Share into the app.** Photos, videos and files from other apps or a file manager. No
  `SEND`/`SEND_MULTIPLE` intent filter exists in `AndroidManifest.xml` today. Needs a receive plugin, a
  "send to which chat" picker, then the existing send pipeline (quality sheet included).
- `[BACKLOG]` **12.2 Media bubble states in the chat.** Deleted, can't decrypt, expired, failed download,
  loading, each with a clear look. Today photo/video bubbles have a skeleton, a broken-image icon and a 10.5px
  **Media expired**; no can't-decrypt or failed state; the expiry pill shows only in the last 7 days. Go
  after Page 9 (same files; reuses its read-only blob-status provider).
- `[BACKLOG]` **12.4 Media send.** Keep the original format (GIF/PNG/WebP as is; JPEG/HEIC still re-encoded to
  strip GPS, see the photo learning), sharper thumbnails (today 200px at 60%), and a simple crop / mark-up /
  video trim screen. No filters or edits. Merges Page 9 parked items 15a (GIF → JPEG) and 15b (thumbnails).
  Video trim needs a maintained native transcoder (the common FFmpeg Flutter wrapper was retired in 2025);
  check before choosing.
- `[BACKLOG]` **12.4b `pro_image_editor` fallback** (user, 2026-10-31). If the media-send page's built-in crop (the avatar
  cropper's pan/zoom under an Original/Square frame) doesn't feel good enough on the device, swap the editor's Crop +
  Draw to `pro_image_editor` with its filters, text and stickers turned off (`media-send.md` decision 15, alternative B).
- `[BACKLOG]` **12.5 Albums.** Several photos/videos sent together show as one bubble that scrolls sideways
  (reference: the user's mock; no like/dislike, reactions already exist), and open as an auto-arranged
  collage that fits each item by orientation, then fullscreen with swipe between items (Page 9 decision 6).
  Needs a way to know what belongs together: a batch id on the messages, or grouping by sender + time.
- `[BACKLOG]` Page 9 parked items, still separate: offline media resend that never retries · upload cancel ·
  Chat J8 download progress (no progress source) · 200% overflows on Home rows and the chat app bar's
  "Last seen" · no timeout on the media store's download (bound the `http.get` only, never around decrypt).

**Ideas (not media fullscreen)**
- `[IDEA]` **12.6 Voice recorder redesign.** Live waveform, timer, cancel ✕ / record / send (user's reference
  image: centred "Voice note" title, waveform, 01:14, three round controls). Accent only as fill, no purple
  (C1/C2).
- `[IDEA]` **12.7 Keep a message in a disappearing chat.** An option on one text, photo, video or document so it
  does not disappear when the timer runs out. Needs design: the purge runs on every member's device, so "kept"
  must reach the other side too, and media retention on the server is separate from the disappearing timer.
- `[IDEA]` **12.8 Multi-select that works.** Today you long-press each message and pick Select; then the only
  action is delete, and it deletes at once with no confirmation (confirmed: `chat_screen.dart:986-992`
  loops `deleteMessage` for me, no dialog; R20 `showConfirmDialog` exists). Wanted: once selecting, a tap adds
  a message; drag/range select for many; a confirm before delete; more actions (copy, star, forward if it
  ever exists, add to list 12.9).
- `[IDEA]` **12.9 Lists / notes per chat or group.** Pick messages of any type into a list, reorder them, merge
  several into one point (e.g. a sunset photo + its name + its location), add a note to each point, choose the
  style (plain, dotted, numbered, checklist), keep it private or share it with the chat. Example: an itinerary
  of hidden spots with location links.
- `[IDEA]` **12.10 Tags through lists.** Notes from 12.9 tag photos/videos so in-chat search can find them.
- `[IDEA]` **12.11 App lock.** PIN, biometrics or password to open the app. Not built today (the Settings learning:
  app lock "looks built but is not").

## 13. Device run + "Things To Fix Lol" list (2026-10-31) `[BACKLOG]`

From the user's own list in the "Things To Fix Lol" group (7 items, 2026-10-30/31) plus a debug run on the M52
(`flutter run`, Marionette, logcat) on 2026-10-31. Causes marked *confirmed* were read in code or seen in the log;
*likely* ones are not yet checked.

**From the device run (Claude):**
- `[FIXED 2026-10-31, uncommitted]` **13.1 Closing a chat throws, so its cleanup half-runs. Confirmed, high.** `ChatScreenState.dispose`
  (`chat_screen.dart:256`) calls `_pres.leaveChat`, and `_pres` is `ref.read(...)` (`:204`). Riverpod forbids
  `ref` in `dispose`, so it throws `Cannot use "ref" after the widget was disposed`. Everything after it is
  skipped: `replyProvider` is never cleared (this IS 13.6 below), presence never "leaves" the chat, and
  `super.dispose()` never runs, so the screen's provider listeners stay alive. That last part caused the 2
  `markNeedsBuild … _ElementLifecycle.defunct` unhandled exceptions in the log after opening the next chat.
  Seen on every chat close. Fixed: presence read once in `initState`; `replyProvider` is now an auto-disposed
  family per conversation, so no `dispose` write is needed and a reply can't cross chats; a grep gate fails any
  `dispose()` in lib that touches `ref` (proved RED on the old screen). Checked on the M52: reply in Avium, back,
  open another chat = no reply, and no ref/defunct errors in the log. 741/741.
- `[BUG]` **13.2 An open group chat re-writes the same receipt status in a loop. Seen, medium.** With
  "Things To Fix Lol" (8 messages) open, the log shows 17× `watchMessages EMIT` + 28×
  `[Receipt] Updating local message status to: sent (deliveredIds=1/3, readIds=1/3)` with no change in the
  values. Each write re-emits the whole list. Write only when the status actually changes.
  **Fixed 2026-10-31 (device PASS):** an unchanged status is no longer written.
  M52: 1 emit, 0 writes on open. Log: `docs/audits/bug-wave-3-work-log.md`.
- `[BUG]` **13.3 Home: "3 Oct Test" gains one unread every time ANY chat is opened. Reproduced 2026-10-31.**
  On the M52 it went 4 → 5 → 6 across three chat opens with no new message, and its preview flips from
  "Can't decrypt" to a skeleton that never resolves. Likely: an undecryptable message in that group is counted
  again on each open (the unread count or the undecryptable re-scan). Investigate before fixing.
  **Fixed 2026-10-31 (device PASS):** each resync re-ingests the undecryptable
  newest row. The badge guard compared ms against drift's seconds, so the badge went up every time.
  The re-ingest also wrote `pending` over `key_missing`, which left the preview on a skeleton.
  Log: `docs/audits/bug-wave-3-work-log.md`.
- `[NOTE]` 8× `[Enc] Skipping undecryptable group key version` at every start. Expected (historical keys from the
  2026-10-13 rotation are unrecoverable), but it is noise at startup. A full resync took 21s (`resync done —
  path=full total=20994ms`).

**User's list:**
- `[BUG]` **13.4 Video bubble length shows 0:00.** Cause (2026-10-31, code read + live read R1): client-side. The
  server stores `duration_seconds` (video 2/2 and voice 4/4 > 0). The bubble reads it from the thumbnail's
  `LocalMediaFile` (`vb`, `media?.durationSeconds ?? 0`). The record path fills it; the blob store's fast path (a row
  already `ready`, e.g. after a restart) returns no metadata, so it is null → 0:00. Fixed by the media-send spec's
  stored blob metadata (`docs/design/pages/media-send.md` C3, decision 3).
- `[FIXED 2026-11-01]` **13.5 Viewer: the video play/pause disc never hides while playing and covers the video.** Page 9's own
  controls; auto-hide the disc (with the bar) a few seconds after play, and show it again on tap. Reduced
  motion = no fade.
- `[FIXED 2026-10-31, uncommitted]` **13.6 Swipe to reply, then open another chat: the reply stays attached, sends there, and the other
  device can't decrypt the quote.** Root cause = 13.1 (`replyProvider` is global and never cleared). Also make
  the send path drop a reply whose message belongs to another conversation. The stray "Avium / Pakka?"
  quote-only bubble on the M52's Avium chat is probably one of these.
- `[BUG]` **13.7 Sending a photo shows two bubbles; the first disappears only once the upload finishes.** The
  uploading placeholder and the real message are both visible. One bubble that turns into the sent one.
- `[BUG]` **13.8 Your own photos show the download disc.** Known limit from Page 9: the sender's full copy is not
  kept in the media cache after upload. Fix: register the sent (compressed) file as a `ready` full blob on send.
  Belongs with 12.4 media send.
- `[FIXED 2026-11-01]` **13.9 Photo viewer zooms and pans into the black around the photo.** Likely: InteractiveViewer's child
  is the full screen, not the photo. Size the child to the photo's aspect so the edges clamp to it.
- `[FIXED 2026-11-01]` **13.10 A reply quote of an expired (disappeared) message shows the decrypting bar forever.** Show
  "Message expired" in the quote instead.

Suggested order: 13.1 + 13.6 (one fix, the crash affects every chat) → 13.2 → 13.4, 13.5, 13.9 (Page 9 follow-ups)
→ 13.3 (now reproducible) → 13.10 → 13.7 + 13.8 with 12.4 media send.
