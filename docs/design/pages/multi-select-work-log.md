# Multi-select (12.8): phase 2 work log

Spec: `docs/design/pages/multi-select.md` (user spec PASS 2026-11-02, decisions 1–14 = defaults). Board:
`docs/design/pages/multi-select.html`. Implemented by Claude (one session), 2026-11-02, on `main` at `5580d1e`.

## Baseline

Re-run at phase 2 start, before any change: **900/900** (`flutter test`, all passed).

## Count

**900 + 30 = 930** for this page: `test/chat/multi_select_test.dart` 23 + `test/offline/star_many_test.dart` 7. No
existing test edited. The full-suite run in the shared checkout reads **973/973**: the other 43 are the share-in
(12.1) session's in-flight tests, uncommitted in the same working tree.

## Test gates (RED then GREEN)

- Both files written first; RED = compile failure (no `SelectionBar`, no `setStarred`, no pacing clock).
- `star_many_test.dart` 7/7: phone first then server · 30 stars never more than 15 creates in any 5 s window
  (virtual clock) · a 429 waits 5 s and retries the same row · gives up after 3 retries and moves on · unstar = list
  + delete per row, unpaced · no request for rows without a server id or already in the target state · bodies are
  ids only.
- `multi_select_test.dart` 23/23: enter, toggle, 0 stays open with actions disabled, keyboard down · ✕ and back
  exit, then back pops · tap beside the bubble · long-press while selecting opens no menu · date and system rows ·
  inner taps off (photo, album, reply quote, reaction chip, SwipeToReply all under an ignoring `IgnorePointer`; no
  viewer, no collage, no reaction call) · no reply on a sideways drag · drag range grow and shrink · range from a
  selected row deselects · album in a range = all rows · autoscroll in the top band grows the range and loads older
  history · Copy (skip toast, one, several, all-media disabled) · Star / Unstar ids and toasts · delete sheet, D5
  per-row calls, offline hint, one theirs, left group, cancel, expired id (D7) · semantics (selected / not selected
  + Select / Deselect hint, inner nodes hidden, live count, disabled not enabled) · 360dp × 200% bar (system font
  and Plus Jakarta Sans).
- Harness notes: the chat runs with reduced motion (the composer's mic pulse repeats forever otherwise, so
  `pumpAndSettle` never settles); text bodies are seeded into `bodyCache`.
- Not covered by widget tests (device list items 4, 5): the gesture arena on real touch, autoscroll feel, voice play
  and link taps (covered structurally by the ignoring `IgnorePointer` over the whole bubble).

## Gates

- `flutter analyze`: 0 errors; no issue in any file this page touches.
- Full suite: 973/973 (see Count).
- `git diff --check`: clean on this page's files.
- Frozen-method diff vs HEAD: `message_repository_impl.dart` is one pure-addition hunk after `toggleStar`
  (`setStarred`, `_sendStars`, `_paceStarCreate`, pacing fields); `toggleStar`, `deleteMessage` and every send path
  untouched. `message_context_menu.dart`: only the album Star row. `album_screen.dart`: only `_deleteChoice`,
  `_deleteSelected`, `_selectionBar` and one import. `message_bubble.dart`: `_messageRowSemantics`, the
  `selecting` field, the selected look, the final wrap; no bubble state rule touched.
- `trail check`: 3 flagged. `MainActivity.kt:63` is the share-in session's file. The two in
  `message_repository_impl.dart` (~2668, ~2699) are keyword matches on the new `setStarred`: one learning is about
  same-second unread badges, the other about a retryable failed bubble on a rejected send; this is a background
  star write with the 429 retry D6 requires. Neither applies; the commit message says so.

## Deviations from the spec (clerical)

- **Registry number C19, not C18.** The share-in session (12.1) registered its Send-to picker as C18 first in the
  shared working tree; the selection bar is C19. Spec text still says C18.
- **`SelectionBar` signature** adds `canCopy` / `canStar` (the spec's sketch had only nullable callbacks): a null
  callback leaves the slot out (collage, H1), so "present but disabled" needs its own flag. `starState` is a bool
  (true = Unstar).
- **Tint switches instantly** (C3 allows "a 100 ms colour fade at most"; no fade is within it and needs no
  reduced-motion branch).
- **Bubble tree stays stable while selecting**: `SwipeToReply` stays in the tree under an ignoring `IgnorePointer`
  instead of being removed, and the selected look's `ColoredBox` + `DecoratedBox` are always present, so toggling a
  row never rebuilds its bubble (a playing voice note or video keeps its state).

## F-b (spec follow-up, checked here, not fixed)

Deleting a still-queued text for me does **not** stop its outbox send: `deleteMessage` (for me, no server id) only
sets `isDeletedForMe` on the row and the outbox drain does not read that flag (code read, not run on a device). So
D5's "an own unsent row → delete for me" hides it here but it is still delivered when the queue drains. Media is
different (an unsent photo/video is cancelled, wave 4). Backlog item.

## Review (one fresh-context reviewer, 2026-11-02): PASS, no BLOCK; frozen code untouched

- **S1 fixed**: a cancelled long-press (app backgrounded) never sent an end, so autoscroll kept running; now
  `onLongPressCancel` ends the drag, and `_startDrag` cancels any old timer first.
- **S2 fixed**: a finger past the list's edge during autoscroll stopped the range growing; the hit-test y is now
  clamped inside the list, so the range follows the edge row.
- **S3 fixed (first half)**: Delete for everyone re-reads each row when confirmed (a row that got its server id
  while the dialog was open is deleted for everyone; a row gone meanwhile is skipped). **Second half open, user's
  call**: F-b above, so "Delete for everyone" on a still-queued own text hides it here but the outbox still delivers
  it.
- **N1 fixed**: the bulk-star chain catches errors, so one failure never stops later sends. **N5 fixed** (fake repo
  comment order).
- Not changed: S4 (no voice/link/bottom-band/late-album-row/pointer-cancel widget cases; device items 2, 4, 5 cover
  them), N2 (Copy whose every body times out does nothing, rare), N3 (fixed 16 ms tick; tune on device), N4 (the
  collage's Delete for everyone now follows D5 per row: an unsent tile or tombstone is deleted for me; accepted).
- After fixes: analyze 0 errors, full suite 975/975 (share-in added 2 more of its own), `git diff --check` clean.

## Device round 1 (user, 2026-11-02): all items PASS except one; item 12 not run (no short-timer chat)

- **FAIL item 8**: the delete sheet read "online" once when it opened, so turning the internet off with the sheet
  open kept **Delete for everyone** enabled (and back on kept **Available online**), and a delete for everyone sent
  offline showed deleted, then came back after reopening the app (server-first, the fetch restores it). **Fixed**:
  the sheet watches the connection live, and the delete re-checks right after the confirm; offline there → toast
  **Available online**, nothing deleted, selection kept (the same flow serves the collage). New test in
  `multi_select_test.dart`; this page's count is now **900 + 31 = 931**; full suite 976/976; analyze 0 errors.
- F-b (a queued text deleted still sends): user chose backlog.
