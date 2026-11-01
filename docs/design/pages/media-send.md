# Media send and bubble states: one bubble from pick to sent, honest states (acceptance checklist)

Date: 2026-10-31. Backlog **12.2 + 12.4**, taking in **13.7, 13.8** and the **Page 9 parked items** (offline
resend, upload cancel, download progress). Visual ground truth: **`docs/design/pages/media-send.html`** (sections
S1–S16, numbered; S1 = every media bubble state today vs this spec; S12 = trim engine options; S14 = parked items;
S15 = hooks for 12.5 / 12.1; S16 = diff summary). Authority: `docs/design/00-foundation.md` (tokens/laws) →
`docs/design/10-registry.md` (shared pieces) → this checklist. Page letters A–K are page-local; decisions are
numbered (bottom). Line refs as of `901065e`:
`ib` = `lib/features/chat/widgets/image_message_bubble.dart`, `vb` = `video_message_bubble.dart`, `vo` =
`voice_message_bubble.dart`, `db` = `document_message_bubble.dart` (same folder), `mb` = `message_bubble.dart`,
`mr` = `media_retry.dart`, `eb` = `expiry_badge.dart`, `mi` = `lib/features/chat/widgets/message_input.dart`,
`cp` = `lib/features/chat/providers/chat_provider.dart`, `mvp` = `lib/features/media/providers/media_viewer_providers.dart`,
`us` = `lib/services/media_upload_service.dart`, `rep` = `lib/infrastructure/repositories/message_repository_impl.dart`,
`bs` = `lib/infrastructure/media/media_blob_store.dart`, `bt` = `lib/data/local/database/tables/media_blob_table.dart`,
`cr` = `lib/features/profile/screens/crop_photo_screen.dart`.

**Starting point (audited 2026-10-31, `trail ask/skeleton/grep/callers` + `sed -n` ranges; no code run, no live
PocketBase read).** Suite baseline **752/752** at `901065e` (from the bug wave 3 commit; Mimo's 13.5/13.9/13.10
work lands on top, so phase 2 re-runs the baseline first and records it). Existing coverage to keep green unedited:
`test/chat/failed_media_placeholder_test.dart`, `test/media/media_download_state_test.dart`,
`test/media/media_retry_test.dart`, `test/offline/media_blob_store_test.dart`, `test/offline/media_stall_test.dart`,
`test/chat/send_failure_test.dart`, `test/grep_gates_test.dart`.

**Smells, confirmed in code (not assumed).**
1. **13.8 cause, confirmed.** `_uploadMediaMessage`'s `finally` deletes the compressed file and the thumbnail
   after every upload, success or not (`rep:1856-1866`). The sender's full copy is gone, so `mediaFullLocalProvider`
   (`mvp:29-37`) sees no ready row and the bubble draws the download disc (`ib:136-140`).
2. **13.7 cause, likely (path read in code, not reproduced).** The optimistic row has no server id until the
   upload finishes (`rep:1666-1680`, stamped at Step D `rep:1822-1838`). The message record is created on the
   server *before* the media upload (Step B, `rep:1738-1752`). SSE skips own messages (`rep:471`), but any
   page fetch in that window (`_cacheMessagesBatch` ← `_fetchAndCacheMessages` ← `_messagesStream` /
   `_startPollFallback` / `_backfillTargets`) finds no local row by server id (`rep:4070-4095`) and inserts the
   server row under a fresh uuid. Two bubbles: the skeleton placeholder (`mb:295-313`) and an image bubble that
   waits for a media record. Step D's `deleteByServerIdExcept` (`rep:1822`) removes the second one when the
   upload ends. That matches "the first disappears only once the upload finishes". Device check 1 proves it.
