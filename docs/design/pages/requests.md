# Requests screen — acceptance checklist (Page 3)

Date: 2026-10-21. Visual ground truth: **`docs/design/pages/requests.html`** (sections Q1–Q14,
numbered). Authority: `docs/design/00-foundation.md` (tokens/laws) → `docs/design/10-registry.md`
(shared pieces) → this checklist. Page letters A–K are page-local ("home D5" ≠ this page).

**How Astra uses this:** every MUST must be implemented or consciously reported as not-done.
SHOULD = stretch, do after MUSTs. A deviation from foundation C1–C4 / L1–L4 that *looks better*
is still a FAIL (surpass = better inside the system).

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors ·
`flutter test` green (pre-change baseline **258/258**) · mandatory test-gate files below green ·
device captures light + dark on Redmi S2 (M52 if connected) · user PASS (no commit without it).

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence;
`[ ]` pending, partial, or blocked. Progress also logged in `requests-work-log.md`.

---

## A. Shell & canvas (Q3)

- [x] **A1 MUST** Scaffold bg = `context.t.bg` explicit (kill default-M3-surface seam); AppBar
  title **Requests** 20/28 w700, no actions, no bottom, no elevation line; back = 48dp ink target.
- [x] **A2 MUST** Route `/friend-requests` unchanged; back pops (GoRouter); FCM deep-link entry
  still lands here (fcm_service payload path untouched).

## B. Two-source data contract (Q10, Q7)

- [x] **B1 MUST** Page renders from BOTH `incomingRequestsProvider` + `incomingGroupInvitesProvider`
  with per-source status: one source error → content of the other STILL renders + partial banner
  (home H6 pattern). No single `.when` gating the whole page.
- [x] **B2 MUST** No false-empty flash: empty state only when BOTH sources settled AND both empty
  (replace `valueOrNull ?? []` invites swallow — invites error must surface, not vanish).
- [x] **B3 MUST** Full error = R7-style error state: **Couldn't load requests.** +
  **Check your connection and try again.** + **Retry** re-running failed providers.
  Raw `Error loading requests: $e` BANNED (no `$e` anywhere on this page).
- [x] **B4 MUST** Pull-to-refresh (RefreshIndicator) invalidates both providers; keeps prior data
  during refetch (skipLoadingOnRefresh semantics).
- [x] **B5 MUST** Row data rules: newest-first both lists; duplicate pending rows from one sender
  render as independent cards; `Unknown`/`Someone`/`Group` fallbacks render safely (Q4/Q5).

## C. Friend request card (Q4)

- [x] **C1 MUST** Anatomy: R1 AppAvatar disc r52 accentSoft + accent initial; name 16/22 w600
  ellipsize; meta `@username` 13/18 `inkSoft`; card = surface + `radiusMd 16` + warm elevation
  token + pad 16 + card gap 12 (no `BorderRadius.circular(16)` literals, no
  `colorScheme`/`withValues(alpha…)` — C3 grep gate).
- [x] **C2 MUST** Empty/short displayName never crashes (R1 fallback — regression test for
  `substring(0,1)` RangeError currently at :126).
- [x] **C3 MUST** Actions: Decline = ghost/secondary, Accept = primary accent, gap 8, ≥48h each,
  verbatim labels; card body NOT tappable (buttons only).

## D. Group invite card (Q5)

- [x] **D1 MUST** R1 disc + **group glyph badge** (20dp accent, 2px surface ring) bottom-right;
  title conversationName 16/22 w600 (fallback **Group**); meta **{inviter} invited you to join**
  with verbatim fallbacks (**You were invited to join** / **Someone**).
- [x] **D2 MUST** Same action pair + busy/offline laws as C3; post-accept side effects unchanged
  in repo (member row, deferred join bubble) — UI only invalidates + toasts.

## E. Sections (Q6)

- [x] **E1 MUST** Order: friend cards → section header → invite cards; header uses **R9
  SectionHeader** label **Group invites** + count pill; renders ONLY when ≥1 invite (today it
  renders with zero invites — fix).
