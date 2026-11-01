# Media send, phase 2 part E–H: Mimo brief

Paste everything below the line into `freebuff --cwd /home/chaitanyadhotre/kuch_bhi --trust-agents`.
Claude grades the result. B–D (send path, blob store, resume, cancel, progress) are DONE and
uncommitted in the working tree; build on them, do not change them.

---

You are implementing part of a spec in a Flutter app (kuch_bhi: Riverpod, drift, PocketBase). Read
these first, in this order, and nothing else whole:

1. `docs/design/pages/media-send.md`: sections ⛔ Frozen, A, D2, D5, E, F, G, H, Test gates. Your
   items are **A1, A2, D2, the UI half of D3 and D5, B3's legacy look, E1–E6, F1–F7, G1–G3** and
   the tests `media_bubble_states_test`, `media_edit_screen_test`, `media_format_test`.
2. `docs/design/pages/media-send.html`: the visual ground truth (S1 matrix, S2–S4 states, S7–S10
   editor). Open it in a browser or read the `draw(...)` calls near the bottom.
3. `docs/design/10-registry.md` rows R3, R3a, R5, R11, R19, R20 (use these, never raw widgets).
4. `docs/design/pages/media-send-work-log.md` (what is already built).

Use `trail ask "<question>" --source`, `trail skeleton <file>` and `sed -n` ranges. Never read a
whole large file.

## Already built (call these, do not reimplement)

- `uploadProgressProvider(localId)` in `lib/features/chat/providers/upload_progress_provider.dart`:
  `double?` 0–1 while an upload runs, `null` when none runs. `ref.watch` it in build; never await it.
- Own upload state of a media row: `isMine && isOpId(message.localId) && message.status != 'sent'`
  (`isOpId` in `lib/core/utils/op_id.dart`). `status == 'pending'` + progress `null` = **waiting**
  (no arc); progress non-null = **uploading** (arc); `status == 'failed'` = **failed**.
- `message_bubble.dart` already computes `mediaId` (server id, or the own op-id localId) and passes
  it to the four bubbles as `serverId`. Pass the bubbles what they need for the disc (localId +
  status) through new optional constructor params; keep existing params and tests working.
- Cancel: `await ref.read(messageRepositoryProvider).cancelMediaUpload(localId)` → `true` means
  cancelled: then `showToast(context, 'Upload cancelled')`. No confirm dialog (decision 6).
- Try again: `ref.read(messageRepositoryProvider).retryMessage(localId)`. Offline (`isOnlineProvider`
  false): the ↻ is `Opacity(.38)` once, not tappable, with **Available online** (`kOfflineActionHint`)
  outside the dim.
- `isOnlineProvider` (`lib/infrastructure/offline/connectivity_signal.dart`),
  `mediaBlobStatusProvider` + `MediaBlobStatus` (`lib/features/media/providers/media_viewer_providers.dart`).

## Files

