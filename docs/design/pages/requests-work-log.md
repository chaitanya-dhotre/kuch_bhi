# Requests screen — implementation work log

Date: 2026-10-21  
Scope: Page 3 Requests redesign, checklist `docs/design/pages/requests.md`.

## Evidence

| Check | Result |
|---|---|
| Focused Requests gates | PASS — 37+ tests across screen, actions, pending count, snapshot, realtime, shadow, and grep gates |
| Full Flutter suite | PASS — 279/279 |
| Flutter analyze | 0 errors; command exits 1 on 94 non-error info/warning diagnostics |
| Diff whitespace | PASS — `git diff --check` |
| Device capture | PASS — Samsung Galaxy M52 (`SM M526B`, `RFCRA047WSJ`), 1080×2400 light + dark |

## Implemented

- Two independent request sources with partial/full error states and no false-empty flash.
- R11 request-shaped loading cards; R7 empty/error states; R9 group section count.
- Request and group invite feature cards with safe fallbacks, group glyph, a11y labels,
  offline action policy, and per-card busy locking.
- Notifier-owned accept/decline mutations with source invalidation and friendship refresh.
- Stable success/failure toasts; declines remain silent; removal announcement added.
- Home requests badge converged to R2 `AppBadge`.
- New test gates under `test/friend_requests/` plus Requests-specific grep gates.
- M52 evidence: `docs/design/pages/captures/requests-m52-light.png` and
  `docs/design/pages/captures/requests-m52-dark.png` (empty-state render, light/dark).

## Open / deferred

- I5 card-exit fade/collapse animation remains SHOULD and is not implemented.
- No commit created. User PASS remains required.

## Review pass (2026-10-22) — H3 + R1 + R2 landed

| Item | Result | Evidence |
|---|---|---|
| H3 cold-start offline cache | **IMPLEMENTED** | `RequestSnapshotCache` (per-user snapshot in `app_settings_table`); network-first, cache-fallback in both notifiers; `test/friend_requests/offline_snapshot_test.dart` 6/6 green |
| R1 SSE listener kill | **FIXED** | scoped `UnsubscribeFunc` retained and disposed in `lib/core/network/realtime_subscribe.dart` + `friend_query_service.dart`; `test/friend_requests/sse_scoped_unsubscribe_test.dart` 2/2 green (real PB realtime stack over a local SSE server) |
| R2 dark card shadow halo | **FIXED** | `WarmPopTokens.shadowLight/shadowDark` (foundation §4) read as `context.t.shadow`; render-verified — the white halo is gone; registry row T1 added |
| R2b shadow strength | **FIXED** | Material's elevation shadow paints materially weaker than the token (the engine routes it through a tonal path — measured ~7× weaker in a pixel probe); raised cards now use an explicit `WarmPopTokens.cardShadow(...)` BoxShadow layer matching the board's `0 2px 8px rgba(52,42,28,.10)` |
| R2c app-wide halo class | **FIXED** | the same `ink`-derived shadow existed at 6 other sites (chat expiry badge / pinned banner / message input / chat screen / profile / starred messages) — all migrated to `context.t.shadow`; app-wide grep gate added |
| R3 offline SSE hang (found while implementing H3) | **FIXED** | PB's SSE client retries forever, so `await subscribe(...)` never completed offline and the page hung on the skeleton; realtime subscribe now bounded (4s) AND the data load runs concurrently with the handshake. NOTE: the realtime bound alone did NOT stop the hang — the unbounded DATA fetch did (R3a below). With a fast-failing network the cold start is instant; with a BLACKHOLED socket it is bounded by the 8s fetch timeout |
| H3-1 handled row resurrect | **FIXED** | accept/decline evict the row from the snapshot before the rebuild |
| H3-2 empty vs absent | **FIXED** | the cache returns null when absent and a list when present; only an absent snapshot produces the error state (an empty one renders the G1 empty state) |
| H3-3 cross-user leak | **FIXED** | both sources rebuild on an auth transition (deferred to a microtask — invalidating a provider from inside its own build is a riverpod circular dependency) AND drop the previous session's rows first: riverpod's `copyWithPrevious` retains the old value inside a new `AsyncError`, so a rebuild whose fetch FAILS would render the previous user's rows. Regression-proved RED (`the retained previous value must be dropped on a session change`) |
| R1a/b/c/e | **FIXED** | `registerDispose` throws when the provider is gone → guarded, the listener is dropped instead of leaked; a late handshake is ADOPTED (live caller) or DROPPED (gone caller); the `bool _disposed` flag (never reset — riverpod reuses the notifier across `invalidateSelf`) replaced by a per-build GENERATION counter; the local `unawaited` that shadowed `dart:async`'s removed |
| R3a fetch hang | **FIXED** | the realtime bound alone did NOT stop the skeleton hang — PocketBase's HTTP client has no request timeout, so a blackholed socket hung the page forever. The FETCH is now bounded too (8s) → the offline path renders the snapshot. Regression-proved RED (90s hang vs 8s) |
| R3b unhandled refresh error | **FIXED** | the SSE callback's discarded Future let a failed refetch escape as an unhandled zone error — `_refresh` now catches its own failure and keeps the last good state |
| R3c home skeleton | **FIXED** | the home screen awaited its realtime subscribe before its data load (4s skeleton offline) — the subscribe now runs concurrently; the home friendships FETCH is bounded too (8s, same blackhole reason) |
| R3d reconnect | **FIXED** | nothing re-subscribed when connectivity returned; the sources now watch the connectivity transition stream and rebuild on reconnect |
| R1f/g/h orphan listeners | **FIXED** | the helper now subscribes on `pb.realtime` directly, so it owns the listener identity from the start and can always remove it — a handshake that never lands (PocketBase retries forever) or fails outright no longer orphans a listener, and orphans no longer accumulate one per rebuild |
| R2d AMOLED invisibility | **FIXED** | the AMOLED theme paints pure black surfaces, so a black shadow gave no elevation cue (pixel probe: 1 distinct colour on screen). Added `shadowAmoled` (a faint light edge) + a near-black card surface (`0x0A0908`); the probe now finds 107 distinct colours |