- [x] **E2 MUST** Friends empty + invites present → header + invite cards, NO page empty state.

## F. Loading (Q2, Q13)

- [x] **F1 MUST** First load = R11 **card-shaped skeleton** ×3 (disc + 2 lines + 2 button bars) —
  `CircularProgressIndicator` for content-with-a-shape BANNED (foundation §6; add no-spinner gate).
- [x] **F2 MUST** Refresh keeps prior list (no skeleton flash on invalidate); shimmer parks under
  reduced-motion (R11 duration-restart already in tree).

## G. Empty (Q2)

- [x] **G1 MUST** R7 EmptyState: Capybara **neutral** slot + title **No pending requests** +
  subtitle **Friend requests and group invites will show up here.** + primary CTA
  **Add a Friend** dispatching the Add-Friend sheet (sheet itself = page 8 boundary; Requests
  only dispatches the existing entry point).

## H. Offline (Q8)

- [x] **H1 MUST** Offline strip under bar: accentSoft + verbatim **You're offline — actions are
  available when you're back.**; auto-clears 250ms on reconnect (home O1 timing); no Retry in strip.
- [x] **H2 MUST** All four actions disabled offline: exactly ONE dim layer @38% + trailing
  **Available online** (`kOfflineActionHint`) — double-dim is a FAIL (chat L3 law).
