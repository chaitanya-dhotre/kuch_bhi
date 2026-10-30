# Media fullscreen: one viewer, opens at once, honest states (acceptance checklist, Page 9)

Date: 2026-10-30. Visual ground truth: **`docs/design/pages/media.html`** (sections S1–S15, numbered;
S1 = every way into fullscreen media, in scope or not; S12 = which viewer actions the app and PocketBase
support today; S13 = the parked media items, in scope or a separate task; S15 = diff summary). Authority:
`docs/design/00-foundation.md` (tokens/laws) → `docs/design/10-registry.md` (shared pieces) → this
checklist. Page letters A–J are page-local; decisions are numbered (bottom). Line refs, as of `1a8d416`:
`mv` = `lib/features/media/screens/media_viewer_screen.dart`, `ib` =
`lib/features/chat/widgets/image_message_bubble.dart`, `vb` = `lib/features/chat/widgets/video_message_bubble.dart`,
`vp` = `lib/features/chat/widgets/video_player_screen.dart`, `md` = `lib/features/media/screens/media_docs_screen.dart`,
`mb` = `lib/features/chat/widgets/message_bubble.dart`, `ar` = `lib/core/router/app_router.dart`, `cp` =
`lib/features/chat/providers/chat_provider.dart`, `bs` = `lib/infrastructure/media/media_blob_store.dart`.

**Starting point (audited 2026-10-30, trail grep + plain grep).** `MediaViewerScreen` is built in **3 live
places** (`ib:44`, `vb:117`, `md:158`) and **1 dead GoRoute** (`ar:197-203`, `AppRoutes.mediaViewer`
`ar:43`, nothing navigates to it, and its builder casts `state.extra`). `Hero(` exists at `ib:146`,
`md:224`, `mv:255` only. No other `PhotoView`, `InteractiveViewer` (except the avatar cropper) or
fullscreen viewer exists. Existing coverage: `test/chat/media_link_widgets_test.dart` (image skeleton under
reduced motion, overrides `mediaFileProvider`); `test/grep_gates_test.dart` gate 10 (exempts `mv`). **No
test opens the viewer.** Suite baseline **592/592** (run 2026-10-30, this session).

**Smells, confirmed (not assumed).**
1. **Two video players? No: one live, one dead.** The registry says `vb` still references
   `VideoPlayerScreen`; it does not. `vb` opens `MediaViewerScreen` (`vb:117`). `VideoPlayerScreen` (`vp`,
   141 lines, its own chewie + `Gal`) has **zero references** in `lib/` and `test/`. L3 is met in practice;
   the dead file and the dead route are deleted here (A3).
2. **Fetch, then open, in silence.** Every entry point awaits the full download + decrypt before it pushes
   (`ib:124-131`, `vb:104-114`, `md:151-155`), with no feedback. Offline on an uncached photo,
   `mediaFileProvider` returns only after its **45s** wait for the media row (`cp:74-80`), then nothing
   happens. The image tap has no in-flight guard (two taps = two viewers); the video's `_opening` flag is
   never reset if the future throws (`vb:106-114`), so the video can't be opened again.
3. **`$e` in user-visible text:** `Share failed: $e` (`mv:138`), `Save failed: $e` (`mv:168`), raw `SnackBar`s.
4. **Chrome fails contrast and C1.** Top and bottom bars are `LinearGradient`s (`mv:288`, `mv:356`), a C1
   breach (no gradients on chrome). The date line sits where the gradient is thin: `white70` over a white
   photo measures about **1.4:1**. Labels are 12px `white70` (`mv:424`).
5. **Video init has no error path** (`mv:91-111`, no try): a bad file spins forever.
6. **Video can't be swiped away** (`mv:187`, `:191`); **the top bar says "Photo"/"Video"**, not the sender
   (`ib:48`, `vb:121`, `md:279`); the action buttons are `GestureDetector`s with no semantics (`mv:406`).
7. **System UI:** immersive from the first frame (`mv:65`), restored to `manual` + all overlays (`mv:83`), not
   the app's edge-to-edge; the route is an opaque `MaterialPageRoute`, so swipe-down shows black, not the chat.
8. **Swipe-down vs zoom:** the outer vertical-drag detector wraps `PhotoView`; nothing stops a vertical pan
   on a zoomed photo from dismissing it.