Full suite **300/300** · analyze 0 errors (91 info/warning — three dead-code warnings removed) · `git diff --check` clean.

Note: the drift code generator cannot run in the current toolchain (locked `analyzer` 7.6 cannot
parse the Dart 3.13 SDK's dot-shorthand syntax; `build_runner` deletes the `.g.dart` files and
then crashes). The H3 snapshot therefore uses the EXISTING `app_settings_table` key/value store
rather than a new Drift table — no schema change, no migration, no generated-code churn.

## Second adversarial pass (2026-10-28) — three residuals fixed

| Item | Result | Evidence |
|---|---|---|
| H3-1 stale refresh resurrect | **FIXED** | Eviction at decline time was not enough: an older fetch was still in flight, and `_load` unconditionally snapshotted a payload captured BEFORE the decline. All four actions now bump an action generation; `_refresh` discards a stale refresh and `_load` refuses to snapshot a stale payload. RED-proved: a listener saw `[['request-1'], ['request-1'], []]` without the fence |
| H3-1b failed refresh shrinks the list | **FIXED** | The failure path returned the SNAPSHOT, so a failed snapshot write made newer pending rows vanish. It now prefers the live list and falls back to the snapshot only from a value-less cold start. RED-proved: 2 rows collapsed to 1 |
| R2e unbounded card actions | **FIXED** | The four accept/decline calls had no timeout, so a blackholed socket locked the card's busy state permanently (released only in the handler's finally) and the toast never fired. Bounded by the same 8s. RED-proved: the test hangs past its 30s limit |

Full suite **303/303** · analyze 0 errors (91 info/warning, unchanged) · `git diff --check` clean.

Test seam note: the two notifiers expose `refreshForTest()` (`@visibleForTesting`) so the test can
drive the private SSE `_refresh` callback directly — the race it reproduces has no other reachable
trigger.