- [x] **H3 MUST** Open-while-offline with stale local cache renders last-good list when available;
  error state only when nothing to show (B3 copy). Implemented as a local snapshot per user
  (`RequestSnapshotCache`, stored in the existing `app_settings_table`): a successful fetch
  refreshes the snapshot; a failed fetch falls back to it; with no snapshot the error
  propagates and the page shows the B3 error state.
  - An **empty** snapshot is NOT an error: it means the last known state was "nothing pending",
    so the page settles into the empty state (G1), not the error state.
  - A row the user accepted/declined is **evicted from the snapshot** when the action succeeds,
    so a failing refetch can never resurrect a handled row.
  - A **stale in-flight refresh** also cannot resurrect it: an accept/decline bumps an action
    generation, and a refresh whose payload predates that bump is discarded outright (the
    action's own rebuild already refetched the truthful list).
  - A **failed** refresh prefers the live list over the snapshot — only a value-less cold start
    falls back to it.
  - All four card actions are **bounded** by the same 8s fetch timeout, so a blackholed socket
    releases the card's busy lock and shows the failure toast instead of freezing it forever.
  - Both sources are **session-scoped**: an auth transition rebuilds them AND drops the previous
    session's rows (riverpod retains the previous value inside a new `AsyncError`, so the old
    rows would otherwise survive into the new session's error state and be rendered). A second
    user signing in on the same process never reads the previous user's rows — verified for
    BOTH the successful-fetch and the failing-fetch path.

## I. Actions & outcomes (Q9)

- [x] **I1 MUST** Per-card lock while either action in flight: both buttons disabled, busy
  spinner on the pressed one (R3 `busy` slot) — double-tap second press must no-op (test).
- [x] **I2 MUST** ALL four handlers try/catch (friend Decline currently has none :169) → failure
  toast R5 **Couldn't update. Try again.**; no `$e`; card unlocks; no silent unhandled errors.
- [x] **I3 MUST** Success: friend Accept → tile exits (invalidate requests + friendships) +
  toast **Friend added**; invite Accept → tile exits + toast **Joined {name}**; declines → tile
  exits silent. Announce **{name} removed** live-region (K3).
- [x] **I4 MUST** L4: widget callbacks dispatch notifier methods — remove direct
  `*_repository_impl.dart` imports/writes from the screen (move accept/decline onto notifiers).
- [ ] **I5 SHOULD** Card-exit animation 250ms fade+collapse; instant under reduced-motion.

## J. Home entry badge (Q12)

- [x] **J1 MUST** Person+ button uses **R2 AppBadge** (accent/onAccent, hide ≤0, 99+ ≥100)
  replacing the hand-rolled error-red pill (C2: error is status-only). Keep 48dp, tooltip
  **Friend requests**, label **{n} pending requests** / **No pending requests**.
- [x] **J2 MUST** Count semantics unchanged: `pendingRequestCountProvider` = incoming friend
  requests + incoming group invites, async wrapper keeps the no-0-flash boundary (home :43-52).

## K. A11y + gates (Q11)

- [x] **K1 MUST** Card merged semantics: **Friend request from {name}, {username}** /
  **Group invite to {name}, from {inviter}**; avatar discs decorative (excluded from tree).
- [x] **K2 MUST** Retry/CTA/strip carry button/container semantics; 48dp floor everywhere.
- [x] **K3 MUST** Removal announced via live region (**{name} removed**).
- [x] **K4 MUST** Contrast: meta inkSoft ≥4.5:1 both themes; badge = onAccent-on-accent (test
  reuses registry amendment harness); C3 grep gate extended to this feature (no `colorScheme`,
  no `withValues(alpha` in `lib/features/friend_requests/`).

## Test gates (mandatory re-run — NEW files, none exist today)

- [x] `test/friend_requests/requests_screen_test.dart` — loading skeleton (no spinner), false-empty
  guard, partial-failure banner + content, full error copy (no `$e`), offline strip + single-dim
  disabled actions + hint, empty state copy/CTA, section header conditional (0 invites).
- [x] `test/friend_requests/request_actions_test.dart` — busy lock/double-tap no-op, all four
  try/catch paths → failure toast, success exits + toasts, initials-crash regression
  (empty displayName → fallback, no RangeError), live-region announce ("{name} removed",
  captured off the accessibility channel).
- [x] `test/friend_requests/pending_count_test.dart` — badge sum incl. loading/error collapse.
- [x] `test/friend_requests/offline_snapshot_test.dart` — H3: offline cold start renders the
  last-good snapshot; no snapshot → the error propagates; an EMPTY last-good list renders the
  empty state (not an error); a declined row never comes back; a new session never renders the
  previous user's rows — for BOTH the successful-fetch and the failing-fetch path.
- [x] `test/friend_requests/sse_scoped_unsubscribe_test.dart` — R1: a scoped unsubscribe removes
  only its own listener; the topic-less form removes every listener on the collection.
- [x] `test/friend_requests/realtime_subscribe_test.dart` — the subscribe helper times out instead
  of hanging, registers a scoped dispose func, ADOPTS a late handshake for a live caller, and
  DROPS one whose caller is gone.
- [x] `test/friend_requests/card_shadow_test.dart` — R2: the dark elevation token is not a light
  color, and the card shadow layer paints the token alpha (not Material's tonal math).
- [x] `test/friend_requests/offline_fetch_timeout_test.dart` — R3: a fetch that never completes
  still settles (bounded), and a blackholed fetch still renders the snapshot.
- [x] `test/grep_gates_test.dart` — extended: friend_requests has no `colorScheme`/`withValues(alpha`,
  no `CircularProgressIndicator`, no `*_repository_impl.dart` import in the screen; **app-wide**
  no shadow is painted with `ink` (registry T1) — matches the `ink.withValues`,
  the bare `color: t.ink`, and the `WarmPopTokens.ink` forms.
- [x] `test/friend_requests/stale_refresh_test.dart` — H3-1a: a stale in-flight refresh cannot
  resurrect a declined row (every post-action publish is recorded, not just the final state);
  H3-1b: a FAILED refresh keeps the live list rather than shrinking to the snapshot; R2e: a
  BLACKHOLED accept/decline settles instead of locking the card forever.
- [x] Full suite **303/303** · analyze 0 errors (91 info/warning — three dead-code warnings removed; 0 errors).

### Review-pass findings fixed (2026-10-22)

| ID | Finding | Fix |
|---|---|---|
| R1 | `collection.unsubscribe()` (topic-less) maps to PB `unsubscribeByPrefix`, which removes EVERY listener on `friend_requests/*` — one `invalidateSelf` on this page killed `FriendQueryService`'s listener, so live friend updates died after any decline | keep the scoped `UnsubscribeFunc` PB returns from `subscribe()` and dispose only that (`lib/core/network/realtime_subscribe.dart`); same fix applied in `friend_query_service.dart` |
| R2 | Card `shadowColor: t.ink` — `ink` is near-white in dark, rendering a white halo around every raised card | new elevation token `WarmPopTokens.shadowLight/shadowDark` (foundation §4) read as `context.t.shadow`; registry row T1 added; migrated the 6 other ink-shadowed surfaces app-wide and added an app-wide grep gate |
| R2b | Material's `elevation` shadow is routed through the engine's tonal path and paints materially weaker than the token (measured ~7× weaker in a pixel probe) — the card did not match the board's `0 2px 8px rgba(52,42,28,.10)` | raised cards use an explicit `WarmPopTokens.cardShadow(t.shadow)` BoxShadow layer (one layer — the foundation's max-2 budget) |
| R3 | PocketBase's SSE client retries forever, so `await subscribe(...)` never completes offline — the page hung on the skeleton instead of rendering the cached list (H3) | realtime subscribe bounded by `realtimeSubscribeTimeout` (4s) in `lib/core/network/realtime_subscribe.dart`; the data load runs CONCURRENTLY with the handshake. NOTE: this bound alone did NOT fix the hang — the unbounded DATA fetch did (see R3a). With a fast-failing network the cold start is instant; with a BLACKHOLED socket it is bounded by the 8s fetch timeout. |
| H3-1 | A just-declined request could come back from the snapshot when the refetch failed (the card reappeared and was re-actionable) | accept/decline evict the row from the snapshot before the rebuild |
| H3-2 | An EMPTY last-good list was treated as "no snapshot" → the user saw "Couldn't load requests." instead of "No pending requests" | the cache distinguishes absent (null) from empty (list); only an absent snapshot produces the error state |
| H3-3 | The providers are not auto-disposed, so their in-memory state survived a sign-out — a second user on the same process could read the first user's rows | both sources listen for an auth transition and rebuild themselves (the invalidation is deferred to a microtask: invalidating a provider from inside its own build is a circular dependency) AND drop the previous session's rows first — riverpod's `copyWithPrevious` retains the old value inside a new `AsyncError`, so a rebuild whose fetch fails would otherwise render the previous user's rows. Regression-proved RED (`the retained previous value must be dropped on a session change`) |
| R1a | `registerDispose` (`ref.onDispose`) THROWS when the provider was already disposed — a subscribe that resolved after disposal registered no disposer and leaked its listener | the registration is guarded; on failure the listener is dropped instead of leaked |
| R1b | PocketBase registers the listener BEFORE the handshake completes, so a timed-out subscribe still owns a live listener whose unsubscribe func only materialises later — it survived the provider's disposal and fired into a dead notifier | the helper watches the original future: a late handshake is ADOPTED (registered for disposal) when the caller is alive, or DROPPED when the caller is gone |
| R1c | Riverpod REUSES a notifier instance across `invalidateSelf`, so a `bool _disposed` flag stayed `true` after the first rebuild — the helper then dropped a LIVE provider's listener, re-creating the original R1 symptom (no live updates after one decline) | per-build GENERATION counter (`generation != _generation`) instead of a boolean; regression-proved RED (`Expected: <1>, Actual: <0>`) |
| R1e | A local `unawaited` shadowed `dart:async`'s and swallowed every error | removed — `dart:async`'s `unawaited` is used |
| R3a | The realtime bound did NOT stop the skeleton hang: the underlying DATA fetch has no timeout. PocketBase's HTTP client never times out, so a blackholed socket ("wifi up, no internet") left the page on its skeleton FOREVER, even with a good snapshot on disk | the fetch is bounded too (`_fetchTimeout`, 8s) — a blackholed network degrades to the offline path: the snapshot renders, or the error state. Regression-proved RED (without the bound the test hangs 90s vs 8s) |
| R3b | The realtime refresh (`_refresh`) is a fire-and-forget SSE callback — its Future is discarded, so a failed refetch escaped into the zone as an UNHANDLED error | `_refresh` catches its own failure: a failed realtime refresh keeps the last good state and reports nothing |
| R3c | The home screen awaited its realtime subscribe BEFORE its data load, holding the whole home skeleton for the full timeout offline | the subscribe runs concurrently with the data load (`unawaited`) |
| R3d | Nothing re-subscribed when connectivity returned — a device offline at cold start stayed deaf for the rest of the session | the sources watch the connectivity transition stream and rebuild on reconnect (which re-subscribes and re-fetches) |
| R1f | The helper's watcher only ran when the handshake COMPLETED. PocketBase's SSE client retries forever, so an offline cold start left the handshake pending forever: the listener PocketBase had already registered was orphaned with no disposer, and it ACCUMULATED one per rebuild — every orphan kept firing | the helper now subscribes on `pb.realtime` directly, so it owns the listener identity from the start and can ALWAYS remove it (handshake success, failure, or never) |
| R1g | When the handshake FAILED outright, the `UnsubscribeFunc` never materialised — the listener stayed in PocketBase's map forever and the failure was swallowed silently | the same fix: the listener identity is owned up front, so a failed handshake removes it |
| R1h | `unawaited(unsubscribe())` did NOT suppress errors — `dart:async`'s `unawaited` only silences the lint, so a rejecting unsubscribe (offline POST) surfaced as an unhandled zone error | the cancel path swallows its own failures (the local listener removal already happened; a failed POST must not surface) |
| R2d | The AMOLED theme paints pure black surfaces, so a black shadow gave NO elevation cue — the card was invisible (a pixel probe found 1 distinct colour on screen) | an AMOLED-specific shadow token (`shadowAmoled`, a faint light edge) + a near-black card surface (`0x0A0908`) that differs from the page ground; probe now finds 107 distinct colours |
| H3-1a | A stale in-flight realtime `_refresh()` could STILL resurrect a declined/accepted row: eviction at decline time does not help while an older fetch is in flight, and `_load` unconditionally snapshotted a payload captured before the decline | `_refresh` fences on the action generation (`_actionGeneration`, bumped by all four actions) and discards a stale refresh entirely — the action's own rebuild already refetched the truthful list; `_load` also refuses to snapshot a stale payload. Regression-proved RED (listener saw the row publish twice: `[['request-1'], ['request-1'], []]`) |
| H3-1b | A FAILED refresh fell back to the SNAPSHOT, so when the snapshot's own write had failed the pending rows on screen shrank to the older snapshot | the failure path prefers the live list (`state.valueOrNull`) and falls back to the snapshot only from a genuinely value-less cold start. Regression-proved RED (2 rows collapsed to 1) |
| R2e | All four card actions awaited the repository with NO timeout — PocketBase's HTTP client has no request timeout, so a blackholed socket locked the card's busy state permanently (released only in the handler's finally) and the "Couldn't update. Try again." toast never fired | the same 8s bound as the fetch; the caller's catch then shows the toast and unlocks the card. Regression-proved RED (the test hangs to its 30s limit) |

## Out of scope (do NOT build on this page)

AddFriendSheet internals (page 8) · outgoing/cancel requests · block/unblock UI · auto-nav after
accept · notification styling (FCM service) · pagination · nicknames · Profile/ViewProfile (page 5).

---

### Deferred decisions (user may override at review)

1. **Badge red→accent (J1):** C2 compliance changes a shipped red visual — one-line revert if you prefer red.
2. **Post-accept "Open chat" toast action:** needs repo to return conversation id — default OFF this pass.
3. **Decline feedback:** declines exit silently (I3) — flag if you want a toast too.
4. **Empty subtitle copy:** new string in G1 — exact wording above, editable.
