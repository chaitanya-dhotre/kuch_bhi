# Media send: phase 2 work log

Spec: `docs/design/pages/media-send.md` (user PASS 2026-10-31, decisions 1–24 at default). Visual: `media-send.html`.

## Baseline

- 2026-10-31, HEAD `fb2fd2c`, working tree: only `docs/backlog.md` modified (no Mimo 13.5/13.9/13.10 edits present).
- `flutter test`: **753/753** green.

## Progress

### B, C, D (send path + blob store), Claude, 2026-10-31

- B1 `generateOpId()` localId = server record id (`'id': localId` in the create); B2 files moved by
  `MediaBlobStore.registerLocal` as ready blobs with `uploadPending`, message row + blob rows in one
  drift txn, rollback deletes moved files and rethrows (composer toast); B3 `mb` passes
  `serverId ?? localId` (own, `isOpId`) so the media bubble draws from frame one; B4 create ack stamps
  `serverId = localId`, the server `created`, the body stub, runs `deleteByServerIdExcept` and
  `liftQueuedSends` (new, all types; the text path keeps `liftQueuedTextSends` byte-identical).
- C1 no file deletes after upload; C2 `registerLocal` (epoch/auth gated at entry and before the row
  write; falls back to the system temp dir only when path_provider is missing = unit tests);
  C3 `meta` JSON column, schema v12 (one guarded `addColumn`), the pipeline's ready write stores it,
  the fast path returns it (null meta = old behaviour).
- D1 `UploadTicket` (lib/services/upload_progress.dart): counted 128 KB chunks, 8s stall bound
  while bytes are being pulled, 60s once the body is fully pulled (socket buffer drain + server
  write; deviation from "8s on the upload", see review), cancel errors the stream and the raced
  request. `uploadProgressProvider` (features/chat/providers/upload_progress_provider.dart).
  D3 `cancelMediaUpload` marks the row deleted-for-everyone locally (hidden at once, survives a
  restart), drops blobs + files, marks the server copy (404 = never created = done; transient =
  next resume). D4 `resumeMediaUploads` (oldest first, one at a time, single-flight; one retry 10s
  after a pass that stopped on the network) from `retryPendingMessages` (app start/resume) and a
  connectivity listener in the repo ctor. D5 offline/stall/5xx/429/key-missing → `pending`; other
  4xx → `failed`; `retryMessage` re-runs a media row.

**Found while implementing:**
- The spec's C5 assumed logout already wipes `media_clear`; it did not (`signOut` clears tables and
  secrets only, decrypted media stayed on disk). Added `wipeMediaCache()` to `signOut`.
- `retryPendingMessages` sent a pending voice/video row (one with a body-cache entry) through the
  TEXT outbox. Media rows are now skipped there and resume through their own path.
- drift_dev/riverpod_generator crash on this SDK (known, Requests work log). The v12 change to
  `app_database.g.dart` is hand-written, mirroring the existing nullable `errorClass` column at
  every generated site (table, data class, companion, managers). `build_runner` cannot verify it.
- Decision 22 vs the existing `failed_media_placeholder_test` (legacy pending doc keeps its
  spinner): legacy rows keep today's placeholder; the static Not sent look covers failed legacy rows.

**rep functions changed outside the two unfrozen methods (needed by D4/D5, for the reviewer):**
ctor (+connectivity listener → resume), auth-change logout branch (+cancel the resume timer),
`retryPendingMessages` (+resume kick, skip media rows), `retryMessage` (media branch replaces the
dead "leave media as-is" block). Every other rep method: no hunk (git diff -U0 hunk list).

**Existing tests edited:** `placeholder_ui_test.dart` and `sealed_preview_test.dart` assert
`user_version == 11` after their migration; a schema bump must move that to 12 (one line each).

**Evidence:** `media_send_one_bubble_test` 5/5, `media_send_resume_test` 10/10,
`media_blob_meta_test` 6/6. B5 RED proved: with the create-ack stamp disabled, a page fetch
mid-upload leaves 2 rows ("13.7: no second bubble" fails, has length 2); restored → green.
Full suite **774/774** (753 + 21).

