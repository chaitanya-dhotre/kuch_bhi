# Media fullscreen (one viewer, opens at once, honest states) — implementation work log

Date: 2026-10-30.
Scope: Page 9, checklist `docs/design/pages/media.md` (A1–J2 incl. B6, registry C10, test gates),
board `media.html` (S1–S15 + S13b). Routed to Claude end to end (Omnirush down until 2026-11-02
17:30 IST). Every deferred decision at its default (user spec PASS 2026-10-30). No live PocketBase
read (decision 16).

## Status

| Step | Result |
|---|---|
| Spec + checklist | user PASS 2026-10-30, decisions 1–17 = defaults |
| Implementation | DONE 2026-10-30 by Claude, every MUST in A–J |
| Gates | `flutter test` **641/641**, run twice (baseline 592 + **49** new: 42 at implementation + 7 from review fixes) · `flutter analyze` 0 errors, and no issue of any level in a changed or new file (whole-repo count 83 before and after) · `git diff --check` clean, no trailing whitespace in new files · J1 RED → GREEN · `trail check` 0 conflicts · frozen diff clean · `flutter pub get` clean after removing `photo_view` + `chewie` |
| Independent review | fresh-context reviewer subagent, one pass: **1 BLOCK + 3 SHOULD + 4 NIT**. BLOCK and all SHOULDs fixed, each with a test that failed on the unfixed code and passes now; NITs 5 and 6 fixed and tested; NIT 7 (tests) done; NIT 8 accepted as a known limit |
| Device check | pending (15 items, `media.md` § Device check list) |
| Commit | none. After the user's device PASS, one commit: `media.html`, `media.md`, this log, `.trail/learnings/2026-10-30-a-photo-s-expiry-date-is-chaitanya.md` + `.trail/learnings/2026-10-30-a-fullscreen-video-must-pause-itself-chaitanya.md` (new, this implementation), the implementation and tests, the registry row, `docs/backlog.md` §12. Device photos stay uncommitted. |

## What changed

- **`lib/features/media/screens/media_viewer_screen.dart` (rewrite, C10)**: `MediaViewerArgs`
  `{conversationId, serverId, mediaType, senderName, timestamp, heroTag?, thumbPath?}` (no
  `localPath`); `pushMediaViewer(context, args)` = `PageRouteBuilder(opaque: false)` fade
  (`motionBase` in / `motionFast` out, zero under reduced motion). The screen is a
  `ConsumerStatefulWidget` that watches `mediaFileProvider(MediaRef(conv, server))` itself and
  wraps its subtree in `warmPopDark(amoled: true, fontFamily: <user font>)`.
  - States: loading (thumbnail + R3a 32, plus **Waiting for a connection** on a 64% pill when
    offline), loaded, load failed (**Couldn't load this photo/video.** + R3 secondary **Try
    again**; offline: one 38% dim, disabled, **Available online** beside it), expired (blob
    `failed` + `expired`/`dead_link`, or a loaded file past `expiresAt`), can't decrypt (blob
    `failed` + `decrypt`/`verify`), play failed (video `initialize()` threw).
  - Every retry (`Try again`, offline → online, video retry) evicts the decoded photo, disposes the
    video controller, then `ref.invalidate`s the blob-status and media providers. On open, a
    null / error result cached by an earlier attempt is invalidated once (D6), checked with
    `ref.exists` so the viewer's own first load is never thrown away; an earlier open's load still
    in flight is restarted too (review fix 3). The blob row is read from the start, so a blob
    already `failed` shows expired / can't decrypt at once, and it is re-read whenever a load ends
    (review fix 2). The viewer pauses the video on any lifecycle state but `resumed` (review fix 1).
  - Chrome: one flat `t.bg` @ 64% top bar (Close · sender 16/22 w600 · date 13/18 · optional
    **Expires …** line · Share · Save to gallery), all `t.ink`. Actions only on the loaded state.
    Tap toggles (opacity `motionFast`, hidden = `IgnorePointer` + `ExcludeSemantics`), never under
    `accessibleNavigation`. Edge-to-edge shown / `immersiveSticky` hidden / edge-to-edge on dispose,
    transparent bars via `AnnotatedRegion`.
  - Photo: `InteractiveViewer` 1–4×; double-tap 2.5× about the tapped point / back to fit
    (`motionBase`, jumps under reduced motion); vertical drag only at fit (scale ≤ 1.01), ground
    alpha `1 − |dy|/300` floor 0.3, pop past 120dp or 600 px/s, else snap back `motionFast`;
    full photo fades in over the thumbnail (`frameBuilder`); decode error → load-failed block;
    rotation resets zoom.
  - Video: `video_player` only; poster + R3a until initialised; autoplay, no loop; 64dp accent
    disc (Pause / Play / Play again, tooltip = label); bottom strip on the same scrim: elapsed ·
    `VideoProgressIndicator(allowScrubbing)` (accent played, ink 40% buffered, ink 16% track, 48
    tall, semantics **Video position**) · total, tabular figures; the chrome comes back at the
    end; controller disposed on pop.
  - Save / share through `mediaActionsProvider`; R3a in the button while busy, second tap ignored;
    R5 toasts with fixed copy (`$e` only in `debugPrint`).
  - The chrome sits **outside** the gesture layer, so Close/Share/Save never wait out the photo's
    300ms double-tap timeout (found while writing the tests: the first build put the bar inside the
    detector and every bar button fired 300ms late on a loaded photo).