Create:
- `lib/features/chat/widgets/media_upload_disc.dart`: **C15** `MediaUploadDisc({double? progress,
  VoidCallback? onCancel, VoidCallback? onRetry, bool enabled = true, ...})`. 44px on photo/video
  (reuse the look of `MediaDisc` in `expiry_badge.dart`: compose it, so this file has no `Colors.`),
  30px in the voice play / document icon slot on the own amber bubble (ink `onAccent` on the full
  accent shell, never accent ink on a faint shell). Arc = `t.accent` progress drawn with a
  `CustomPainter` (no `CircularProgressIndicator`); waiting = ✕ with no arc; failed = ↻. Reduced
  motion (`MediaQuery.disableAnimationsOf`): the arc jumps, no sweep. Semantics: button, label
  **"Photo, sending, 40 percent. Cancel"** (Video / Voice message / Document; waiting: "…, waiting
  for connection. Cancel"; failed: "… not sent. Try again").
- `lib/features/media/screens/media_edit_screen.dart`: **C14** `MediaEditScreen(file, type)` →
  `Future<MediaEditResult?>` (F1–F5, G1–G3, copy in H). Crop generalises
  `lib/features/profile/screens/crop_photo_screen.dart` (pan/zoom under a frame, `PictureRecorder`
  export at source resolution, no upscaling) to frames Original / Square + Rotate 90°. Draw: one pen
  (4dp at fit, scaled to source px), the six colours from S9 as ONE `const` list, Undo, Clear,
  canvas in `ExcludeSemantics`. Trim: `RangeSlider` in whole seconds under a `video_player` preview,
  start / end / length labels in m:ss with tabular figures, length ≤ 5:00, handles announced
  **Trim start** / **Trim end** with their m:ss value. GIF / animated WebP: no tools, caption
  **GIFs are sent as they are.** Close with edits → R20 **Discard changes?** / **Your crop and
  drawing will be lost.** / **Discard** (destructive); no edits → pops null. Android back = Close.
  Video load failure → R5 error **Couldn't open that video.** and pop.
- The three test files named in the spec's Test gates (bubble states, edit screen, format).

Modify (only what your items need):
- the four bubbles in `lib/features/chat/widgets/` (`image_`, `video_`, `voice_`, `document_message_bubble.dart`)
  and `message_bubble.dart`: the disc + captions per S1 (failed photo/video: ↻ disc with the pill
  **Not sent · Try again**; voice/doc failed: ↻ in the slot + **Not sent · Try again** text). Own
  sent photo with a ready full blob shows no download disc (already true once the blob is ready;
  keep it so). Legacy rows (non-op-id localId, `_OptimisticMediaPlaceholder`): a **failed**
  photo/video shows the static **Not sent** look with no Try again; leave pending legacy rows as
  they are (the existing `failed_media_placeholder_test` pins the pending spinner).
- `media_retry.dart` + `media_viewer_providers.dart` + `voice_message_bubble.dart`: E3/E4 (three
  ended captions **Media expired** / **No longer available** / **Can't decrypt** with
  `Icons.lock_outline`; `MediaBlobStatus` gains `deadLink`; voice gets the inline ended row, no
  spinner, no retry), E6 (expired caption 12px in the photo/video slot). Strings live next to
  `kOfflineActionHint` in `lib/features/chat/message_offline_policy.dart` (A2), never inlined twice.
- `lib/features/chat/widgets/message_input.dart`: after a photo/video pick open `MediaEditScreen`,
  then the existing quality sheet (GIF skips both the tools and the quality sheet, Normal
  retention), then the existing compress + send. F7: before compress, a file over
  `AppConstants.maxFileSizeMb` (100) → `showToast(context, 'Too big to send. The limit is 100 MB.',
  error: true)` and stop; check the compressed size again before `send`. Trim: pass the range to
  the compressor; the video thumbnail is taken at the trim start (decision 19).
- `lib/services/media_upload_service.dart`, ONLY `compressImage` (F6 format choice: PNG→PNG,
  static WebP→WebP, JPEG/HEIC/other→JPEG; output extension matches; keep EXIF stripped) and
  `compressVideo` (+ optional trim start/end seconds). Trim engine = the installed `video_compress`
  3.1.4 `compressVideo(startTime:, duration:)`. **Android passes `duration` as time cut from the
  END** (Transcoder's TrimDataSource), so call it with `startTime: start, duration: length − end`
  (comment it; device check 11 proves it). GIF / animated WebP (RIFF…WEBP with a VP8X chunk whose
  animation flag is set / an ANIM chunk) are never re-encoded: send the original bytes, `.gif` /
  `.webp`, matching mime. Add a seam so `media_format_test` can fake the compressor.

## Never touch (automatic FAIL)

`message_repository_impl.dart`, `media_blob_store.dart`, `upload_progress.dart`, anything under
`lib/data/` (incl. `*.g.dart`), `encryption_service.dart`, the upload/encrypt methods in
`media_upload_service.dart`, `media_viewer_screen.dart`, `reply_quote.dart`, the quality sheet's
content (`attach_sheets.dart`), the voice recorder. No existing test may be edited. No new
dependency. No `ffmpeg` anywhere.

## Rules (the repo's gates enforce some of them)

- No `ref` in any `dispose()`. Never `await ref.read(x.future)` on an autoDispose provider.
- No `$e` / `e.toString()` in user-visible text (only in `debugPrint`).
- New files: no `Colors.` (except the draw palette's one const list), no `Color(0x` outside it, no
  `LinearGradient`, `SnackBar(`, `CircularProgressIndicator`, `LinearProgressIndicator`,
  `showModalBottomSheet`. Use `context.t.*` tokens, R3 `AppButton`, R3a `BusySpinner`, R5
  `showToast`, R11 `Skeleton`, R19 `showAppSheet`, R20 `showConfirmDialog`.
- Any retry of a media download invalidates the cached provider first (as `MediaRetry` does).
- Respect reduced motion (no sweep, no Hero, instant tool switches).
- Every state and the editor must fit at 360×640 with `textScaler 2.0`, system font AND
  `PlusJakartaSans`: captions in fixed media slots use `FittedBox(fit: BoxFit.scaleDown)`.
- Semantics tests use `tester.getSemantics(...)`.

## Gates you run yourself before you stop

```
flutter test
flutter analyze
git diff --check
```

All green, 0 analyze errors, no existing test edited. Then append a short section to
`docs/design/pages/media-send-work-log.md` ("E–H, Mimo") listing files changed, tests added
(count), the suite total, and anything you could not do. Do not commit.

Claude grades the result; do not claim PASS.

---

# Round 2 (after Claude's grading, 2026-10-31)

Paste everything below this line into freebuff. Same rules, same never-touch list as round 1, plus:
do NOT touch `reply_quote.dart`, `media_viewer_screen.dart` or their tests (separate work), and do not
undo Claude's grading fixes (listed in `media-send-work-log.md`, "Grading round 1").

## 1. Rework the photo editor (`lib/features/media/screens/media_edit_screen.dart`), F3 + F4

Round 1 has no pan/zoom, the preview ignores Rotate, and strokes are normalised against the whole
screen box, so a burned-in stroke lands in the wrong place on a letterboxed photo. Build it like this:

- **One transform for display, drawing and export.** Show the image inside a fixed **frame**
  centred in the editing area: Original = the (rotated) image's aspect ratio, Square = 1:1, sized
  to fit the area. The image is panned/zoomed UNDER the frame exactly like
  `lib/features/profile/screens/crop_photo_screen.dart` (read its `cr:44-64` and `cr:133-164`
  pattern: min scale = the image covers the frame; it can never show empty space inside the frame).
  Dim outside the frame with `t.ink` at low alpha (no `Colors.`).
- **Rotate** bakes into the source: render the current `ui.Image` rotated 90° clockwise into a new
  `ui.Image` with `PictureRecorder` and swap it in; map every stored stroke point
  `(x, y) → (oldHeight − y, x)`; reset pan/zoom. The preview then always shows what is exported.
- **Draw**: while Draw is active, pan/zoom is off. Convert each touch point with the inverse of the
  display transform into **image pixels** and store strokes in image pixels. Stroke width = 4 logical
  px at the current fit, converted to image pixels (4 × imagePixelsPerLogicalPixel). Undo removes the
  last stroke, Clear removes all (both enabled only when there are strokes).
- **Export** (only when edited; unedited returns `file: null`, as Claude's fix already does):
  source rect = the frame mapped into image pixels; output = that rect at source resolution (never
  upscaled), strokes drawn in the same image-pixel space minus the rect origin. PNG bytes, as now.
- Tool switches are instant under reduced motion; the canvas stays in `ExcludeSemantics`; every
  button (Close, Crop, Draw, Original, Square, Rotate, Undo, Clear, the six colour buttons with
  names, Send) is reachable by TalkBack with a label.
- Keep the video Trim and GIF paths as they are, except: give the two trim handles their own
  semantics (**Trim start** m:ss / **Trim end** m:ss) instead of one container label.
- Put the pure maths (frame → source rect, touch → image px, rotate a point) in small top-level
  functions in the same file so the tests can call them without a widget.

## 2. The test gates the spec lists (round 1 has 5 tests; the spec needs these)

`docs/design/pages/media-send.md` → "Test gates (mandatory)". Implement every bullet for:

- `test/media/media_edit_screen_test.dart`: photo → Crop/Draw shown, video → Trim, GIF → no tools +
  the caption · Square crop of a 400×300 test image exports 300×300 (decode the exported PNG) ·
  rotate then export swaps sides (300×400 for Original) · a pan moves the exported rect · draw a
  stroke, Undo removes it, export pixels equal the no-stroke export · a stroke drawn at a known
  screen point lands at the expected image pixel (letterboxed image) · trim handles produce whole
  seconds, length ≤ 5:00, labels m:ss · close with edits → R20, Discard pops null; no edits → pops
  null without a dialog · Android back = Close · 360×640 at `textScaler 2.0` with the system font
  AND `PlusJakartaSans`: no overflow (`tester.takeException()` is null).
- `test/chat/media_bubble_states_test.dart`: per type (photo, video, voice, document), each own
  upload cell: uploading (disc, arc at 40%, semantics label via `tester.getSemantics`), waiting (no
  arc), failed (Try again; offline → disc at 38% once + **Available online**, not enabled, and no
  "Not sent · Try again" text) · tapping ✕ calls `cancelMediaUpload` (fake repo) and shows
  **Upload cancelled**; tapping ↻ calls `retryMessage` · failed download: **Tap to retry**
  invalidates (count fetches = 2) · expired / dead link / can't decrypt captions with no button,
  for photo AND voice (voice: no spinner, no retry) · own sent photo with a ready full blob → no
  download disc · reduced motion → no Hero · no `Text` coloured `t.accent` or `t.error` · 360×200%
  + Jakarta for each state. Override `mediaFileProvider`, `mediaFullLocalProvider`,
  `mediaBlobStatusProvider`, `isOnlineProvider`, `uploadProgressProvider`, `messageRepositoryProvider`.
- `test/services/media_format_test.dart`: GIF bytes (magic `GIF89a`, any file name) → same file
  back, no compressor call · animated WebP (VP8X with the animation flag, and one with an ANIM
  chunk) → as is · static WebP → `CompressFormat.webp`, `.webp` output · PNG → `CompressFormat.png`,
  `.png` · JPEG and HEIC → `CompressFormat.jpeg`, `.jpg` (fake compressor seam) · 101 MB → refused.
  For the size cap, move the check into one pure top-level function (e.g. `mediaTooBig(File)` in
  `media_upload_service.dart`, next to `compressImage`) that the composer calls, and test it with a
  sparse 101 MB temp file (`RandomAccessFile.truncate`), asserting no compressor call happens.

## Gates (same as round 1)

`flutter test` (all green), `flutter analyze` (0 errors), `git diff --check`. Append "E–H round 2,
Mimo" to the work log: files, tests added, suite total. Do not commit. Claude grades the result;
do not claim PASS.
