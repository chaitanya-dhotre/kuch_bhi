# Albums (12.5) phase 2: work log

Spec: `docs/design/pages/albums.md` (user PASS 2026-11-01) + board `albums.html`. Main at `348b4b0`.
Server: W1 live 2026-11-01 (no PocketBase touched in phase 2).

## Baseline

`flutter test` at `348b4b0`, before any change: **822/822** (2026-11-01).

## Round 1: Claude (data path, grouping, album bubble)

Routing: Claude did A, B7–B10, C2–C4 and D (the bubble reuses the frozen photo/video state rules, so it stayed
here). The rest (B1–B6 UI, E, F, G outside the bubble, K1, K2) goes to Mimo with the brief below; Astra is down
until 2026-11-02 17:30 IST. Claude grades Mimo's round.

| Item | What | Evidence |
|---|---|---|
| A1 | `album_id` = item 0's own pre-assigned id, `album_index` 0…N−1, on the row and the create body | `album_send_test` "3 items → 3 rows…" |
| A2–A4, A7 | `groupChatUnits` (crg): same album + sender → one unit at the earliest row; late rows join; one row → normal; index/time/id order; split page shows the loaded part | `album_grouping_test` (5 tests) |
| A5 | run flags over the collapsed list (`_buildItems` feeds the unit anchors to `computeChatRunFlags`) | `album_grouping_test` "run flags…" |
| A6 | `_findFlatIndex` → `unitHolds(rows, target)`; flash matches any album row | `album_grouping_test` "a jump to a middle row…" |
| A8 | old clients ignore the two fields (nothing else sent) | by construction; device check 1 |
| B7 | `MessageRepository.sendMediaAlbum(conversationId, items, quality)`: N `sendMediaMessage(albumId:, albumIndex:)` in pick order, then one resume pass, after any pass already running (it read its ids before these rows existed) | `album_send_test` |
| B8 | serial, index order; offline holds the rest; 413 on item 1 does not hold item 2 | `album_send_test` (max in flight = 1; offline; 413) |
| B9 (repo half) | per-item `cancelMediaUpload` drops unsent items, sent stay | `album_send_test` "Cancel sending" |
| B10 | create body carries both; a lost-ack re-run sends the same values; single sends carry neither | `album_send_test` |
| C2 | drift v13: `album_id` text?, `album_index` int?; `from < 13` = two `addColumn`; codegen hand-written (33 spans + `Object.hashAll`, 21 fields > `Object.hash`'s 20) | `album_send_test` "schema v12 → v13…" |
| C3 | `_companionFromRecord`: empty `album_id` → null, index only with an id; `ssePinDeleteCompanion` carries both (delete-then-insert would wipe them) | `album_send_test` "ingest maps…" |
| C4 | `rowsInAlbum(conversationId, albumId)` (selectable: `.get()` / `.watch()`), not deleted, by index | `album_send_test` (2 tests) |
| D1–D3 | `AlbumBubble` (C16): tiles 180dp, width clamp [100, 210−40], gap 4, radius 12; count pill + one time pill; one earliest expiry badge bottom-left; least-advanced ticks (clock until all sent); tiles = `ImageMessageBubble` / `VideoMessageBubble` in tile mode (`onTileTap`, `tileLabel`: no shell, no own badge) | `album_bubble_test` |
| D4, D6 | `MessageBubble(album:)`: no `SwipeToReply`; `ReactionBar` keyed by the cover; long-press menu gets the cover (album variant = Mimo F1) | `album_bubble_test` "in MessageBubble…" |
| D5 | tap tile i → `onOpen(i)` (`MessageBubble.onOpenAlbum`); not wired to a screen yet (Mimo E1) | `album_bubble_test` "tap a tile…" |
| D7 | row: "Album, 3 photos and 2 videos, from Asha, 12:41"; tile: "Photo 1 of 3" / "Video 2 of 3" (+ its length chip text), ", sending" / ", not sent" | `album_bubble_test` |
| D8 | `HeroMode(enabled: false)` around the tiles | `album_bubble_test` |
| F3 | `albumLabel(rows)` in crg | `album_grouping_test` |

Shared pieces added: `mediaBubbleInputs` (upload_progress_provider.dart; MessageBubble now uses it too, same logic),
`MediaOverlayPill` (expiry_badge.dart; `ChatBubbleTimestamp`'s overlay uses it), `ExpiryBadge.bottomLeft`.

**Frozen-code diff (function level vs `348b4b0`).** `rep`: only `ssePinDeleteCompanion` (+2 carried fields, doc
count 19 → 21), `sendMediaMessage`, new `sendMediaAlbum`, `_uploadMediaMessage` create body only, `_companionFromRecord`,
`_rowToMessage`. Resume, cancel, decrypt, SSE handler, outbox, keys: untouched. `ssePinDeleteCompanion` is outside
the spec's unfrozen list; it must carry every column or an SSE pin toggle resets `album_id` to null (its own I1
rule). `mb`: `build` (helper call, album branch, cover for menu/reactions, no swipe for albums) + new
`albumSemanticsLabel`. `ib` / `vb`: constructor + `build` (tile-mode bypass of the shell and badge; every state
branch unchanged) + `_BubbleWrapper.bare`.

**Gates round 1 (2026-11-01).** `flutter analyze` 0 errors · `flutter test` **822 + 30 = 852**, all green
(`album_send_test` 9, `album_grouping_test` 9, `album_bubble_test` 12) · `git diff --check` clean · `trail check`:
5 hits, all word-match false positives (backlog.md:329 is wave 4's line, not this change; g.dart:9084 IS the
hand-written-codegen path that learning prescribes; messages_dao:359 orders by createdAt, stores nothing new;
rep:1772/1780 = `sendMediaAlbum`, which touches neither the text send's queue lift nor same-second badges).

**Existing tests edited (beyond the spec's one allowance), with reason.** `placeholder_ui_test` (T9.3),
`sealed_preview_test` (P7.5), `media_blob_meta_test` (v11 → v12): `user_version` 12 → 13 only. They pin the current
schema version; the v12 bump in `d0e3c85` made the same edit. Also learned: the v11 fixture has no messages table,
so the v13 step got the v12-style `sqlite_master` guard (it threw without it). Learning saved:
`.trail/learnings/2026-11-01-a-drift-schema-bump-here-also-chaitanya.md`.

**Dropped:** a `SendMediaMessageNotifier.sendAlbum` wrapper. The "bug wave 1" grep gate counts exactly two send
notifiers; the composer calls `sendMediaAlbum` on the repository instead.

**Not done in round 1 (still open):** everything in the Mimo brief; K1 grep gate; registry K2; the device check;
the fresh-context review (after round 2, over the whole diff).

## Brief for Mimo (round 2: everything left)

Paste below the line into `freebuff --cwd /home/chaitanyadhotre/kuch_bhi --trust-agents`.

---

You are implementing the rest of backlog 12.5 Albums in the Flutter app at /home/chaitanyadhotre/kuch_bhi
(Riverpod + drift, PocketBase backend). Read, in this order: `docs/design/pages/albums.md` (the spec: checklist,
copy in section H, test gates), `docs/design/pages/albums.html` (board S2–S10), `docs/design/pages/albums-work-log.md`
round 1 (what already exists). Do not read whole large files; use `sed -n` ranges or `trail skeleton <file>`.

Already done (do not redo or change): album fields on messages + drift v13, `MessageRepository.sendMediaAlbum`,
`ref.read(messageRepositoryProvider).sendMediaAlbum(conversationId:, items:, quality:)` (items = `AlbumSendItem` records; a grep gate allows only the two existing send notifiers, so the composer calls the repository and does its own debugPrint + toast on a throw), grouping in
`chat_screen.dart`, `AlbumBubble` (`lib/features/chat/widgets/album_bubble.dart`), `MessageBubble(album:,
onOpenAlbum:)`, `albumLabel(rows)` and `unitHolds` in `lib/features/chat/chat_run_grouping.dart`,
`rowsInAlbum(conversationId, albumId)` in the messages DAO, `albumTileLabel`, `MediaOverlayPill`.

Build these (spec ids in brackets):
1. [B1–B3] `attach_sheets.dart`: replace the Photo library + Video library rows with one **Photos and videos** row
   (`Icons.photo_library_outlined`, value `gallery`). In `message_input.dart` `_onAttachPressed`, `gallery` runs
   `ImagePicker().pickMultipleMedia(limit: 20)`; keep the first 20 and toast **Only the first 20 were added.**
   (`showToast`) if more came back. One item → exactly today's single photo or video flow. Two or more → album flow.
2. [B4] `lib/features/media/screens/media_edit_screen.dart` album mode: a 56dp thumbnail strip above the tool row,
   selected ringed in accent 2dp, per-item edits kept in memory, **Remove** (✕, 48dp target, semantics "Remove") on
   the selected thumbnail, strip hidden at one item, GIF/animated WebP items show no tools, Close with any edit →
   existing **Discard changes?**, Send returns `List<MediaEditResult>` in order. Strip thumbnails are buttons
   **Item 2 of 5, selected**. Do not change the Crop / Draw / Trim tools themselves.
3. [B5] one quality sheet per album: all photos → `showMediaQualitySheet(isVideo: false)`, all videos → `isVideo:
   true`, mixed → new variant titled **Quality** with Normal / High subtitles built from `AppConstants` (H copy;
   never number literals), all GIFs → no sheet.
4. [B6] compress item by item in the composer's existing floating upload row, text **Preparing 2 of 5**; its cancel
   stops the whole album (nothing sent). Items over 100 MB (`_withinMediaLimit`) are left out first with the H
   toasts; none left → the existing **Too big to send. The limit is 100 MB.** Then one
   `ref.read(messageRepositoryProvider).sendMediaAlbum(...)`. Reuse the existing compression calls of
   `_sendImage` / `_sendVideo`; do not change the single flows.
5. [E1–E4c] new `lib/features/chat/screens/album_screen.dart`: `AlbumScreen(conversationId, albumId, senderName,
   timestamp)`, pushed with `MaterialPageRoute` and constructor args (no route extras) from `MessageBubble`'s album
   branch: wire `onOpenAlbum` in `chat_screen.dart` (`MessageBubble(onOpenAlbum: (i) => …)`), scrolled so tile i is
   visible. It watches `rowsInAlbum(...).watch()` (filter by sender like the grouping), pops at one row left. Theme
   background. New pure `lib/features/media/album_layout.dart`: `albumLayout(List<double> aspects, double width,
   {double gap = 2}) → List<Rect>` per E2. Collage tiles reuse `ImageMessageBubble` / `VideoMessageBubble` tile mode
   (`onTileTap`, `tileLabel`) like `AlbumBubble` does. Long-press a tile → R19 sheet (`showAppSheet` + `AppSheetChrome`
   + `SheetActionRow`) Reply / Select / Delete for me / Delete for everyone (own + online only, offline hint as in
   `message_context_menu.dart`). Select mode per E4a–E4c; delete for me = `confirmAndDeleteForMe` from
   `message_context_menu.dart`; delete for everyone = an R20 confirm with the H copy, then the existing per-message
   delete-for-everyone call.
6. [E5–E11] split `lib/features/media/screens/media_viewer_screen.dart` into `MediaViewerPage` (one item: zoom,
   clamp, double-tap, video controller, loading/errors) and the existing screen as a shell hosting a `PageView`.
   One item = a pager of one with no counter and **identical behaviour**: `test/media/media_viewer_screen_test.dart`,
   `media_viewer_video_test.dart`, `media_entry_points_test.dart` must pass **unedited**. Paging only at fit (scale
   ≤ 1.01), counter **2 of 5** (tabular figures) announced on change, full file for the current page only, one video
   controller at a time, Hero per item, reduced motion → `jumpToPage` and no Hero. The collage opens it at tile i.
7. [F1, F2, F4, F5, F7] `showMessageMenu` gains `List<Message>? album` (pass `album` from `MessageBubble`'s album
   branch, which today passes the cover): React/Reply/Pin → cover, Star/Unstar and Delete for me → every row, Delete
   for everyone → every own row (online only), **Cancel sending** while any own row is unsent (`cancelMediaUpload`
   per unsent row, then toast **Upload cancelled**), no Copy; deletes reuse `confirmAndDeleteForMe` / the E4b copy.
   Album label (`albumLabel` over `rowsInAlbum(...).get()`/`.watch()`) instead of Photo/Video in `reply_quote.dart`
   (only when the quoted row has an `albumId` and 2+ visible rows), the pinned banner and the home preview
   (`ConversationPreviewText`). Starred (`starred_messages_screen.dart`): one card per album's starred rows with the
   cover thumbnail and label; tap = the existing jump.
8. [K1] in `test/grep_gates_test.dart`, INSIDE `main()`, an "albums" group per the spec's K1 list over
   `album_bubble.dart`, `album_screen.dart`, `album_layout.dart` and the viewer page/pager files, plus "no
   `pickMultiImage` in lib/". Run it once with a deliberate violation to prove it fails (RED), remove it (GREEN);
   paste both outputs into this work log.
9. [K2] `docs/design/10-registry.md`: add C16 + C17 and amend C14 + the viewer row (text in the spec's Registry
   amendments table).
10. Tests: write the NEW test files the spec's "Test gates" lists that do not exist yet (`album_layout_test`,
    `album_screen_test`, `media_pager_test`, `media_edit_album_test`, `starred_album_test`) and amend
    `test/chat/attach_sheets_test.dart` (the only existing test you may edit). Assert outcomes (what the user sees,
    which calls ran), not internal flags. Semantics via `tester.getSemantics` / `find.bySemanticsLabel`. Large text =
    `pumpHost(..., large: true)` from `test/core/sheet_harness.dart`, with and without `fontFamily: 'PlusJakartaSans'`.

Rules (an automatic fail if broken): do not touch encryption, keys, `message_repository_impl.dart`, the drift files,
`album_bubble.dart`, `chat_run_grouping.dart`, the outbox, receipts or the SSE handler. No `Colors.`, `Color(0x`,
`SnackBar(`, `CircularProgressIndicator`, `LinearProgressIndicator`, `showModalBottomSheet` or `extra:` in new files
(use `context.t` tokens, `showToast`, `BusySpinner`, `showAppSheet`). No `$e` or `e.toString()` in any user-visible
text. No `ref` inside any `dispose()`. Never `await ref.read(<autoDispose provider>.future)` without a listener.
Respect `MediaQuery.disableAnimationsOf`. Do not commit, do not push, do not run `build_runner`.

Gates you run yourself before stopping: `flutter analyze` (0 errors), `flutter test` (all green; write the count
here as `822 + N = total`), `git diff --check`. List every file you changed at the end of this work log under
"Round 2 (Mimo)". Claude grades the result; do not claim PASS.

## Round 2 (Mimo)

**Implemented / recorded.** The remaining album UI, editor mode, pager, starred grouping, K1 gate, and registry amendments are present in the working tree. The editor and collage tests were adjusted to create temporary files synchronously and allow asynchronous media decoding to progress in `tester.runAsync`. The starred album card test supplies a test database and resolved media providers.

**K1 proof.** With a temporary `SnackBar(` comment in `lib/features/media/album_layout.dart`, the gate reported:

```text
00:00 +0: albums: tokens, app chrome, no $e, one picker
00:00 +0 -1: albums: tokens, app chrome, no $e, one picker [E]
Expected: empty
Actual: ['lib/features/media/album_layout.dart: SnackBar(']
album gates failed: [lib/features/media/album_layout.dart: SnackBar(]
```

After removing the temporary comment, the same gate reported:

```text
00:00 +0: albums: tokens, app chrome, no $e, one picker
00:00 +1: All tests passed!
```

**Gate results (2026-11-02).** `flutter analyze`: 0 errors, 91 total analyzer issues (mostly existing infos/warnings). `flutter test --reporter compact`: **822 + 71 = 893** discovered; 883 completed and 10 failed. Failures remain in album editor send/order, item-2 edit, remove/discard checks, and album screen pager/selection/semantics checks. The focused GIF editor case, starred album card case, and K1 gate completed successfully. `git diff --check` returned no output. `trail check` reported 6 conflicts and additional nonblocking word-match hits; these include the existing hand-written schema generation and DAO ordering entries noted in Round 1, plus message-input/repository paths and the grep-gate title. No trail changes were made to hide those matches.

**Changed implementation files (lib).**

- `lib/core/constants/app_constants.dart`
- `lib/data/local/database/app_database.dart`
- `lib/data/local/database/app_database.g.dart`
- `lib/data/local/database/daos/messages_dao.dart`
- `lib/data/local/database/tables/messages_table.dart`
- `lib/domain/entities/message.dart`
- `lib/domain/repositories/message_repository.dart`
- `lib/features/chat/chat_run_grouping.dart`
- `lib/features/chat/providers/album_provider.dart`
- `lib/features/chat/providers/upload_progress_provider.dart`
- `lib/features/chat/screens/album_screen.dart`
- `lib/features/chat/screens/chat_screen.dart`
- `lib/features/chat/widgets/album_bubble.dart`
- `lib/features/chat/widgets/attach_sheets.dart`
- `lib/features/chat/widgets/expiry_badge.dart`
- `lib/features/chat/widgets/image_message_bubble.dart`
- `lib/features/chat/widgets/message_body_text.dart`
- `lib/features/chat/widgets/message_bubble.dart`
- `lib/features/chat/widgets/message_context_menu.dart`
- `lib/features/chat/widgets/message_input.dart`
- `lib/features/chat/widgets/pinned_message_banner.dart`
- `lib/features/chat/widgets/reply_quote.dart`
- `lib/features/chat/widgets/video_message_bubble.dart`
- `lib/features/media/album_layout.dart`
- `lib/features/media/screens/media_edit_screen.dart`
- `lib/features/media/screens/media_viewer_page.dart`
- `lib/features/media/screens/media_viewer_screen.dart`
- `lib/features/starred_messages/screens/starred_messages_screen.dart`
- `lib/infrastructure/repositories/message_repository_impl.dart`

**Changed test files.**

- `test/chat/album_bubble_test.dart`
- `test/chat/album_grouping_test.dart`
- `test/chat/attach_sheets_test.dart`
- `test/chat/starred_album_test.dart`
- `test/grep_gates_test.dart`
- `test/media/album_layout_test.dart`
- `test/media/album_screen_test.dart`
- `test/media/media_edit_album_test.dart`
- `test/media/media_pager_test.dart`
- `test/media/viewer_harness.dart`
- `test/offline/album_send_test.dart`
- `test/offline/media_blob_meta_test.dart`
- `test/offline/placeholder_ui_test.dart`
- `test/offline/sealed_preview_test.dart`

**Changed design files.** `docs/design/10-registry.md`; `docs/design/pages/albums-work-log.md`.

## Round 2 grading (Claude, 2026-11-02)

**Frozen-code check (done first, Mimo stood in for Astra).** No stray commits (HEAD still `348b4b0`). Every file the brief froze
(`message_repository_impl.dart`, the drift files, `album_bubble.dart`, `chat_run_grouping.dart`, `chat_provider.dart`, outbox,
receipts, SSE, E2E key/crypto code) carries an mtime from before round 1 ended (19:30), so round 2 did not touch them. No file
outside the brief's list changed, except `test/media/viewer_harness.dart`, which gets two additive params (`extraOverrides`, `open`)
whose defaults keep the old behaviour. The existing viewer tests (`media_viewer_screen_test`, `media_viewer_video_test`,
`media_entry_points_test`, `media_edit_screen_test`): `git diff HEAD` empty. Banned-pattern grep over the new files: clean
(`debugPrint('…$e')` only).

**Mimo's state on arrival:** 893 tests, 8 failing (7 album_screen, 1 media_edit_album).

**Fixed by Claude (code):**
- Collage tiles took a tap only once the thumbnail had loaded (the inner bubble's tap), so a loading or skeleton tile couldn't be
  opened or selected. Now the outer GestureDetector has `onTap` too, as in AlbumBubble. 3 collage failures were this.
- The selection bar got `isMine` (first row) instead of `allOwn`. `albumRowsProvider` never filtered by sender, so another member's
  row carrying the same `album_id` joined the collage, the labels and Starred. The provider now keeps only the cover's sender's rows
  (new test in `album_send_test`).
- Delete in selection mode now ends selection mode (it used to leave "0 selected").
- Review BLOCK 1: rotating while zoomed called the shell's `setState` from `didChangeDependencies` (page → `onZoomChanged`) →
  "setState() called during build"; the same path ran from `didUpdateWidget` → `_deactivate` → `onVideoPlayingChanged(false)`. The
  zoom reset now notifies the shell after the frame. `_deactivate` no longer calls the shell; `_onPageChanged` re-shows the chrome.
  Test `rotating while zoomed…`: RED on the old code, GREEN now.
- Review BLOCK 2: `_onVideoTick` reported `playing=true` every 100 ms and restarted the 3 s hide timer, so on a device the chrome
  never hid while a video played. The shell now acts on a change only. Test `a playing video with ticking position…` (the fake's
  position advances): RED on the old code, GREEN now.
- Review BLOCK 3: Remove down to one item, then Send → `MediaEditResult` popped to a `push<List<MediaEditResult>>` route →
  TypeError, editor stuck. `_send` now branches on `widget.items != null`. New test `Remove down to 1, then Send`.
- Review BLOCK 4: a cancel during the final `sendMediaAlbum` deleted not-yet-moved files → part of the album sent while the toast
  said "Upload cancelled". The row now hides and the temp list is handed over before the send. On a send throw, files not taken by
  the repository are deleted; a compress/thumbnail throw now discards the temps; items over 100 MB after compression get the same
  left-out toasts (all of them → `kUploadTooBig`). Album cancel also stops `VideoCompress`. No widget test (needs the picker);
  device check item.
- SHOULDs: Save/Share come back after a partial swipe back (`_reportedFile = null` on leave); your own album says **You** in the
  viewer; the collage removes its own route when ≤1 row is left, even with the viewer open on top; starred album card uses
  `BusySpinner` (was a new `CircularProgressIndicator`).
- Spec misses: E4a (long-press in selection toggles), E4b (one selected → "Delete message?" single copy), F4 (album label only when
  the quoted row is the cover; shortcut: item 0 replied from the collage reads as the album), G1 (AlbumScreen route has zero
  duration under reduced motion). E4a/E4b covered by a new collage test.
- Test fixes (test bugs, not code): `byTooltip` → IconButton ancestor; SemanticsHandle disposed in the body; the "one row is
  theirs" case rewritten as "their album" (with the sender filter a mixed album can't reach the screen); collage semantics wait for
  load and check "selected" only in selection mode (E4c); editor rotate test gives the PNG export real time; pager adds "leaving a
  video page disposes its controller" (it uses the fake Mimo left unused).

**Not fixed, noted:** if `sendMediaAlbum` throws on item k > 0 (session ended mid-send), items 0..k−1 still upload while the
composer toasts "Couldn't send". It's rare (not-a-member throws before item 0). A collage tile still loading has no semantics
label (same as AlbumBubble).

**Fresh-context review:** 1 round. 4 BLOCK, 7 SHOULD, 2 NIT and 3 spec misses. Every BLOCK is fixed; every SHOULD is fixed except
the partial-send toast (above); NIT `mounted` after the GIF awaits: fixed (`if (!mounted) return` before the send). NIT AlbumScreen route under reduced motion: fixed (G1 above).

**Gates after grading (2026-11-02):** `flutter test` **822 + 77 = 899** all green · `flutter analyze` 0 errors (88 issues, all
existing infos/warnings outside the album files) · `git diff --check` clean · `trail check`: 6 ✗, all word-match false
positives (5 from round 1, plus `message_input.dart:424` "keeps today's single flow" and the K1 gate title `grep_gates_test.dart:855`)
· v12→v13 migration test green · K1 gate inside `main()`, RED/GREEN logged by Mimo above.

**Next:** your device check (spec "Device check list", M52 + Redmi S2). Add to it: cancel during "Preparing N of N" (nothing sent),
Remove down to one in the editor then Send, rotate a zoomed photo in the pager, and play a video in the pager (the chrome hides
after 3 s). Commit only after a device PASS (this log, albums.{md,html}, the registry, and the 3 learnings). Do not push.

## Device check round 1 (user, 2026-11-02): FAIL on photo arrangement only

The user reports everything else works. Screenshots: in the chat bubble the photos didn't fill their 180dp tiles (orange showed
below them); in the collage every photo stopped at 210dp wide, with black gaps inside its rect.

**Cause:** `ImageMessageBubble` in tile mode still used the single bubble's sizing: a loose `Stack` → `maxWidth: 210` →
`AspectRatio(photo aspect)`. Whenever the tile's box differs from the photo's shape, the photo letterboxed inside it. In the chat
that's a wide photo clamped to bubble − 40; in the collage, the `albumLayout` rects crop by design and are wider than 210. The tests
missed it because their photo had exactly the tile's shape. The video bubble was fine (`StackFit.expand`).

**Fix:** in tile mode the Stack is `StackFit.expand` and the photo (Hero, `BoxFit.cover`) fills the tile. The single bubble is
unchanged. A downloaded full photo in a tile decodes at screen width, not 210dp (collage tiles can be full width).

**Tests:** `album_bubble_test` "a photo whose shape differs from its tile still covers the whole tile"; `album_screen_test` rects
test now also checks each photo fills its rect. Both are RED on the old layout and GREEN now.

**Gates:** 822 + 78 = **900** green · analyze 0 errors · `git diff --check` clean · the frozen viewer tests are still unedited.
`server_created_watermark_test` C1a failed once under full-suite load, then passed 3/3 alone and in the next full run (flaky,
not touched by this change).

**Next:** device re-check of the arrangement (chat bubble tiles + collage), then commit on PASS.