3. **A failed or offline upload can never be retried.** Offline, Step B throws → `status = 'failed'`
   (`rep:1851-1853`), and the `finally` deletes the files. No retry exists anywhere. Photo/video placeholders keep
   shimmering when failed (`mb:406-445`, `_OptimisticMediaPlaceholder` ignores `status` for image/video); voice
   and documents show a static "… not sent" row. An upload that fails *after* Step B leaves a message record on
   the server with no media: receivers wait, then see "No longer available" after a day (store's one-day rule).
4. **Cancel works only while compressing.** `_cancelUpload` (`mi:537-548`) bumps a generation counter that is
   checked between compress steps (`mi:404-443`, `mi:467-532`). Once `send()` is called the upload runs
   unawaited in the repo (`rep:1683-1698`) and nothing can stop it.
5. **No upload progress source.** `uploadImage`/`uploadVideo` read the whole file, encrypt it in memory and hand
   PocketBase `MultipartFile.fromBytes` (`us:166-213`). The SDK (`pocketbase 0.21.0`) exposes no progress
   callback. Video *compression* progress exists (`VideoCompress.compressProgress$`, `mi:475-479`) and is shown in
   the composer's floating row.
6. **Every photo becomes a JPEG.** `compressImage` always writes `CompressFormat.jpeg` (`us:118-137`): a GIF
   loses its animation, a PNG its transparency. (EXIF/GPS is dropped by the re-encode, keepExif false; see the
   photo learning.) Thumbnails are already **640px / 70%** (`us:139-157`): **12.4's thumbnail item is done.**
7. **The size cap is not enforced.** `AppConstants.maxFileSizeMb = 100` has no caller in `lib/`. A file over the
   server's limit fails only after compress + encrypt + upload.
8. **Can't decrypt reads as "No longer available".** `MediaRetry` folds `cantDecrypt` into the expired caption
   (`mr:39-48`). The viewer (Page 9) and the message label (`mb:68-72`) say **Can't decrypt**. The voice bubble
   has no ended state at all: a blob the store marked failed shows the red error icon and a **Tap to retry** that
   can never work (`vo:95-125`, `vo:193-230`; the store returns null for `failed` without trying, `bs:146`).
9. **A cache hit loses the media's metadata (found here, confirmed in code; device not checked).** For a `ready`
   row, `requestBlob` runs the pipeline, whose fast path returns `LocalMediaFile(file, fileName: basename)` only
   (`bs:192-207`): no width/height, no `expiresAt`, no mime type, and the file name keeps its `<id>_f_` prefix.
   `mediaFileProvider` is per session, so **after every app restart** a cached photo/video bubble falls back to
   4:3 / 16:9 (`ib:42`, `vb:41`), loses its expiry badge, the viewer loses its expiry line, and a document shows
   `abc123_f_report.pdf`. **This is also backlog 13.4** (video bubble shows 0:00): the video bubble reads
   `durationSeconds` from the thumbnail load (`vb`, `media?.durationSeconds ?? 0`), the record path fills it, the
   fast path leaves it null. Live read R1 confirms the server has it (video 2/2 and voice 4/4 with
   `duration_seconds` > 0), so 13.4 is client-side. Registering the sender's file as a ready blob (13.8) would make
   the sender hit this on every send, so this page has to fix it (decision 3).
10. **"Deleted" needs no bubble state.** `watchMessages` filters `isDeletedForEveryone` and `isDeletedForMe`
    (`messages_dao.dart:18-23`): a deleted message leaves the chat. The deleted look matters only in reply quotes
    (13.10, Mimo) and Media & docs (not this page).
11. **A dormant upload latch exists.** `media_blob.upload_pending` (`bt:58-61`) protects a blob from eviction
    (`bs:496-501`) but nothing sets it. It was designed for exactly this (offline-first spec §5.3, "a blob whose
    only copy feeds a pending upload").

**Routing.** Spec: Claude (this session). Phase 2: the send path and blob store changes (B, C) are race/lifecycle
work, so **Claude implements B–C**; the editor screen and bubble visuals (D–H) are spec-able and can go to
**Astra** (Omnirush back after 2026-11-02 17:30 IST) or Mimo, with Claude grading. The grading pass is a
fresh-context reviewer, never the implementer.

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test` green
(baseline re-run at phase 2 start, plus the new tests, no existing test edited to pass) · test-gate files below
green · `git diff --check` clean · K1 grep gate green (proved RED once) · `trail check` clean · frozen-method diff
vs HEAD empty · drift migration test green · fresh-context review with no open BLOCK, findings in
`media-send-work-log.md` · device captures of the device-check list · user device PASS (no commit without it).

**Spec status: user PASS 2026-10-31; every deferred decision = its default (1–24).** `pro_image_editor`
(decision 15 alternative B) is parked in `docs/backlog.md` §12 in case the built-in crop doesn't feel good enough.

**Live PocketBase reads.** R1 done 2026-10-31 (read-only, user approved, by the Page 9 session):
`message_media.file` maxSize **104857600 = 100 MB** (decision 13's phone cap matches the server); `thumbnail`
maxSize 0 = PocketBase's default; `duration_seconds` exists (number, optional), video 2/2 and voice 4/4 > 0,
image/document 0. No further read is needed; ask before any. Everything else is already proven
by shipped code: client-supplied record ids on `messages` (text sends use the op id as the record id, `rep:1590-1612`),
the sender setting `is_deleted_for_everyone` (`deleteMessage`, `rep:2198-2205`).

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence; `[ ]` pending.

---

## ⛔ Frozen (read first: a breach here is an automatic FAIL)

**Still frozen:** E2E and key code anywhere: `encryption.*`, `_encryptFileBytes` (`us:65-71`), `_getConvKey`, the
store's download → verify → decrypt section (`bs:209-345`), `_lookupRecord`, the stall bound, the store's failure
classes and one-day rule, `mediaFileProvider`'s wait/retry shape (`cp:66-100`), receipts, ingest/decrypt passes
(`_cacheMessagesBatch`, `_companionFromRecord`, SSE handler), the outbox worker, the viewer (Page 9, and Mimo's
13.5/13.9 edits), `reply_quote.dart` (Mimo, 13.10), the quality sheet's content (Page 8), the voice recorder.

**Unfrozen by this page, and only these (decision 2):**
- `rep` `sendMediaMessage` + `_uploadMediaMessage` (+ new private helpers they call): the pre-assigned id, kept
  files, the create-ack stamp, resume, cancel, progress. Every encrypt/key call inside stays byte-identical.
- `bs`: one new method `registerLocal(...)` and the fast path returning stored metadata. `requestBlob`'s
  terminal/coalesce rules, the download section and eviction are untouched.
- `bt` + `media_blob_dao.dart`: one new nullable column (`meta`, decision 3) + schema v12 migration.
- `us`: `compressImage` format choice (decision 11) and the upload calls taking a progress-counting stream
  (decision 5). Encryption, record bodies and retention stay byte-identical.

When an edited file holds frozen code (`rep`, `bs`, `us`, `mb`, `mi`), every other method in it is diffed against
HEAD **at function level** and must be byte-identical. No timeout is ever wrapped around key resolution, encryption
or decrypt; a network bound covers the network call only. Read for context, do not re-solve:

- `.trail/learnings/2026-10-30-a-media-upload-that-fails-stays-chaitanya.md` (failed upload stays on the placeholder)
- `.trail/learnings/2026-10-31-expired-media-is-told-apart-from-chaitanya.md` (expired vs not-uploaded by age)
- `.trail/learnings/2026-10-30-a-media-bubble-claims-not-downloaded-chaitanya.md` (disc only on a positive answer)
- `.trail/learnings/2026-10-30-a-send-that-fails-gives-the-chaitanya.md` (rejections restore input, no failed row)
- `.trail/learnings/2026-10-29-choosing-high-quality-for-a-photo-chaitanya.md` (High halves retention; re-encode strips GPS)
- `.trail/learnings/2026-10-29-a-media-download-that-failed-stays-chaitanya.md` (retry invalidates first)
- `.trail/learnings/2026-10-31-reading-an-auto-disposed-provider-s-chaitanya.md` (never await an autoDispose future without a listener)
- `.trail/learnings/2026-10-31-a-screen-never-uses-ref-in-chaitanya.md` (no `ref` in dispose)

## A. States matrix (S1)

- [ ] **A1 MUST** Every cell of S1's matrix (photo, video, voice, document × loading, uploading, waiting for
  connection, failed upload, failed download, offline, expired, can't decrypt, no longer available, not
  downloaded) renders as drawn, in light, dark and AMOLED. "Deleted" has no cell (smell 10).
- [ ] **A2 MUST** One rule per state, shared by the four bubbles: the caption strings live in one place
  (`message_offline_policy.dart` holds `kOfflineActionHint`; new strings next to it), never inlined twice.

## B. One bubble from send to sent (13.7; S5; decisions 1, 20)

- [ ] **B1 MUST** `sendMediaMessage` uses `generateOpId()` (`lib/core/utils/op_id.dart`) as the row's `localId`
  and creates the server message with `'id': localId`. Text sends already do this.
- [ ] **B2 MUST** Before the row is inserted, the compressed file and thumbnail are registered as **ready** blobs
  `mediaBlobId(localId, thumb: false/true)` with `uploadPending: true` and their metadata (B/C, decision 3). The
  message row and the blob rows are written in **one drift transaction**; if it throws, the moved files are
  deleted and the composer's existing error toast shows (send-failure learning: no failed row).
- [ ] **B3 MUST** The chat draws the **media bubble itself** from the first frame: for own rows `mb` passes
  `message.serverId ?? message.localId` as the media id when the `localId` is a record id (15 chars `[a-z0-9]`).
  The bubble finds its local thumbnail through the ready blob, so no skeleton, no placeholder swap, the Hero tag
  never changes. `_OptimisticMediaPlaceholder` stays only for **legacy rows** (uuid `localId`, from before this
  update): they show the static failed look (decision 22).
- [ ] **B4 MUST** When the message create acks (Step B), the row is stamped at once with `serverId = localId` and
  the **server's** `created` (never device time: the watermark rule, `rep:1754-1762`), status stays `pending`,
  and `deleteByServerIdExcept` runs. Step D then writes `mediaId` + `sent` and clears `uploadPending`.
- [ ] **B5 MUST** A page fetch during the upload leaves exactly **one** row (test: run `_cacheMessagesBatch`
  between Step B and Step D with the server record in the page).
- [ ] **B6 MUST** Same for all four types (decision 20): photo, video, voice note, document.

## C. The sender keeps the file (13.8; S6; decisions 2, 3)

- [ ] **C1 MUST** The `finally` in `_uploadMediaMessage` no longer deletes the compressed file or thumbnail
  (they now live in the store's `media_clear` dir, moved there by `registerLocal`). Composer temp files that are
  not the sent file (the picked original) are still cleaned.
- [ ] **C2 MUST** `MediaBlobStore.registerLocal({blobId, file, meta, uploadPending})`: moves `file` to
  `media_clear/<id>_<f|t>_<name>`, inserts/updates the row as `ready` with `bytes`, `localPath`, `meta`,
  `lastAccess`. Epoch-gated like every store write (`_stillValid`). No network.
- [ ] **C3 MUST (decision 3)** `media_blob` gains one nullable `meta` text column (JSON: `width`, `height`,
  `durationSeconds`, `expiresAt`, `mimeType`, `fileName`), schema **v12**, migration = one `addColumn`. The
  pipeline's ready write stores it from the record; the fast path returns it. Old rows (null `meta`) behave as
  today. **This fixes backlog 13.4** (video length 0:00 after the blob is ready): a video bubble's length survives
  a reopen and a restart.
- [ ] **C4 MUST** Own sent photo/video: no download disc, ever (the full file is ready). The viewer opens the
  full file with no network. Eviction may later drop it like any other unprotected blob; then the disc returns
  honestly.
- [ ] **C5 MUST** Logout wipes registered files with the rest of `media_clear` (existing wipe; test it covers a
  registered file).

## D. Upload progress, cancel, resend (S2, S7; decisions 4–7)

- [ ] **D1 MUST (decision 5)** Upload progress = bytes pulled from a counting stream fed to
  `MultipartFile.fromStream` (encrypted bytes, chunked), summed over file + thumbnail. Exposed per `localId`
  through a small in-memory `uploadProgressProvider` (family, autoDispose, stream). Bound: none on the progress
  itself; the upload request gets the same **8s stall bound** as downloads (no bytes pulled for 8s → transient
  failure → pending, resumes). Key/encrypt work is never inside the bound.
- [ ] **D2 MUST** The uploading bubble shows the local photo/video poster at full opacity with **`MediaUploadDisc`**
  (new, C15): a 44px disc, progress arc (accent), ✕ inside. Voice/doc: the same disc in the play/file-icon slot.
  Semantics: button, label **"Photo, sending, 40 percent. Cancel"** (Video/Voice message/Document).
- [ ] **D3 MUST (decision 6)** Tap ✕ → upload stops (the counting stream errors), the row + its blob rows +
  files are removed, toast **Upload cancelled** (R5, existing copy). If the server message already exists, it is
  marked `is_deleted_for_everyone: true` (best effort, the existing update path), so receivers never see an empty
  bubble. Offline cancel works (local only; the server mark retries on the next resume).
- [ ] **D4 MUST (decision 4)** **Resume:** on app start and on every offline→online flip, own media rows with
  `status` `pending` whose blobs have `uploadPending` are re-run, one at a time, oldest first. Re-run is
  idempotent: Step B create with the same id → duplicate → ownership check (reuse the text path's check) =
  success; Step C first looks the media record up (`message_id` filter) and skips the upload if it exists.
- [ ] **D5 MUST** Failure classes: offline / stall / 5xx / 429 → stays **`pending`** ("Waiting for connection"
  look, resumes by itself). 4xx other than 429 (too large, not a member, validation) → **`failed`** (terminal look
  + **Try again**). Try again = one re-run; offline it is dimmed once (38%) with **Available online** outside the
  dim; nothing else dims.
- [ ] **D6 MUST** The compress phase stays in the composer's floating row (decision 7), with its existing cancel;
  the bubble appears after compression. The composer's raw `LinearProgressIndicator` rows are out of scope.
- [ ] **D7 MUST** No `ref` in any `dispose()`; the progress provider is listened to with `ref.watch` in build, never
  awaited (`await ref.read(autoDispose.future)` is banned without `listenManual`).

## E. Received media states (12.2; S2–S4; decisions 9, 10)

- [ ] **E1 MUST** Loading: R11 `Skeleton.fill` in the media slot (photo/video), the existing doc shimmer, the voice
  disc's R3a. Unchanged.
- [ ] **E2 MUST** Failed download: `MediaRetry` as today (**Tap to retry**, invalidates first); offline: icon 38% +
  **Available online**. Unchanged.
- [ ] **E3 MUST (decision 9)** Ended states get their own caption: store `expired` or age past retention →
  **Media expired** (existing `ExpiredPlaceholder`); `dead_link` → **No longer available**; `decrypt`/`verify` →
  **Can't decrypt** with `Icons.lock_outline`. `mediaBlobStatusProvider` gains a `deadLink` value (read-only, same
  row read). No retry on any of the three.
- [ ] **E4 MUST (decision 10)** The voice bubble reads `mediaBlobStatusProvider`: an ended blob shows the inline
  ended row (same three captions, inline variant), no spinner, no retry.
- [ ] **E5 MUST** Not downloaded: Page 9's disc, photo/video only. Voice and documents still auto-load on display
  (unchanged).
- [ ] **E6 MUST** Expired caption grows from 10.5px to **12px** in the photo/video slot (matches `MediaRetry`'s
  12px caption; decision 23).

## F. Send flow and the editor screen (12.4; S7–S10; decisions 14–19)

- [ ] **F1 MUST (decision 14)** After a photo/video is picked: **`MediaEditScreen`** (new, C14) opens on the file
  (input = `File` + type, nothing picker-specific, so 12.1 can open it). Top: Close (✕). Bottom: tool row
  (photo: **Crop**, **Draw**; video: **Trim**; GIF/animated WebP: no tools, caption **GIFs are sent as they
  are.**) + **Send** (R3 primary). Send → the existing quality sheet (unchanged) → send. GIF skips the quality
  sheet (decision 12).
- [ ] **F2 MUST** Close with edits → R20 **Discard changes?** / **Your crop and drawing will be lost.** /
  **Discard** (destructive). Close with no edits → just closes. Android back = Close.
- [ ] **F3 MUST (decision 15)** Crop = the avatar cropper's pan/zoom-under-a-frame pattern (`cr:44-64`, `cr:133-164`)
  generalised to a rectangular frame: **Original** and **Square** frames, **Rotate** (90° steps). Export through
  `PictureRecorder` at source resolution (no upscaling), then the normal compressor (strips EXIF).
- [ ] **F4 MUST (decision 16)** Draw = freehand pen over the photo: one width (4dp at fit, scaled to source
  pixels), six fixed colours (S9), **Undo**, **Clear**. Strokes burn into the export. No text, stickers or filters.
- [ ] **F5 MUST (decisions 17, 18)** Trim = a `RangeSlider` (whole seconds) under a `video_player` preview, start /
  end / length labels (tabular figures), length capped at 5:00 (the picker's existing cap). The trimmed range goes
  to the compressor in the same pass (decision 17's engine). The thumbnail is taken at the trim start.
- [ ] **F6 MUST (decision 11)** Format: GIF and animated WebP are sent **as is** (no re-encode, no quality choice);
  PNG → PNG re-encode; static WebP → WebP re-encode; JPEG / HEIC / anything else → JPEG (today's path). Every
  re-encode drops EXIF/GPS. The file extension and `mime_type` match the bytes sent. Thumbnails stay 640px/70% JPEG.
- [ ] **F7 MUST (decision 13)** Before compress: a file over `maxFileSizeMb` (100) is refused with **Too big to
  send. The limit is 100 MB.** (R5 error toast); after compress the size is checked again.

## G. Motion, a11y, large text

- [ ] **G1 MUST** Reduced motion: the progress arc jumps (no sweep animation), R11 parks, no Hero, editor tool
  switches are instant.
- [ ] **G2 MUST** 360×640 at `textScaler 2.0`, system font and Plus Jakarta Sans: every bubble state and the editor
  fit with no overflow (captions `FittedBox.scaleDown` in fixed media slots, as `MediaRetry` does).
- [ ] **G3 MUST** TalkBack: the upload disc, Try again, Crop/Draw/Trim/Send/Close, Rotate, Undo, Clear, the trim
  handles (**Trim start**, **Trim end**, value in m:ss) are announced. Draw is skipped by TalkBack users: the
  canvas is `ExcludeSemantics` with the tools still reachable.

## H. Copy (verbatim)

`Upload cancelled` (existing) · `Not sent` · `Try again` · `Waiting for connection` · `Available online`
(existing `kOfflineActionHint`) · `Media expired` (existing) · `No longer available` (existing) · `Can't decrypt` ·
`Tap to retry` (existing) · `Too big to send. The limit is 100 MB.` · `GIFs are sent as they are.` · `Crop` ·
`Draw` · `Trim` · `Send` · `Rotate` · `Original` · `Square` · `Undo` · `Clear` · `Discard changes?` ·
`Your crop and drawing will be lost.` · `Discard` · `Couldn't open that video.` (editor load failure, R5 error,
pops) · `Couldn't use that photo.` (existing cropper copy, reused). No `$e` in any of it.

## K. Hygiene and gates

- [ ] **K1 MUST** NEW grep test **inside `main()`** of `test/grep_gates_test.dart`, "media send": in the new files
  (`media_edit_screen.dart`, `media_upload_disc.dart`, the progress provider file), none of `Colors.` (except the
  draw palette's one `const` list, exempted by line content), `Color(0x` outside that list, `LinearGradient`,
  `SnackBar(`, `CircularProgressIndicator`, `LinearProgressIndicator`, `showModalBottomSheet`, `$e`/`e.toString()`
  outside `debugPrint`; in `rep`, no `mediaFile.delete()`; in `lib/`, no `ffmpeg`. Prove RED once, then GREEN.
- [ ] **K2 MUST** Registry C14 + C15 added, `MediaRetry` row amended (below), same commit.

## Registry amendments (same commit, L2)

| ID | Amendment |
|---|---|
| C14 | `MediaEditScreen(file, type)` → `Future<MediaEditResult?>`: the ONE pre-send screen for a picked photo/video (Crop with Original/Square/Rotate, Draw with 6 colours/Undo/Clear, Trim with a whole-second range). Input is a file, not a picker, so share-in (12.1) can open it. GIF/animated WebP: no tools. |
| C15 | `MediaUploadDisc(progress?, onCancel?, onRetry?, enabled)`: the 44px disc on an own media bubble while sending (arc + ✕), waiting (✕, no arc), failed (↻ Try again). Reduced motion: no sweep. |
| (amend) | `MediaRetry`: three ended captions (**Media expired** / **No longer available** / **Can't decrypt**), no retry on any; the voice bubble uses the same rule inline. |

## Test gates (mandatory)

Bubble tests override `mediaFileProvider`, `mediaFullLocalProvider`, `mediaBlobStatusProvider`, `isOnlineProvider`
and the new `uploadProgressProvider`; repo/store tests use the in-memory drift database and the store's injected
`cacheDir` + `httpClient` (existing seams), and a fake PocketBase client for creates. Semantics via
`tester.getSemantics`. Large text = 360×640, `textScaler 2.0`, system font and `PlusJakartaSans`.

- [ ] NEW `test/offline/media_send_one_bubble_test.dart`: send inserts ONE row whose `localId` is a 15-char id, and
  two ready blobs with `uploadPending` · the create body carries `'id': localId` · create ack stamps `serverId` and
  the server `created` (not device time) · a `_cacheMessagesBatch` page holding the server record mid-upload leaves
  one row · Step D writes `mediaId` + `sent` and clears `uploadPending` · the compressed file still exists after
  success (13.8) · insert transaction throw → no row, no blob row, files deleted.
- [ ] NEW `test/offline/media_send_resume_test.dart`: offline at Step B → row `pending`, files kept · reconnect →
  re-run, one row, `sent` · duplicate-id on re-create → ownership check → success, not failed · media record found
  on re-run → no second upload (count uploads) · 413 → `failed` · stall (no bytes pulled 8s, fake clock) →
  `pending` · two pending rows resume oldest first, one at a time · cancel mid-upload → row and blobs gone, server
  mark called once · cancel offline → local gone, mark queued for the next resume.
- [ ] NEW `test/offline/media_blob_meta_test.dart`: schema v11 → v12 migration keeps rows, `meta` null · ready write
  stores meta · fast path returns width/height/durationSeconds/expiresAt/mimeType/fileName (no `_f_` prefix) ·
  a video bubble over a ready thumb row with stored meta shows its length, not 0:00 (13.4) · `registerLocal` moves
  the file under `media_clear`, epoch-gated (bumped epoch → no row) · logout wipe deletes a registered file.
- [ ] NEW `test/chat/media_bubble_states_test.dart`: per type, each S1 cell: uploading (disc, arc at 40%, semantics
  label), waiting (no arc), failed (Try again; offline → 38% once + **Available online**, not enabled), failed
  download (Tap to retry invalidates: count fetches = 2), expired / dead link / can't decrypt captions with no
  button, own sent photo with a ready blob → no disc · voice ended → no spinner, no retry · reduced motion → no
  arc animation, no Hero · no `Text` coloured `t.accent`/`t.error` · 360×200% + Jakarta for each state.
- [ ] NEW `test/media/media_edit_screen_test.dart`: photo → Crop/Draw shown, video → Trim, GIF → no tools + caption
  · Square crop of a 400×300 test image exports 300×300 · rotate then export swaps sides · draw a stroke, Undo
  removes it, export pixels unchanged · trim handles produce whole seconds, length ≤ 5:00, labels m:ss · close
  with edits → R20, Discard pops null; no edits → pops null without dialog · 360×200% + Jakarta.
- [ ] NEW `test/services/media_format_test.dart`: GIF bytes → sent as is (same bytes, `.gif`, `image/gif`), animated
  WebP (VP8X + ANIM) → as is, static WebP → `CompressFormat.webp`, PNG → `CompressFormat.png`, JPEG/HEIC →
  `CompressFormat.jpeg` (fake the compressor seam) · 101 MB → refused with the copy, no compress call.
- [ ] `test/grep_gates_test.dart`: K1 inside `main()`; RED once, then GREEN, both in the work log.
- [ ] Existing tests stay green **unedited** (list at the top). `failed_media_placeholder_test.dart` keeps passing
  because legacy rows keep the placeholder.
- [ ] Count: the work log records **baseline + N = total**.
- [ ] Function-level diff vs HEAD of every frozen method in an edited file: empty.
- [ ] Full suite green · analyze 0 errors · `git diff --check` clean · `trail check` clean · `build_runner` output
  committed with the v12 table change.

## Device check list (phase 2, M52 + Redmi S2; you do every send)

1. **13.7 repro first (before the fix):** send a large photo on a slow link (Developer options → network throttle or
   a weak spot) and pull to refresh / reopen the chat mid-upload → two bubbles. After the fix: one bubble, always.
2. Send a photo: the bubble shows your photo at once with the ring filling, then the ring goes and the tick turns
   to sent. No skeleton, no swap, no jump in size.
3. Your sent photo has no download disc; open it → the viewer shows it sharp at once, in airplane mode too.
4. Kill the app mid-upload, reopen → the upload continues by itself and finishes.
5. Airplane mode, send a photo, a voice note and a document → each shows "Waiting for connection" with ✕; turn the
   network on → they send in order, on their own.
6. Tap ✕ mid-upload → **Upload cancelled**, bubble gone; the other phone shows nothing (or nothing lasting).
7. Send a GIF from the gallery → no tools, no quality sheet, it animates in your bubble and on the other phone.
8. Send a PNG with transparency → transparency kept on the other phone. Send a camera photo → Save it on the other
   phone → no location in its details.
9. Crop a photo to Square, rotate once, send → the other phone gets exactly that framing. Portrait camera photo:
   the editor shows it upright.
10. Draw on a photo with two colours, Undo once, send → the remaining stroke is burned in.
11. Trim a 40s video to 0:05–0:15, send → the other phone plays 10s, starting at 0:05; its poster is the 0:05
    frame. (Proves decision 17's end-trim conversion.)
12. Restart the app → old photos keep their real shape and expiry badge; a document shows its real name; a video
    bubble shows its real length, not 0:00, after reopening the chat and after a restart. (Smell 9, 13.4.)
13. A photo whose key is gone (an old group message after a key loss, if you have one) → **Can't decrypt**, no
    retry; an expired one → **Media expired**; a voice note in either state → no spinner, no retry.
14. Largest text + Plus Jakarta Sans, 360dp if available: every state above and the editor fit.
15. Reduce animations: no ring sweep, no Hero; TalkBack reads the disc, Try again and the editor tools.
16. A file over 100 MB (a long 4K video from the gallery) → **Too big to send. The limit is 100 MB.**, nothing
    uploads.

## Out of scope (do NOT build on this page)

Everything still in ⛔ · albums (12.5) and share-in (12.1), beyond the hooks in S15 · the composer's own compress rows and raw `LinearProgressIndicator` · captions ·
filters, text, stickers · multi-pick · download progress (decision 8) · Media & docs · the outbox `media_upload`
kind (decision 4 alternative) · mascots.

---

## Diff vs current implementation

| # | Area | Today (file:line) | Spec | Checklist |
|---|---|---|---|---|
| 1 | Bubbles while sending | skeleton placeholder + a second "real" bubble after a page fetch (`mb:295-313`, `rep:4070-4095`) | one media bubble from frame one, same id and Hero tag | B1–B5 |
| 2 | Sender's full copy | deleted after upload (`rep:1856-1866`); disc on own photos | moved to `media_clear` as a ready blob; no disc | C1–C4 |
| 3 | Metadata on a cache hit | dropped (`bs:192-207`): 4:3 after restart, no expiry, prefixed doc names, video length 0:00 (13.4) | stored in `meta`, returned by the fast path | C3 |
| 4 | Offline / failed upload | `failed`, files deleted, never retried (`rep:1851-1866`); photo/video shimmer forever | `pending` + auto-resume (start, reconnect); terminal `failed` + Try again | D4, D5 |
| 5 | Upload progress | none (`MultipartFile.fromBytes`, `us:207-210`) | counting stream → arc on the bubble | D1, D2 |
| 6 | Cancel | only while compressing (`mi:537-548`) | ✕ on the bubble until sent; server mark if the message exists | D3 |
| 7 | Upload stall | no bound | 8s silence bound on the upload request only | D1 |
| 8 | Can't decrypt | "No longer available" (`mr:39-48`); voice: retry that can't work (`vo:193-230`) | **Can't decrypt**, no retry; voice gets ended states | E3, E4 |
| 9 | Expired caption | 10.5px | 12px | E6 |
| 10 | Pre-send | quality sheet only | `MediaEditScreen` (crop/draw/trim) → quality sheet | F1–F5 |
| 11 | Formats | everything → JPEG (`us:118-137`) | GIF/animated WebP as is; PNG→PNG; WebP→WebP; rest→JPEG | F6 |
| 12 | Size cap | `maxFileSizeMb` unused | checked before and after compress | F7 |
| 13 | Thumbnails | 640px / 70% (done after Page 9) | unchanged; video thumb at trim start | F5 |
| 14 | Legacy pending rows | placeholder | placeholder, static failed look | B3 |

---

### Deferred decisions (you decide at spec review; default = recommended)

1. **One bubble via a pre-assigned id** (B): the row's `localId` is a PocketBase-style id used as the server record
   id, the sent file is a ready blob from the first frame, and the server id is stamped at the message-create ack.
   Fixes 13.7 at the root and makes resend and cancel safe (a re-run converges on the same record).
   Alternative: a narrow fix: skip own media records in the page fetch while a local in-flight row exists, keep the
   placeholder, and register the file only after the upload (13.8 alone). Smaller, but the skeleton → photo swap and
   the no-retry problem stay.
2. **Unfreeze the media send path and the blob store, narrowly** (⛔ "Unfrozen" list). Risk: these have been frozen
   since the offline-first work; a mistake can lose a send or leave a stale ready row. Containment: E2E/key code
   byte-identical (function-level diff), the store's download/decrypt section untouched, Claude implements B–D, one
   fresh-context review, the device list items 1–6. Alternative: keep them frozen and do only the bubble visuals
   (12.2) + the editor (12.4); 13.7, 13.8 and resend stay open.
3. **The blob row remembers metadata** (one nullable JSON column, schema v12). Required by decision 1 (else every own
   photo is 4:3 with no expiry badge) and fixes smell 9 for everyone. Alternative: the bubble decodes width/height
   from the file when missing (photo/video only); restart still loses expiry badges and document names.
4. **Resume automatically** on app start and on reconnect, oldest first, one at a time; Try again only for terminal
   failures. Alternative A: manual Try again only. Alternative B: the outbox `media_upload` kind the offline-first spec
   planned (§5.2): keeps strict order with text sends, but it is a larger change to the frozen outbox. With the
   default, a text sent after an offline photo can arrive first.
5. **Determinate progress** from a counting stream on the upload. Alternative: an indeterminate ring (no change to
   the upload calls).
6. **Cancel on the bubble until it is sent**; a message already on the server is marked deleted for everyone so the
   other side never keeps an empty bubble. No confirm dialog (the original is still in your gallery). Alternative:
   no cancel after compression.
7. **The compress phase stays in the composer's floating row** (it has progress and cancel today); the bubble appears
   when compression ends. Alternative: the bubble appears at pick time and shows compression too (moves compression
   into the repo, more change).
8. **Download progress (Chat J8) deferred.** The store reads the body as one stream (`bs:271-277`); a progress source
   is possible but every download today is a thumbnail or a viewer load with R3a. Alternative: a ring in the viewer.
9. **Three ended captions**: Media expired / No longer available / Can't decrypt (lock glyph). Alternative: keep one
   "No longer available" for all.
10. **The voice bubble gets the ended states** (no spinner, no retry when the store marked it failed). Alternative:
    leave voice as is.
11. **Format rules:** GIF and animated WebP as is; PNG and static WebP re-encoded in their own format; JPEG/HEIC and
    the rest re-encoded to JPEG. Every re-encode drops EXIF/GPS (PNG and WebP can carry EXIF too, so "as is" for them
    would leak location). Alternative: PNG and WebP also as is.
12. **GIFs skip the quality sheet and the tools**, and are kept for the Normal photo retention (60 days). Alternative:
    ask the quality anyway (it would change only retention, not the file).
13. **Refuse files over 100 MB on the phone**, before any work. Live read R1 confirmed the server's `file` cap is
    exactly 100 MB, so the copy's number is right. Alternative: no client check (the upload then fails at the server
    after compress + encrypt).
14. **The editor always opens after a pick** (you see what you send; one extra tap: pick → editor → Send → quality
    sheet). Alternative: no editor by default; an **Edit** row inside the quality sheet opens it.
15. **Crop = the avatar cropper's pan/zoom under a frame**, frames Original and Square, Rotate in 90° steps, no new
    dependency. Alternative A: `image_cropper` (native uCrop screen: free handles, but off-brand, a new Android
    activity, crop only). Alternative B: `pro_image_editor` (crop + draw in one package, large dependency, needs its
    filters/text/stickers turned off).
16. **Draw = one pen width, six fixed colours, Undo, Clear.** Alternative: also a highlighter width.
17. **Trim engine: the `video_compress` already installed** (3.1.4: `compressVideo(startTime:, duration:)`, whole
    seconds, trimmed in the same pass as compression, no new dependency). Watch out: on Android it passes `duration`
    to Transcoder 0.10.5's `TrimDataSource(source, trimStartUs, trimEndUs)`, whose last argument is *time cut off the
    end*, not a length; phase 2 wraps the call as `duration = videoLength − end` and device check 11 proves it. The
    package has had no release since Feb 2025 (per a fork's README), but it is already our compressor, so trim adds
    no new risk. Alternatives (S12): **B** `flutter_native_video_trimmer` (Media3 / AVFoundation, ms precision) for
    trim + keep `video_compress` (one more dependency, two passes); **C** swap to `video_compressor_plus` (a maintained
    fork that also trims; a compressor swap touches every video send); **D** an FFmpeg community fork
    (`ffmpeg_kit_flutter_minimal` / `_new`): FFmpegKit was retired in 2025, forks are community-maintained, binaries
    add tens of MB and bring LGPL/GPL terms. Not recommended.
18. **Trim UI = a range slider with times**, no filmstrip. Alternative: an 8-frame filmstrip behind the slider (frames
    from `VideoCompress.getByteThumbnail` at 8 positions; slower to open).
19. **Video thumbnail at the trim start** (taken from the original before compression, as today). Alternative: the
    middle of the trimmed range.
20. **All four types use the one-bubble path** (voice notes and documents resend and cancel too; offline voice notes
    are the most common offline media). Alternative: photos and videos only; voice/doc keep the placeholder.
21. **The uploading look keeps the photo at full opacity** with the disc; "waiting" adds no dim (nothing is disabled:
    ✕ still works offline). Alternative: dim the photo while sending.
22. **Legacy pending/failed media rows** (sent before this update; their files are gone) show the static **Not sent**
    look with no Try again (long-press Delete as today). Alternative: hide them.
23. **Expired caption 12px** in the photo/video slot (10.5px today). Alternative: keep 10.5px.
24. **Hooks only for 12.5 / 12.1** (S15): `MediaEditScreen` takes a file, not a picker; `sendMediaMessage` stays
    one-file-per-call with its pre-assigned id, so an album can later send N items with a shared batch id. No album or
    share-in code here. Alternative: none.