- **NEW `lib/features/media/providers/media_viewer_providers.dart`**: `mediaBlobStatusProvider`
  (auto-dispose family on `MediaRef`; one `mediaBlobDao.byId` read, no write, no pipeline call)
  and `MediaActions` / `mediaActionsProvider` (`Gal.hasAccess` → `requestAccess` →
  `putImage`/`putVideo(path)`; `Share.shareXFiles([XFile(path)])`).
- **`lib/features/chat/widgets/expiry_badge.dart`**: `viewerExpiryLabel(expiresAt, {now})` next to
  `compactExpiryLabel`, same thresholds (> 7 days → **Expires Nov 29**, year only when it differs;
  1–7 days → **Expires in N days**; under 24h → **Expires in N hours**, **1 hour** under 2h; past
  or null → no line).
- **Entry points**: `image_message_bubble.dart` (`_openFullScreen` + its `onTap`, new `senderName`
  param), `video_message_bubble.dart` (`onTap`, new `senderName`, `_opening` removed, Hero
  `media_{serverId}` around the thumbnail per A2/G1), `message_bubble.dart` (passes `senderName`
  to both), `media_docs_screen.dart` (`_MediaGridTile._open` only: reads the tile's own thumbnail
  and pushes). All push synchronously; nothing awaits a load before `push`.
- **Deleted**: `lib/features/chat/widgets/video_player_screen.dart`; the `/media-viewer` GoRoute,
  `AppRoutes.mediaViewer` and the viewer import in `app_router.dart`.