**Routing.** Claude end to end (spec, implementation, grading); Omnirush down until 2026-11-02 17:30 IST.
If phase 2 starts after that time, the optimiser routes it (this checklist + `media.html` are the brief). The
grading pass is a fresh-context reviewer (subagent or `/code-review`), never the implementer.

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test` green
(baseline **592/592**, plus the new tests, with no existing test edited to pass) · test-gate files below
green · `git diff --check` clean (and no trailing whitespace in new files) · the J1 grep gate green (proved
RED once) · `trail check` clean · frozen-method diff vs HEAD unchanged · fresh-context review with no open
BLOCK, findings recorded in `media-work-log.md` · device captures of the items in the device-check list ·
user device PASS (no commit without it).

**Spec status: user PASS 2026-10-30; every deferred decision = its default (1–17).** Five media requests
were added at review; one is pulled in here (B6, decision 17), the other four are separate tasks (see "User
requests 2026-10-30" at the bottom, and `docs/backlog.md` §12).

**Server facts.** No live PocketBase read is needed or was made. Retention (`message_media.expires_at`) is
set at upload by type + quality (`media_upload_service.dart:46`); the blob store's failure classes come from
the HTTP status (`bs:250-262`: 404 → `dead_link`, 401/403 → `expired`, 5xx/other → stays `queued`).

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence; `[ ]` pending,
partial, or blocked.

---

## ⛔ Frozen (read first: a breach here is an automatic FAIL)

Out of scope and frozen: **how media is fetched, decrypted, uploaded and rendered in the bubble.**
`lib/infrastructure/media/media_blob_store.dart` (whole file), `mediaFileProvider` and `MediaRef`
(`cp:20-83`), `lib/services/media_upload_service.dart` (whole file), `message_repository_impl.dart` (whole
file), E2E and key code anywhere, the composer (`message_input.dart`), the bubbles' rendering (everything in
`ib` / `vb` / `mb` except the tap handlers and the one new `senderName` parameter, A2/A4), the Media & docs
grid and tabs (`md` except `_MediaGridTile._open`, A2), the voice sheet.

When an edited file holds frozen code (`ib`, `vb`, `mb`, `md`), every other method in it is diffed against
HEAD **at function level** and must be byte-identical. No timeout is ever wrapped around `requestBlob` /
`mediaFileProvider` (they decrypt inside); the viewer does no network work of its own. Read for context only,
do not re-solve:

- `.trail/learnings/2026-10-29-a-media-download-that-failed-stays-chaitanya.md` (any retry invalidates the provider first)
- `.trail/learnings/2026-10-29-restore-is-skipped-when-message-sync-chaitanya.md` (decrypting reads the device key only)
- `.trail/learnings/2026-10-29-choosing-high-quality-for-a-photo-chaitanya.md` (High halves retention)
- `.trail/learnings/2026-10-28-group-screens-amber-and-red-text-chaitanya.md` (amber/red text contrast)
- `.trail/learnings/2026-10-29-a-router-refresh-rebuilds-a-screen-chaitanya.md` (no route extras)

## A. Entry points and handoff (S1, S9)

- [ ] **A1 MUST (decision 2)** `MediaViewerArgs` becomes `{conversationId, serverId, mediaType
  ('image'|'video'), senderName, timestamp, heroTag?, thumbPath?}`. `localPath` goes. The viewer is a
  `ConsumerStatefulWidget` that reads `mediaFileProvider(MediaRef(conversationId, serverId))` itself.
- [ ] **A2 MUST** The three entry points push **at once** (no await before `push`), each with the thumbnail
  file it already shows as `thumbPath`: chat photo (`ib` tap, Hero `media_{serverId}`), chat video (`vb` tap,
  Hero `media_{serverId}`, new), Media & docs Photos/Videos tile (`md._open`, Hero `media_docs_{recordId}`,
  unchanged tag). `vb`'s `_opening` flag goes (nothing awaits any more). A second tap while the route is
  pushing does not push a second viewer (the push is synchronous; test it).
- [ ] **A3 MUST (decision 13)** Delete `vp` (whole file) and the `/media-viewer` GoRoute + `AppRoutes.mediaViewer`
  (`ar:43`, `ar:197-203`). Nothing else references either (grep before and after). No viewer data travels in
  route extras.
- [ ] **A4 MUST** The top bar names the sender: chat → `mb` passes its `senderName` into `ImageMessageBubble` /
  `VideoMessageBubble` (new optional `senderName` parameter, default `''`), the bubble passes **You** when
  `isMine`, else the name, else **Photo** / **Video**. Media & docs keeps **Photo** / **Video** (it has no
  sender; decision 11).
- [ ] **A5 MUST** Route = `PageRouteBuilder(opaque: false)` with a fade (`motionBase` 250ms in, `motionFast`
  150ms out), so the chat shows behind a swipe-down (C3). Reduced motion: zero-duration transition (G2).

## B. Ground and chrome (S2, S3; decisions 1, 4)

- [ ] **B1 MUST (decision 1)** The viewer subtree runs on the **AMOLED tokens** in every app theme:
  `Theme(data: warmPopDark(amoled: true, fontFamily: <the user's font>))`. Ground = `t.bg` (#000). No
  `Colors.*` / `Color(0x` in `mv` (J1).
- [ ] **B2 MUST (decision 4)** One top bar, no bottom bar: close (48dp, tooltip **Close**) · column [sender
  `title` 16/22 w600, 1 line, ellipsis; date `caption` 13/18 w400, format `MMM d, yyyy · HH:mm` (today's),
  1 line] · **Share** (48dp, tooltip **Share**) · **Save** (48dp, tooltip **Save to gallery**). All text and
  icons `t.ink` (#F3EDE3). No `t.inkSoft` on the scrim (2.2:1 over a white photo).
- [ ] **B3 MUST** The bar background is **flat** `t.bg` at 64% alpha (no gradient, C1), full width, under the
  status bar (`SafeArea` inside it). Measured: ink on 64% black over pure white = **5.7:1**; over black 18:1.
- [ ] **B4 MUST** A single tap on the media toggles the chrome (bar + video controls) with an opacity fade
  (`motionFast`). Hidden chrome is `IgnorePointer` + `ExcludeSemantics`. With
  `MediaQuery.accessibleNavigationOf(context)` the chrome never hides.
- [ ] **B5 MUST** Actions appear only once the full file is loaded (not on the thumbnail, error or expired
  states). Close is always there.
- [ ] **B6 MUST (decision 17, user item 3)** Once the full file is loaded, a third bar line (caption 13/18,
  `t.ink`, 1 line) says when the server drops it, from `LocalMediaFile.expiresAt`: more than 7 days left →
  **Expires Nov 29** (with `, 2027` only when the year differs); 1–7 days → **Expires in 3 days**
  (**in 1 day**); under 24 hours → **Expires in 5 hours** (**in 1 hour** under 2 hours). `expiresAt` null → no
  line. Same thresholds as the bubble pill (`compactExpiryLabel`, `expiry_badge.dart:7-17`), computed by one
  new pure function next to it, unit-tested at the boundaries (7d, 24h, 1h, past).

## C. Photo gestures (S4; decision 8)

- [ ] **C1 MUST (decision 8)** Zoom = Flutter's `InteractiveViewer` (min 1× = fit, max 4×) with a
  `TransformationController`; `photo_view` leaves `pubspec.yaml`.
- [ ] **C2 MUST** Double-tap at fit → 2.5× centred on the tap point; double-tap when zoomed → back to fit.
  Animated over `motionBase`; reduced motion → jumps.
- [ ] **C3 MUST** Vertical drag at fit scale moves the media with the finger and fades the ground
  (opacity `1 - |dy|/300`, floor 0.3), so the chat shows through. Release past 120dp or faster than 600 px/s
  (today's thresholds, either direction) → pop; otherwise snap back over `motionFast` (reduced motion → jump).
- [ ] **C4 MUST** When zoomed (scale > 1.01) a vertical drag pans the photo and **never** dismisses.
- [ ] **C5 MUST** GIF files animate (`Image.file` does; one widget test with a 2-frame GIF asserts the
  frame changes). They arrive as JPEG today (S13 row 1), so this is future-proofing at zero cost.

## D. Loading, errors, offline (S5, S6; decision 3)

- [ ] **D1 MUST** Loading = the thumbnail (`thumbPath`, `BoxFit.contain`, inside the Hero) with an R3a
  `BusySpinner(size: 32)` centred. No skeleton, no lone spinner on black when a thumbnail exists; with no
  thumbnail, the spinner alone. When the full file lands it fades in over the thumbnail (`motionFast`; reduced
  motion → swap).
- [ ] **D2 MUST** Offline while loading (`isOnlineProvider` false): under the spinner, **Waiting for a
  connection** (body 15/22, ink). On offline → online, `ref.invalidate(mediaFileProvider(ref))` then re-read
  (the learning: a retry invalidates first). Nothing is dimmed (no action is offered).
- [ ] **D3 MUST** Load returns `null` → centred state block: icon (48, `t.ink`), **Couldn't load this photo.** /
  **Couldn't load this video.** (body, ink), R3 secondary button **Try again** →
  `ref.invalidate(...)` then re-read. Offline → **Try again** at a single 38% dim, not enabled in semantics,
  with **Available online** (`kOfflineActionHint`) beside it, not inside the dim.
- [ ] **D4 MUST (decision 3)** Before D3, a read-only look at the blob row (`dao.byId(blobId)`, through a new
  provider in `lib/features/media/providers/media_viewer_providers.dart`; no write, no pipeline call):
  `failed` + `expired`/`dead_link`, or a loaded file whose `expiresAt` is past → timer-off icon +
  **This photo has expired.** / **This video has expired.** (no button); `failed` + `decrypt`/`verify` → lock
  icon + **Can't decrypt** (foundation §6, no button). Anything else → D3.
- [ ] **D5 MUST** The photo itself failing to decode (`Image.file` `errorBuilder`) → D3's block.
- [ ] **D6 MUST** No timeout is added anywhere (see ⛔). An error is shown only for the load the viewer started.

## E. Video (S7; decisions 7, 9)

- [ ] **E1 MUST (decision 7)** Own controls on `video_player`; `chewie` leaves `pubspec.yaml`. Controller from
  the loaded file; `initialize()` in `try`; failure → **Couldn't play this video.** + **Try again** (disposes
  the controller, invalidates the provider, re-reads). `$e` only in `debugPrint`.
- [ ] **E2 MUST** Until initialised: the thumbnail poster + R3a (D1). Autoplay once initialised; no loop.
- [ ] **E3 MUST** Centre disc 64dp, `t.accent` fill, `t.onAccent` icon: play / pause / replay (at the end).
  Semantics button **Play** / **Pause** / **Play again**. Shown with the chrome; at the end the chrome shows.
- [ ] **E4 MUST** Bottom strip (same flat 64% scrim, `SafeArea`): elapsed `0:12` · scrubber · total `1:05`
  (caption 13/18 ink, tabular figures). Scrubber = `VideoProgressIndicator(allowScrubbing: true)`, played
  `t.accent` (fill), buffered `t.ink` @ 40%, track `t.ink` @ 16%, touch height ≥ 48. Semantics label
  **Video position**. No mute button (hardware volume, decision 7).
- [ ] **E5 MUST (decision 9)** Swipe-down works on video as on photos (C3); the controller is disposed on pop.
- [ ] **E6 MUST** App to background → playback pauses (`video_player`'s own lifecycle observer; device check);
  back → stays paused.

## F. Save and share (S8; decision 5)

- [ ] **F1 MUST** Save: `Gal.hasAccess()` → if false `Gal.requestAccess()` → `Gal.putImage(path)` /
  `Gal.putVideo(path)` (no `readAsBytes`). Share: `Share.shareXFiles([XFile(path)])`. Both behind one
  `mediaActionsProvider` (same new providers file) so tests override it; no platform channel in tests.
- [ ] **F2 MUST** While running, the button's icon is replaced by R3a `BusySpinner` and a second tap is
  ignored. Neither is bounded at 8s (local work, no network).
- [ ] **F3 MUST** R5 toasts only (`showToast`), fixed copy: **Saved to gallery** · denied →
  **Allow photo access in Settings to save.** (error) · `GalExceptionType.notEnoughSpace` →
  **Not enough space to save.** (error) · anything else → **Couldn't save. Try again.** (error) · share throws →
  **Couldn't share.** (error). The share sheet being dismissed is not an error. No `$e` / `e.toString()`
  outside `debugPrint`.
- [ ] **F4 MUST** Save and Share are **local**: never dimmed offline.
- [ ] **F5 MUST (decision 5)** Default: Save and Share on every photo and video, no confirmation. (If you pick
  5B or 5C, F5 becomes that.)

## G. Hero, motion (S9)

- [ ] **G1 MUST** Hero child on both sides is the thumbnail image (bubble: `BoxFit.cover`; viewer:
  `BoxFit.contain`), so the flight is the same picture. Video gets the Hero too (A2).
- [ ] **G2 MUST** `MediaQuery.disableAnimationsOf(context)`: no `Hero` in the tree (tag ignored), zero-duration
  route, chrome toggle, image swap, snap-back and double-tap all jump. The drag still follows the finger
  (direct manipulation, not animation).

## H. System UI and orientation (S3, S10)

- [ ] **H1 MUST** `AnnotatedRegion<SystemUiOverlayStyle>` with light icons and transparent bars. Chrome shown
  → `SystemUiMode.edgeToEdge`; chrome hidden → `SystemUiMode.immersiveSticky`; `dispose` →
  `SystemUiMode.edgeToEdge` (the app's mode; `main.dart:49` sets transparent bars). Test: record the
  `SystemChrome.setEnabledSystemUIMode` platform calls.
- [ ] **H2 MUST** No orientation lock (the app allows all four, `main.dart:42`). Rotating keeps the video
  position and play state; a zoomed photo resets to fit. Landscape: bar and strip respect the cutout
  (`SafeArea` left/right).

## I. A11y, large text

- [ ] **I1 MUST** Close / Share / Save are buttons with those labels; the photo is one node labelled
  **Photo from {sender}, {date}** (video: **Video from …**). Asserted with `tester.getSemantics`.
- [ ] **I2 MUST** 360×640 at `textScaler 2.0`, system font AND `PlusJakartaSans`: top bar (long sender
  name), video strip, the error/expired/can't-decrypt blocks, the offline line: no overflow (blocks wrap and
  centre; bar text ellipsises at 1 line).
- [ ] **I3 MUST** No `Text` in `t.accent` or `t.error` anywhere in `mv` (accent = disc/scrubber fill only).

## J. Hygiene and gates

- [ ] **J1 MUST** NEW grep test **inside `main()`** of `test/grep_gates_test.dart`, "Page 9 media": in `mv` and
  the new providers file, none of `Colors.`, `Color(0x`, `LinearGradient`, `SnackBar(`,
  `CircularProgressIndicator`, `showModalBottomSheet`, `$e`/`e.toString()` outside `debugPrint` lines; in
  `lib/`, no `VideoPlayerScreen`, `package:chewie`, `package:photo_view`, `AppRoutes.mediaViewer`. Gate 10's
  comment ("media_viewer_screen is fully exempt") is left as is; J1 is the new rule. Prove RED once, then GREEN.
- [ ] **J2 MUST** Registry C10 amended (below), same commit.

## Registry amendments (same commit, L2)

| ID | Amendment |
|---|---|
| C10 | `MediaViewerScreen(args: MediaViewerArgs(conversationId, serverId, mediaType, senderName, timestamp, heroTag?, thumbPath?))`: the ONE fullscreen viewer for photos and videos; opens at once on the thumbnail and loads the full file itself; AMOLED ground in every theme; own video controls; `video_player_screen.dart` and the `/media-viewer` route deleted. Opened by the chat photo/video bubbles and the Media & docs grid only. |

## Test gates (mandatory)

Screen tests override `mediaFileProvider`, `isOnlineProvider`, the new blob-status provider and
`mediaActionsProvider`; no platform channels except the recorded `SystemChrome` calls; video via a fake
`VideoPlayerPlatform` (`video_player_platform_interface` is already in `pubspec.lock`; add it to
`dev_dependencies`) or an injected controller factory. Semantics via `tester.getSemantics`. Large text = 360×640,
`textScaler 2.0`, once with the system font and once with `PlusJakartaSans`.

- [ ] NEW `test/media/media_viewer_screen_test.dart`: first frame shows the thumbnail + R3a while the provider is
  pending · data → full image, chrome with Close/Share/Save buttons (semantics) · `null` → **Couldn't load this
  photo.** + **Try again**; tapping it rebuilds the provider (count builds) · offline → **Try again** dimmed once,
  not enabled, hint outside the dim · offline pending → **Waiting for a connection**; flipping online re-reads ·
  blob `failed/expired` → expired copy, no button · `failed/decrypt` → **Can't decrypt**, no button · tap toggles
  the chrome; with `accessibleNavigation` it stays · save → **Saved to gallery**; save throws `Exception('boom')`
  → **Couldn't save. Try again.** and no `boom` in any text; share throws → **Couldn't share.** · drag 150dp at fit
  pops; same drag after a double-tap zoom does not · reduced motion → no `Hero` · `setEnabledSystemUIMode`
  calls: edge-to-edge at open, immersive on hide, edge-to-edge on dispose · animated GIF advances a frame ·
  no `Text` coloured `t.accent`/`t.error` · 360×200% + Jakarta (loaded, error, expired) · the expiry line
  shows once loaded and not before; `expiresAt` null → no line. The B6 label function gets its own unit
  test (boundaries 7d, 24h, 2h, past) in `test/chat/expiry_label_test.dart` (new).
- [ ] NEW `test/media/media_viewer_video_test.dart`: poster + R3a until initialised · init throws → **Couldn't
  play this video.** + **Try again** · disc labels **Pause** while playing, **Play** paused, **Play again** at the
  end · scrubber node **Video position** · swipe-down pops and disposes the controller · 360×200% + Jakarta.
- [ ] NEW `test/media/media_entry_points_test.dart`: chat photo tap pushes the viewer on the same frame with the
  provider still pending, Hero `media_{id}`, sender **You** on mine and the name on theirs · chat video the same ·
  Media & docs tile pushes with `media_docs_{recordId}` · a double tap pushes one viewer.
- [ ] `test/grep_gates_test.dart`: J1, inside `main()`. RED once (e.g. a stray `Colors.white` in `mv`), then
  GREEN; both recorded in the work log.
- [ ] Existing tests stay green **unedited**, in particular `test/chat/media_link_widgets_test.dart` and the
  whole of `test/grep_gates_test.dart` above J1.
- [ ] Count: the work log records **592 + N = total**, N = tests added, and the suite total matches.
- [ ] Function-level diff vs HEAD of every frozen method in an edited file (see ⛔): empty.
- [ ] Full suite green · analyze 0 errors · `git diff --check` clean · `trail check` clean · `flutter pub get`
  clean after the two dependency removals.

## Device check list (phase 2, M52 if connected, else Redmi S2; you do every real save/share)

1. Chat (light): tap a photo → the viewer opens at once on the thumbnail, the Hero flies, the sharp photo
   fades in. Top bar: sender name (theirs) / **You** (yours), date; Close, Share, Save.
2. Same in dark and AMOLED: the viewer is black in all three; the bar reads clearly over a white photo
   (shoot one of a white wall or page).
3. Tap → chrome and status/nav bars hide; tap → both come back. Close → the chat's status bar looks as before
   (no black band, no overlap).
4. Pinch to 4×; double-tap on a face → zooms there; double-tap → fit. Zoomed, drag up/down → pans, never closes.
5. At fit, drag down slowly → the chat shows through; let go early → snaps back; drag far or flick → closes.
6. Airplane mode, a photo you never opened → thumbnail + spinner + **Waiting for a connection**; turn the network
   on → the photo loads by itself.
7. Airplane mode, a photo you opened before → opens fully; Save and Share work.
8. **Save** a photo (you do it) → **Saved to gallery**; it is in the gallery, no location in its details. Save a
   video. Deny the permission once on an Android ≤ 9 device if you have one (else skip).
9. **Share** a photo to yourself (you do it); dismiss the share sheet once → no error toast.
10. A video: opens on its poster, plays; tap → controls; scrub; pause; play to the end → **Play again**;
    swipe down closes; home button mid-play → paused on return; rotate → keeps playing at the same spot.
11. Media & docs → Photos and Videos tiles open the same viewer.
12. Settings → reduce animations (Android "Remove animations"): open/close have no flight, no fade.
13. Settings → largest text + Plus Jakarta Sans: long sender name ellipsises; video strip and any error block fit.
14. TalkBack: Close, Share, Save, Play/Pause, Video position are announced; the chrome does not hide.
15. The bar's third line: a photo sent today says **Expires** + a date about 60 days out (Normal) or 30
    (High); a video about 30 / 15 days.

Items 1–15: **user device PASS 2026-10-30.** Follow-up added after it (see work log):
16. A photo or video you never opened shows a centre download disc; after opening it once, back in
    the chat the photo is sharp (full file at bubble size) and the video disc says Play.
17. A photo sent after this change looks sharp in the bubble even before anyone opens it.

## Out of scope (do NOT build on this page)

Everything in ⛔ · swipe between items (decision 6) · S13's separate tasks · S14's found-not-here items ·
forward / delete / reply / star from the viewer (decision 14) · screenshot blocking (decision 12) · keeping
the screen awake during video (decision 10) · a fullscreen avatar viewer · captions (the app has none) ·
the Media & docs grid · mascots (page 10).

---

## Diff vs current implementation

| # | Area | Today (file:line) | Spec | Checklist |
|---|---|---|---|---|
| 1 | Open | await full download + decrypt, then push; silent (`ib:124-131`, `vb:104-114`, `md:151-155`) | push at once on the thumbnail; the viewer loads | A1, A2, D1 |
| 2 | Offline open, uncached | ~45s silent wait (`cp:74-80`), then nothing | thumbnail + **Waiting for a connection**; auto-load on reconnect | D2 |
| 3 | Double tap on a photo | two viewers (no guard, `ib:124`) | one | A2 |
| 4 | Video reopen after a throw | blocked forever (`_opening` not reset, `vb:106-114`) | flag removed | A2 |
| 5 | Video player | one live (`mv`) + one dead (`vp`, 0 refs; registry wrong) | one; `vp` deleted | A3 |
| 6 | `/media-viewer` route | dead; casts `state.extra` (`ar:197-203`) | deleted | A3 |
| 7 | Title | "Photo" / "Video" for others (`ib:48`, `vb:121`) | sender name / **You** | A4 |
| 8 | Route | opaque `MaterialPageRoute`; drag shows black | non-opaque fade; chat shows through | A5, C3 |
| 9 | Ground | `Colors.black` hardcoded (`mv:182`) | AMOLED tokens in every theme | B1 |
| 10 | Bars | top + bottom `LinearGradient` (`mv:288`, `:356`), C1 breach; date `white70` ~1.4:1 on a white photo | one flat 64% bar, ink only, 5.7:1 worst case | B2, B3 |
| 11 | Actions | bottom bar, `GestureDetector`, no semantics, 12px `white70` labels (`mv:391-430`) | top-bar `IconButton`s with tooltips | B2, I1 |
| 12 | Hidden chrome | still in semantics; always toggles | `IgnorePointer` + `ExcludeSemantics`; never hides under TalkBack | B4 |
| 13 | Zoom | `PhotoView` (`mv:240-258`); double-tap cycles fixed scales | `InteractiveViewer`, 2.5× at the tap point | C1, C2 |
| 14 | Swipe-down vs zoom | can dismiss while zoomed (`mv:184-197`) | only at fit | C4 |
| 15 | Loading | lone white `CircularProgressIndicator` (`mv:244`, `:263`) | thumbnail + R3a | D1, E2 |
| 16 | Errors | broken-image icon only (`mv:250`); none for video | load / expired / can't-decrypt blocks; **Try again** invalidates first | D3–D5, E1 |
| 17 | Video init | no try; spins forever on a bad file (`mv:91-111`) | try; error + **Try again** | E1 |
| 18 | Video controls | chewie, its own tap layer and options sheet; overlapping our bottom bar | own disc + strip; one tap toggles everything | E3, E4 |
| 19 | Video swipe-down | disabled (`mv:187`, `:191`) | enabled | E5 |
| 20 | Save | `putImageBytes(readAsBytes)`; no access check (`mv:146-176`) | `hasAccess`/`requestAccess` + `putImage(path)` | F1 |
| 21 | Toasts / `$e` | raw `SnackBar`, `Share failed: $e`, `Save failed: $e` (`mv:138`, `:168`) | R5, fixed copy | F3 |
| 22 | Busy | white `CircularProgressIndicator` 24 (`mv:411-419`) | R3a | F2 |
| 23 | Hero | photo only; full-res `PhotoView` inside the Hero (`mv:255`) | photo + video; thumbnail on both ends | G1 |
| 24 | Reduced motion | ignored | no Hero, everything jumps | G2 |
| 25 | System UI | immersive from frame 1 (`mv:65`); restored to `manual` (`mv:83`) | edge-to-edge with chrome, immersive without, edge-to-edge on close | H1 |
| 26 | Dependencies | `photo_view`, `chewie` | removed | C1, E1 |
| 27 | Tests | none open the viewer | 3 new files + J1 | Test gates |
| 28 | Expiry date | shown nowhere until the last 7 days (bubble pill `3d`/`5h` only) | third bar line in the viewer, always | B6 |

---

### Deferred decisions (you decide at spec review; default = recommended)

Every candidate was checked against what the app and PocketBase support today (S12). Nothing below is built
unless its default stands or you pick it.

1. **Media is always on black (AMOLED tokens) in every app theme.** Photos read best on black, and on
   AMOLED screens the ground costs no power. Alternative: follow the app theme (light ground in light mode).
2. **Open first, load inside the viewer** (A1/A2): instant response, one place for loading/offline/error.
   Alternative: keep fetch-then-open and add a busy ring on the tapped bubble/tile (3 places, still no error
   state).
3. **Read the blob row (read-only) to tell expired and can't-decrypt from a plain failure** (D4), so **Try
   again** is only offered when it can work (the store never retries `failed`). Alternative: one generic
   **Couldn't load** + **Try again** for everything.
4. **Actions in the top bar, no bottom bar** (no overlap with video controls, one chrome). Alternative: keep
   a bottom action bar (and lift the video strip above it).
5. **Save / Share leave the app decrypted.** Photos were re-encoded without EXIF at send (no GPS);
   **videos are not verified** (`video_compress` transcodes; container metadata not checked). Default **5A**:
   Save + Share on everything, no confirmation (the sender already trusted the recipient; a confirm on
   every save is friction). **5B**: a one-time R20 notice before the first save/share: **Saved copies aren't
   encrypted** / **Anyone with access to your gallery or the app you share to can see it.** **5C**: hide Save
   + Share in conversations with disappearing messages on. Caveat: the `Message` entity has no per-message
   expiry (`messages_table.dart:47` has it; the entity does not), so 5C would go by the conversation's
   current setting, which also hides them on older, non-disappearing messages.
6. **Swipe between photos and videos: not on this page** → separate task. It needs a list source (chat-local
   media messages in order), a `PageView`, per-page providers and Hero per page; the viewer here is built so
   it slots into a page. Alternative: in scope now (roughly doubles the page).
7. **Own video controls, drop chewie** (one chrome, our tokens, no chewie options sheet, one dependency
   fewer); no mute button (hardware volume). Alternative: keep chewie with `showOptions: false` and accept
   its separate tap layer.
8. **`InteractiveViewer` instead of `photo_view`** (built in; can zoom at the tap point and tells us the scale
   for C4). Alternative: keep `photo_view`, double-tap zooms at the centre.
9. **Swipe-down closes videos too.** Alternative: photos only (today).
10. **Screen may sleep during long videos** (no wakelock; chat videos are short). Alternative: keep it awake
    while playing (`wakelock_plus`, already a transitive dependency, becomes a direct one).
11. **Media & docs shows "Photo" / "Video" as the title** (the grid has no sender). Alternative: look the
    sender up from the local message row (a new read on the message DAO).
12. **No screenshot blocking.** Android `FLAG_SECURE` would need a plugin or platform code, and blocks
    screenshots of the whole app while the viewer is open. Alternative: separate task.
13. **Delete the dead `video_player_screen.dart` and `/media-viewer` route** (L3; the route also breaks the
    route-extras rule). Alternative: leave them (and fix the registry line only).
14. **No forward / delete / reply / star in the viewer.** Forward does not exist in the app; delete, reply
    and star live in the long-press menu. Alternative: a ⋮ menu (R19 sheet) with delete for me / reply,
    as a separate task.
15. **The parked media items (S13)**, each with its default: (a) GIF sent as JPEG, animation lost
    (`media_upload_service.dart:126-132` compresses every image to JPEG) → **separate task** (upload
    pipeline; the viewer already animates GIFs, C5). (b) Pixelated thumbnails (200px at 60%,
    `media_upload_service.dart:139-151`) → **separate task** (upload); in the viewer the thumbnail only
    shows until the full file lands. (c) Offline media resend that never retries → **separate task**
    (outbox/upload). (d) Upload cancel → **separate task** (composer + upload). (e) Chat J8, determinate
    download progress → **separate task**: the store downloads with one `http.get` (no progress source), so
    the viewer uses an indeterminate R3a. (f) 200% overflows on Home rows and the chat app bar's "Last seen"
    → **separate task** (not media files; one small session). (g) No timeout on the store's download
    (`bs:250`) → **separate task** (frozen pipeline; the bound goes on the `http.get` only, never around
    decrypt).
16. **No live PocketBase read for this page.** Nothing here depends on a server rule.
17. **The viewer always says when the media expires** (B6). Today the date is invisible until the bubble's
    pill appears in the last 7 days, so a 60-day photo gives no warning for 53 days. Alternative: show the
    line only in the last 7 days, like the pill.

### User requests 2026-10-30 (triage; default = recommended)

| # | Request | Here or separate | Why |
|---|---|---|---|
| 1 | Share photos/videos/files into the app from other apps or a file manager | **separate task** | New feature: Android `SEND`/`SEND_MULTIPLE` intent filters (none today), a receive plugin, a "send to which chat" picker, then the existing send pipeline. Nothing in the viewer. |
| 2 | Media bubble states in the chat (deleted, can't decrypt, expired, failed, loading) | **separate task, right after this page** | Bubble rendering is frozen here. It reuses this page's read-only blob-status provider (D4), so it goes after Page 9 lands, not alongside it (same files). Today: photo/video bubbles have skeleton, broken-image and a 10.5px **Media expired**; no can't-decrypt or failed-download state; the expiry pill shows only in the last 7 days. |
| 3 | Where the media delete date shows | **here** (B6, decision 17) | The viewer is where you decide to save; the bubble pill stays as is (request 2 can revisit it). |
| 4 | Keep the original format; a simple crop / mark-up / video trim screen before sending | **separate task ("media send")**, merged with parked items 15a (GIF) and 15b (thumbnails) | Upload pipeline + composer, both frozen here. Watch out: "original" must still drop location data (the photo learning: every photo is re-encoded to strip GPS), so keep GIF/PNG/WebP as they are but re-encode JPEG/HEIC without EXIF. Video trim needs a native transcoder: check what is maintained before choosing (the common FFmpeg Flutter wrapper was retired in 2025). |
| 5 | Album bubble for several photos/videos sent together: sideways scroll, opens as an auto-arranged collage | **separate task ("albums")**, owns decision 6 (swipe between items) | Needs a way to know which media belong together (a shared batch id on the messages, or grouping by sender + time), a new bubble, the collage, and a viewer that pages between items. The viewer built here takes one item; albums wraps it in a pager. |