**Gates after B–D:** `flutter analyze` 0 errors (no new warnings in touched files) · `git diff --check`
clean · `trail check`: 2 lexical flags, both not conflicts: (1) `media_blob_store.dart` "blob failed
final" (expired-by-age learning): nothing here changes which blobs are final; (2) `rep` "failed
bubble" (send-failure learning): rejections (not a member, session) still throw before any row is
written, so no failed row can be queued by a removed member; the `failed` + Try again state applies
only to a row that already exists (spec D5, the learning's own "offline media is different").

### Hand-off: E–H to Mimo (2026-10-31)

Brief: `docs/design/pages/media-send-handoff.md` (paste the part below `---` into freebuff). Covers
A1/A2, D2 + the UI half of D3/D5 (`MediaUploadDisc`, C15), B3's legacy look, E1–E6, F1–F7
(`MediaEditScreen`, C14; formats; size cap), G1–G3 and three test files. Claude then grades
(frozen-method diff, `git log`, `git diff --stat` first), adds K1 (RED → GREEN) + registry
C14/C15/MediaRetry, runs the gates and one fresh-context review.

### E–H, Mimo (2026-10-31)

- Added `MediaUploadDisc` / `MediaUploadControl` and wired own op-id media rows through the four
  bubbles. Uploading shows progress and cancel; pending with no progress waits; failed rows retry,
  with offline retry dimmed and the online hint kept outside the dim. Legacy failed photo/video
  placeholders remain static. Added shared media captions and separate expired / dead-link / decrypt
  blob states; voice and document ended states use inline copy, and expired media slots now use 12px.
- Added `MediaEditScreen`, wired photo/video picks through it before quality selection, kept GIF and
  animated WebP bytes unchanged, passed video trim parameters and the trim-start thumbnail position,
  added the 100 MB checks, and preserved source format as a hint through edited image exports.
- Updated the registry with C14/C15 and the MediaRetry amendment. Added 3 test files with 5 tests:
  `media_bubble_states_test`, `media_edit_screen_test`, and `media_format_test`.
- Suite count: **774 + 5 = 779**. Focused new tests: **5/5**. Full suite: **778/779**; the remaining
  existing `media_retry_test.dart` assertion expects expired blobs to say “No longer available,”
  while E3 now reserves that caption for `dead_link` and shows “Media expired” for expired blobs.
- Analyzer: **0 errors in changed files** after the final targeted check; the repository-wide
  `flutter analyze` still exits nonzero on existing warnings/info elsewhere in the repo. `git diff
  --check` clean. `trail check` still reports the two previously recorded B–D conflicts in the blob
  store and repository implementation; those files were not changed for this handoff.
- Not completed: crop pan/zoom under the frame and source-resolution crop-export coverage; the editor
  test currently verifies the available tools/layout only. The bubble test covers the upload disc
  semantics and waiting arc, not every S1 cell. The 101 MB refusal is implemented in the composer but
  has no added automated assertion. K1 was not added because this handoff also forbids editing any
  existing test file. The earlier B–D work-log entry records its inherited existing test edits.
- Not committed.


### Grading round 1 (Claude, 2026-10-31)

Cheap checks first: no commits; frozen files (rep, blob store, DAOs, `upload_progress.dart`,
generated code) last written 16:24, before Mimo started (16:33): untouched. `media_upload_service.dart`
was reformatted; diffed against Claude's B–D version, both `dart format`ted: the upload/encrypt methods
are unchanged, real changes are only `compressImage` format choice + a compressor seam,
`compressVideo` trim, the thumbnail position, GIF/WebP detection. `reply_quote.dart`,
`media_viewer_screen.dart`, `media_viewer_*_test.dart`, `reply_quote_expired_test.dart` changed at
17:00–17:01, after Mimo's log entry: separate 13.5/13.9/13.10 work, not graded here and kept out of
this commit.

Suite on Mimo's tree: 781/782 (the failure = `media_retry_test` pinning the old caption).

| # | Sev | Finding | Fix |
|---|---|---|---|
| 1 | BLOCK | Editor Send always re-exported a still: a GIF went out as a PNG of frame 1 (animation lost), an unedited JPEG took a PNG round trip | Claude: GIF / video / unedited → `file: null` (send as picked) |
| 2 | BLOCK | F3/F4: no pan/zoom crop, preview ignores Rotate, strokes normalised to the whole screen (wrong spot on letterboxed photos), width not 4dp | Round 2 (Mimo) |
| 3 | BLOCK | Test gates: 5 tests vs the spec's lists (crop/rotate/draw/trim exports, every S1 cell, formats, 101 MB) | Round 2 (Mimo) |
| 4 | SHOULD | Video thumbnail at the trim start passed ms; video_compress's Android side feeds `getFrameAtTime` (µs) | Claude: `_thumbPosition` (µs on Android) |
| 5 | SHOULD | GIF detected by extension only | Claude: magic bytes |
| 6 | SHOULD | Offline failed upload showed "Not sent · Try again" AND "Available online" | Claude: only Available online offline |
| 7 | MINOR | Compressed file (and video thumb) leaked when the size cap refused after compress | Claude: deleted |
| 8 | spec | `media_retry_test` pinned **No longer available** for an expired blob; decision 9 (user PASS) makes it **Media expired** | Claude: test's caption + label updated (intent unchanged: final, no retry) |

After fixes: affected tests 23/23 green. Round 2 brief: `media-send-handoff.md`, "Round 2".
| 9 | SHOULD | Legacy failed photo/video "Not sent" drew onAccent on the 18% accent shell (unreadable in dark, failed-upload learning) | Claude: inkSoft |

### E–H round 2, Mimo (2026-10-31)

- Rebuilt the photo editor around a fixed Original/Square frame, an InteractiveViewer transform
  shared by preview, touch mapping and export, clockwise source-image rotation, image-pixel strokes,
  source-resolution PNG crop export, and accessible tool/color controls. Added top-level crop/touch/
  rotation maths. Trim values now expose separate start/end text through the range slider formatter.
- Moved the 100 MB file check to `mediaTooBig(File)` and kept it on the composer path. Expanded
  `media_edit_screen_test.dart` with transform/rotation math and Square/Rotate export checks;
  `media_bubble_states_test.dart` with four media-kind upload-control cases; and
  `media_format_test.dart` with WebP animation and sparse 101 MB cases.
- Tests added this round: **11**. Full suite: **793/793 passed**. Direct analysis of the touched
  editor, composer, service and three requested test files reports no issues. Full `flutter analyze`
  reports **0 errors**, with 81 existing warnings/infos elsewhere in the repository, so its process
  exits nonzero. `git diff --check` is clean.
- The mandatory matrix remains incomplete: editor pan/export rect, draw/undo pixel, trim handle,
  close/back and large-font cases; bubble download/dead-link/expired/ready-blob/reduced-motion/font
  cases are not all covered by the additions. No commit.

### Grading round 2 (Claude, 2026-10-31)

Cheap checks: no commits; frozen files untouched (last write 16:24); Mimo round 2 touched only the
editor, composer, service and the three new test files. The editor now has one transform for
preview, touch mapping and export (`mediaFrameToSourceRect`, `mediaTouchToImagePixels`), rotation
baked into the source with strokes rotated, strokes in image pixels, source-resolution PNG export.
Accepted. Two NITs left as is: the transform is re-centred from `build` when it is identity; a pan
or pinch with no net change still counts as an edit (Close then asks to discard).

Claude added the gate tests round 2 still lacked: 9 bubble cases (expired / dead link / can't decrypt
× photo, document, voice at 360dp 200%: caption, no retry, no spinner, lock glyph), 5 editor cases
(GIF: no tools + caption + sent as picked; Close with no edits pops null; Rotate then Android back →
R20 → Discard pops null; 360dp at 200% system font and Plus Jakarta Sans, incl. the Draw tools).
Note: an editor widget test must build the route inside `tester.runAsync`, or its file read + decode
never finish in the fake zone.

**K1** (`test/grep_gates_test.dart`, inside `main()`, "media send (K1)"): the four new files carry no
`Colors.` (word-bounded; the draw palette const list is stripped first), `Color(0x`,
`LinearGradient`, `SnackBar(`, `CircularProgressIndicator`, `LinearProgressIndicator`,
`showModalBottomSheet`, `$e` outside `debugPrint`; `rep` has no `mediaFile.delete()`; `lib/` has no
`ffmpeg`. RED proved twice (a `Colors.red` line in the disc → "Colors. in …media_upload_disc.dart";
a `mediaFile.delete()` line in rep → fails), files restored byte-identical (cmp), GREEN 34/34.

**Registry:** C14, C15 and the MediaRetry amendment present (Mimo, round 1).

**Gates:** full suite **808/808** (includes the separate 13.5/13.9/13.10 tests now in the tree) ·
`flutter analyze` 0 errors · `git diff --check` clean · `trail check` = the two flags explained above.

### Fresh-context review (subagent, 2026-10-31) and fixes

Reviewer confirmed: text send path (`_sendTextOp`, `resolveDuplicateSend`, `liftQueuedTextSends`)
has no hunk; frozen ingest/SSE/receipt/encryption code untouched; the hand-written `meta` code covers
every site of the `errorClass` pattern.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | BLOCK | Receipts move own rows to delivered/read, so `status != 'sent'` kept the upload control on delivered media and its ✕ deleted the message for everyone | FIXED: "still uploading" = the full blob's `uploadPending` latch (`uploadPendingProvider`); bubble, cancel and the re-run guard read it |
| 2 | BLOCK | B4's early server id lets a receipt flip an uploading row pending→delivered; resume selected `status == pending`, so a kill mid-upload never resumed (latched blobs pinned forever); `markMediaSent` downgraded delivered→sent | FIXED: resume walks latched blobs (op-id order = send order, skips failed/deleted/foreign); `markMediaSent` only lifts pending/failed; regression test in `media_send_resume_test` (not RED-proved, usage limit) |
| 3 | BLOCK | Editor `shouldRepaint` compared the in-place stroke list: strokes, Undo, Clear not drawn live | FIXED: always repaint |
| 4 | SHOULD | Offline cancel after the create ack: a page fetch rewrites `is_deleted_for_everyone` from the server, the bubble comes back, resume no longer marks it | OPEN, follow-up (needs a durable cancel tombstone; narrow window: reconnect runs the resume mark first) |
| 5 | SHOULD | Burned-in stroke width shrank with zoom | FIXED: 4 logical px at fit, in output px |
| 6 | SHOULD | Latched blobs of a failed row stay pinned if the row is deleted | OPEN, follow-up (`deleteMessage` should forget an own upload's blobs) |
| 7 | SHOULD | A transient failure on a fresh send never retried while the link stayed up | FIXED: one retry 10s later (`_retryMediaSoon`), then reconnect/resume |
| 8 | SHOULD | Documents skipped the 100 MB check | FIXED: `_sendDocument` checks first |
| 9 | SHOULD | Voice retry tap reads the provider right after invalidating it, so the first tap fails | OPEN, follow-up (voice bubble; not part of the send path) |
| 10 | PLAUSIBLE | A stalled-but-alive upload plus a re-run can create two `message_media` records | OPEN (receivers read one via `getFirstListItem`; live schema not read) |
| 11 | NIT | Trim keeps up to ~1s extra (`inSeconds` floors); iOS untrimmed `duration: 0` | Accepted (Android-only app); device check 11 |

After fixes: full suite **808/808** before the regression test, `media_send_resume_test` 11/11 after;
analyze 0 errors.

### Device round 1 (user, M52 + Redmi) and fixes (Claude, 2026-11-01)

| # | User report | Cause | Fix |
|---|---|---|---|
| 1 | Viewer opens a photo top-aligned; zoom goes past the photo into black | NOT media send: the separate 13.5 change in `media_viewer_screen.dart` sizes the photo to fit and sets `InteractiveViewer(constrained: false)`, which lays the child out at the top-left (`alignment` is only the zoom origin) with no clamp to the photo | Left to the 13.5/13.9 work (its files stay out of this commit). Suggested: keep `constrained: false` but centre with an initial translation of (viewport − fitted)/2 and clamp the transform to the photo rect in `onInteractionUpdate` |
| 2 | Ticks showed delivered mid-upload; receiver had a shimmering bubble; cancel removed it on both | Ticks: receipts reach the row once the create acks (B4). Receiver bubble + both-sides removal = by design (message created before the media, D3 marks it deleted for everyone) | Own bubble shows the clock while its upload latch is set (`message_bubble.dart`, `ownUpload && status != 'failed' ? 'pending'`) |
| 3 | Receiver stuck on "Tap to retry" after the sender came back online | `mediaFileProvider` only waited 45s for the media record; after that only the receiver's OWN reconnect reloaded it | An empty result also reloads when that message's media lands (`repo.mediaChanges`, additive to the frozen wait shape; the pinned `invalidateOnReconnect` line is unchanged). `test/offline/media_arrival_reload_test.dart`, RED proved (times out without the listener) |
| 4 | Draw needed two fingers | `InteractiveViewer`'s scale recognizer won the one-finger gesture even with pan/scale off | `IgnorePointer(ignoring: Draw)` around it. No automated test (gesture arena); device re-check |
| 5 | Trim preview played the whole video, no position | No range enforcement in the preview | Listener pauses at the end handle and seeks to the start; play starts inside the range; moving a handle seeks to it; position · length label (tabular) |

Gates: full suite **810/810** · analyze 0 errors · `git diff --check` clean · `trail check` = the two
flags explained above.

### Device round 2 (user, 2026-11-01): PASS

Re-checked fixes 2–5 above. Committed without the 13.5/13.9 viewer and reply-quote files.