- **`pubspec.yaml`**: `photo_view`, `chewie` removed; `video_player_platform_interface: ^6.7.0`
  added to `dev_dependencies` (the video tests fake the plugin's platform seam).
- **Registry**: C10 row replaced with the amendment text (+ `pushMediaViewer`).
- **One file outside the brief's list**: `test/media/viewer_harness.dart`, the shared pump, fakes
  and finders for the two viewer test files (same role as `test/core/sheet_harness.dart`).

## Gates

| Gate | Result |
|---|---|
| `flutter test` | **641/641**, full suite run twice after the review fixes (`+641: All tests passed!` both times); 634/634 before the review |
| `flutter analyze` | 0 errors. Whole repo 83 issues before and after (all pre-existing infos/warnings in untouched files); 0 in any changed or new file (3 `containsSemantics` deprecation infos in the new tests were switched to `isSemantics`) |
| `git diff --check` | clean; `grep -nE '[[:space:]]+$'` over every new file: none |
| J1 grep gate | RED: appended `// RED probe: Colors.white` to `media_viewer_screen.dart` → `Page 9 media: …` failed with `Colors. in lib/features/media/screens/media_viewer_screen.dart`. File restored byte-identical (copy back) → GREEN `+1: All tests passed!` |
| `trail check` | `no conflicts · 7 worth a look`; all 7 are lexical matches trail itself labels "not about this file" (e.g. it reads `ref.invalidate(mediaFileProvider…)` as the ruled-out `ref.invalidate(authProvider)`; the media-download learning asks for exactly this invalidate) and 2 are in `docs/backlog.md` (not this page) |
| Frozen diff (function level, vs HEAD `1a8d416`) | script `members()` over every class member / top-level declaration, HEAD vs working tree. `image_message_bubble.dart`: 10 members, 7 byte-identical; changed = constructor (`senderName`), `_openFullScreen` (tap handler), `build` (one hunk: the `onTap` lambda). `video_message_bubble.dart`: 4 members, 2 identical; changed = constructor (`senderName`), `build` (two hunks: the `onTap` lambda, and the Hero wrap A2/G1 asks for); field `_opening` removed (A2). `message_bubble.dart`: 24 members, 23 identical; `build` changed by two added `senderName: senderName,` lines. `media_docs_screen.dart`: 32 members, 31 identical; only `_MediaGridTile._open`. Frozen pipeline files (`media_blob_store.dart`, `chat_provider.dart`, `media_upload_service.dart`, `message_repository_impl.dart`, `message_input.dart`): `git diff --stat` empty |
| No timeout around the load | `grep -rn "timeout\|Timeout" lib/features/media/` → one hit, the comment about the double-tap timeout; no `.timeout(` / `Timeout` anywhere |

### Test count

Baseline **592**. New: `test/chat/expiry_label_test.dart` 4 · `test/media/media_viewer_screen_test.dart`
24 · `test/media/media_viewer_video_test.dart` 6 · `test/media/media_entry_points_test.dart` 7 ·
`test/grep_gates_test.dart` J1 1 = **42** at implementation. 592 + 42 = **634**; the full run printed
`+634: All tests passed!`.

Review fixes added **7** more: screen 24 → **28** (blob already expired while loading, reopen
restarts a cached failure and an in-flight load, no "Photo from Photo", decode failure); video
6 → **8** (background → stays paused, offline initialising has no waiting line); entry points
7 → **8** (Media & docs video tile). One assertion that proved nothing (`find.text('Video
position'), findsNothing`) was deleted. **4 + 28 + 8 + 8 + 1 = 49**; 592 + 49 = **641**, matching
the run.

No existing test was edited; `test/grep_gates_test.dart` only gained J1 at the end of `main()`, and
gate 10's comment is untouched.

## Independent review

Fresh-context `general-purpose` subagent (it never saw this session's work), given `media.md`,
the authority chain, the in-scope file list, the media learnings, and told not to edit. It read the
spec in full, ran `flutter analyze` and the 5 new test files + `grep_gates_test.dart` +
`media_link_widgets_test.dart` (70/70), and checked every MUST A1–J2. Its findings, summarised:

| # | Sev | Finding | Fix | Proof |
|---|---|---|---|---|
| 1 | BLOCK | **E6 not met.** `video_player` 2.11.1's own lifecycle observer records "was playing" at `paused` and calls `play()` on `resumed`, so a video paused by going home plays again on return (device item 10 would fail). | The viewer is a `WidgetsBindingObserver`; any state other than `resumed` calls `_video?.pause()`. `inactive` comes first, so the plugin then records "not playing". | `app to background pauses; back stays paused` (inactive → hidden → paused → hidden → inactive → resumed → disc says **Play**). RED on the unfixed code: `Pause` still shown. |
| 2 | SHOULD | Expired / can't-decrypt media sat on the spinner for **45s**: `requestBlob` returns null at once for a `failed` blob, but the frozen `mediaFileProvider` still waits 45s for a media event, and the blob row was only read after the load ended. Reopening restarted the 45s each time. | `_view` watches `mediaBlobStatusProvider` from the start; `expired`/`cantDecrypt` win over loading. A `ref.listen` on the media provider re-reads the row whenever a load ends (the load itself can fail the blob). Still read-only, frozen code untouched. | `blob already expired while the load is pending → expired now`. RED: no expired text, spinner shown. |
| 3 | SHOULD | D6 gap: an earlier open's load still **in flight** (offline, inside its 45s wait) was reused on reopen after going online, and nothing re-read it, so the spinner ran up to 45s. | `_start` also invalidates when the cached value `isLoading`; the store's `_inflight` map shares any download already running, so nothing downloads twice. | `reopening restarts a cached failure and an in-flight load` (fetch count 1 → 2 for in-flight, 3 → 4 for a cached null). RED: count stayed 1. |
| 4 | SHOULD | **Waiting for a connection** showed offline under a video whose file was already loaded and only initialising locally. | `_busy` gets `online \|\| view != loading`: the line only shows during a real load. | `offline, file loaded, still initialising: no waiting line`. RED: line shown. |
| 5 | NIT | Media & docs passes the fallback word as the sender, so the photo node read **Photo from Photo, …**. | Label drops "from {sender}" when the sender is the fallback word (**Photo, Oct 30, 2026 · 14:02**). | `no sender: the photo node is not "Photo from Photo"`. RED. |
| 6 | NIT | A decode failure (local) mapped to the load-failed block and was dimmed offline with **Available online**. | `dim` also requires `!_decodeFailed`. | `decode failure → load-failed block, Try again live offline` (seeds the image cache with a failing completer; also covers D5, which the reviewer noted was untested). RED with only this line reverted: `Available online` found; restored byte-identical (copy back) → GREEN. |
| 7 | NIT | Tests: one vacuous assertion; no test for `_start` clearing a cached failure; D5 untested; the Media & docs **video** tile untested. | Assertion deleted; `_start` and D5 covered by the tests in rows 3 and 6; new entry test for the video tile (video tiles have no Hero of their own, frozen grid, so it taps the tile's play icon). | tests listed |
| 8 | NIT | The save/share toast (R5, floating) sits over the video scrubber for ~3s. | **Accepted**: R5 is the shared toast; lifting it would change R5 for every page. Known limit below. | — |

Reviewer's verified-OK list covered A1–A5, B1–B6, C1–C5, D1/D3/D5/D6 (apart from rows 2–3), E1–E5,
F1–F5, G1–G2, H1–H2, I1–I3, J1–J2 and the frozen function-level diff. It noted the double tap is
really swallowed by the Navigator's own pointer handling on push, so the one-viewer test is real.

Found while fixing: the decode test passed alone but failed in the full file, because the image
cache keeps an earlier test's pending real-IO load under the same path; the test now clears the
cache before seeding it.

## Known limits

- The thumbnail stays under the full photo; a transparent PNG/GIF would show it through the clear
  pixels. Photos arrive as JPEG today (S13 row a). Upgrade when the media-send task keeps original
  formats.
- Double-tap zoom keeps the tapped point under the finger (always in bounds) rather than moving it
  to the screen centre.
- A pinch whose first finger moves vertically by 18dp before the span changes can be read as a
  swipe-down at fit; device check item 4/5 covers it.
- The toast also lands in the chat's Scaffold under the see-through route (the messenger shows a
  SnackBar in every visible Scaffold); it is hidden behind the viewer's black ground.
- The save / share toast covers the video scrubber while it shows (review NIT 8, accepted; R5 is
  shared).
- Over a video's play disc or strip a vertical drag does not dismiss (those controls own their
  touches); anywhere else it does.
- Device-only, not covered by tests: E6 (pause on background is `video_player`'s own observer),
  H2 rotation keeping the video position, real Save/Share, Hero flight look, TalkBack.

## Device check (user, 15 items)

`media.md` § Device check list, items 1–15. **User device PASS 2026-10-30.**

## Follow-up after device PASS (user, 2026-10-30)

Two asks from the device run: the bubble thumbnail looked pixelated, and a thumbnail that shows
fine while the full photo isn't on the phone felt misleading.

- **Thumbnail size.** `generateImageThumbnail` now makes 640px at 70% (was 200px at 60%). A 210dp
  bubble is ~630px on a 3x screen. Only the two constants changed in `lib/services`; it applies to
  new sends only, since the sender bakes the thumbnail in.
- **Downloaded bubbles draw the full file.** New read-only `mediaFullLocalProvider` (watches the
  blob row via new `MediaBlobDao.watchById`, never starts a download) gives the full file when the
  row is `ready` and the file exists. The photo bubble then draws it with `cacheWidth` = bubble
  width × DPR, the thumbnail standing in until its first frame. This also sharpens old messages
  once opened.
- **Not-downloaded disc.** A positive "not on disk" (no row, queued, failed, evicted, file gone)
  shows a centre `MediaDisc` with `Icons.download_rounded` on photos, and swaps the video's play
  glyph for it; the labels become "Open image, not downloaded" / "Open video, not downloaded". An
  unknown row (stream not emitted yet / error) shows no disc, so nothing claims what it hasn't seen.
  The video's old inline disc is now the shared `MediaDisc` in `expiry_badge.dart`.
- Known limit: your own sent photo shows the disc until you open it, because the sender's full file
  isn't kept in the media cache after upload. It is truthful; keeping it is a media-send (12.4)
  question.

Gates: `test/media/media_download_state_test.dart` +9 (5 widget, 4 provider). RED proved by forcing
`notDownloaded = false` and `full = null` in both bubbles: 3 widget tests failed; restored, 9/9.
Full suite **650/650** (641 + 9, no existing test changed). `flutter analyze` 0 errors. `git diff
--check` clean. Frozen diff: `lib/infrastructure` and `lib/features/chat/providers` empty;
`lib/services` = the two thumbnail constants + doc line only. `trail check`: no conflicts. No
independent reviewer for this follow-up (small, test-covered); not yet seen on a device.
