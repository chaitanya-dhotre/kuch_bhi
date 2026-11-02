# Albums: several photos and videos sent together read as one (acceptance checklist)

Date: 2026-11-01. Backlog **12.5**, taking **Page 9 decision 6** (swipe between items) for albums. Visual ground
truth: **`docs/design/pages/albums.html`** (sections S1–S14, numbered; S1 = how items are known to belong together;
S5 = the album bubble in every state; S8 = collage layout rules; S13 = hooks for 12.1; S14 = diff summary).
Authority: `docs/design/00-foundation.md` (tokens/laws) → `docs/design/10-registry.md` (shared pieces) → this
checklist. Page letters A–K are page-local; decisions are numbered (bottom). Line refs as of `b90bf4f`:
`mi` = `lib/features/chat/widgets/message_input.dart`, `as` = `attach_sheets.dart`, `mb` = `message_bubble.dart`,
`ib` = `image_message_bubble.dart`, `vb` = `video_message_bubble.dart`, `str` = `swipe_to_reply.dart`,
`cm` = `message_context_menu.dart`, `rq` = `reply_quote.dart` (same folder), `cs` =
`lib/features/chat/screens/chat_screen.dart`, `crg` = `lib/features/chat/chat_run_grouping.dart`, `mv` =
`lib/features/media/screens/media_viewer_screen.dart`, `me` = `lib/features/media/screens/media_edit_screen.dart`,
`rep` = `lib/infrastructure/repositories/message_repository_impl.dart`, `mt` =
`lib/data/local/database/tables/messages_table.dart`, `adb` = `lib/data/local/database/app_database.dart`,
`fcm` = `lib/services/fcm_service.dart`, `pol` = `lib/features/chat/message_offline_policy.dart`.

**Starting point (audited 2026-11-01, `trail ask/skeleton/grep` + `sed -n` ranges; no code run, no live PocketBase
read).** Suite baseline **810/810** at `b90bf4f` (the wave 4 loose-ends session lands on top, so phase 2 re-runs the
baseline first and records it). Drift schema **v12** (`adb:74`).

**Facts, confirmed in code (not assumed).**
1. **No multi-pick today.** The attach sheet offers Take a photo · Photo library · Record a video · Video library ·
   Document (`as:20-27`); each runs `pickImage` / `pickVideo` / `pickFiles(allowMultiple: false)` (`mi:362-430`).
   The installed `image_picker` **1.2.2** (lock file) already has `pickMultipleMedia({limit})`, photos and videos
   mixed in one system picker. **No new dependency.**
2. **The send path is one file per call** and already shaped for this (media-send S15): `sendMediaMessage`
   pre-assigns a time-sortable record id (`generateOpId`, `rep:1685`; ids sort in send order, `op_id.dart:9-14`),
   inserts one row + ready blobs in one transaction (`rep:1709-1744`), then starts its upload **unawaited**
   (`rep:1753`). Called N times in a row, N uploads would run **at once**. The resume pass is already serial,
   oldest id first, and stops at the first network failure (`rep:2100-2121`), which is exactly an album's order.
3. **Nothing on a message can group it today.** `messages` rows carry no batch field (`mt:11-70`); the server create
   body has none (`rep:1873-1886`). The decrypted body is a session cache only (`bodyCache`, "never the dropped
   column", `rep:1747`), so a group id hidden inside the encrypted body could not drive the list builder.
4. **The chat list is a flat item list** (`_MsgItem` / `_DateItem` / `_HistoryEndItem`, `cs:38-56`) built in
   `_buildItems` (`cs:334-357`) with run flags from `computeChatRunFlags` (`crg:21`). Search and jump map a message to
   an item in `_findFlatIndex` (`cs:409-423`). An album is one new item kind there.
5. **Every bubble is wrapped in a horizontal drag** (`SwipeToReply`, `mb:379`, `str:75-76`). A sideways-scrolling
   album inside it would fight the reply swipe.
6. **The viewer takes one item** (`MediaViewerArgs`: conversationId, serverId, mediaType, senderName, timestamp,
   heroTag, thumbPath; `mv:30-47`), owns system UI, zoom clamp, chrome auto-hide and the video controller in one
   821-line state class (`mv:76-821`). Page 9 decision 6 left it "built so it slots into a page".
7. **Message actions are per row**: react, reply, copy, star, pin, delete for me / for everyone (`pol:22-30`,
   `cm:379-455`), reactions keyed by one server id (`ReactionBar(messageServerId:)`, `mb:359`), reply quotes resolve
   one row (`rq:80-81`, `rq:175-181`).
8. **Push notifications are per message** and the phone shows one notification per conversation, replaced on each
   (`fcm:617`, id = `conversation_id.hashCode`). Five photos replace the same notification five times; no change
   here (the text comes from the server hook).
9. **Older app versions** read only the fields they know. Two extra fields on a message change nothing for them.

**Routing.** Spec: Claude (this session). Phase 2: the schema + send + grouping work (B, C) touches the send path,
ingest and drift codegen, so **Claude implements B–C**; the bubble, collage, pager and editor strip (D–G) are
spec-able and go to **Astra** (Omnirush back after 2026-11-02 17:30 IST) or Mimo, with Claude grading. The grading
pass is a fresh-context reviewer, never the implementer.

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test` green (baseline
re-run at phase 2 start, plus the new tests; no existing test edited to pass, except `attach_sheets_test.dart` for the
merged row, decision 6) · test-gate files below green · `git diff --check` clean · K1 grep gate green (proved RED
once) · `trail check` clean · frozen-method diff vs HEAD empty · drift v12 → v13 migration test green · live schema
change W1 applied and read back · fresh-context review with no open BLOCK, findings in `albums-work-log.md` ·
device captures of the device-check list · user device PASS (no commit without it).

**Spec status: user PASS 2026-11-01; every deferred decision = its default (1–27), with the user's changes:** decision 5 = **20 items**, decision 21 = star the whole album, Starred shows it as one card that jumps to the album (F7); decision 27 = Select in the collage (E4a–E4c). R1 done 2026-11-01: W1 also locks the two fields in the update rule. Phase 2 goes in a fresh session.

**Live PocketBase.** R1 done 2026-11-01 (read-only, user approved); **ask the user before any other.** SSH over Tailscale `ubuntu@100.64.208.55`
(key `/home/chaitanyadhotre/Chaitanya/Oracle/ssh-key-2026-04-28-1.key`, outside the sandbox),
`sudo sqlite3 -readonly /opt/pocketbase/pb_data/data.db`.
- **R1 (read) DONE 2026-11-01.** `messages` fields: `id` (text, max 15, `^[a-z0-9]+$`), `conversation_id`,
  `sender_id`, `type`, `encrypted_body`, `iv`, `reply_to_id`, `reply_preview`, `is_deleted_for_everyone`,
  `deleted_for_user_ids`, `is_pinned`, `is_starred_by`, `expires_at`, `created`, `updated`. No album or batch field;
  **no `media_id` field either**, yet every media create sends `'media_id': ''` and succeeds: **this server silently
  drops unknown create-body fields.** Create rule = sender is the caller and a member; no field restrictions, so the
  new fields need no create-rule change. **Update rule = two branches (sender marking deleted-for-everyone; any
  member) that each list the fields a caller may not set**; new fields are not in those lists, so without W1's rule
  change any member could rewrite another member's `album_id` / `album_index`. Hooks on `messages`:
  `fcm_notify.pb.js` (onRecordCreate, sends only id, conversation, sender, sender name, recipients to the push
  relay: one push per message, never reads or rejects other fields) and `disappearing_messages.pb.js` (hourly cron
  delete of expired rows). No hook copies, whitelists or rejects create-body fields. Index: only
  `idx_msg_conv_created`; albums need none (grouping is on the phone).
- **W1 (write) DONE 2026-11-01 (user approved).** Migration `pb_migrations/1793541000_updated_messages_album.js`
  (dry-run on a copy first; applied by `systemctl restart pocketbase`; health 200, no log errors). Read back:
  `album_id` text, optional, `^[a-z0-9]{15}$`, max 15; `album_index` number, optional, `onlyInt`, 0–19; each update
  branch now holds both `:isset = false` locks. Existing 566 rows: `album_id` = `''`, `album_index` = 0 (defaults), so
  the client must treat an empty `album_id` as "not in an album" and ignore the index then (C3). Backup
  `/home/ubuntu/pb_backups/data.db.20261101-albums-pre`; the migration has a down step (not run).
  Original plan, for reference: add two optional fields to `messages`: `album_id` (text,
  pattern `^[a-z0-9]{15}$`) and `album_index` (number, integer, 0–19). Through the admin UI or a migration file, the
  way past schema changes were made (`server-topology` memory). **Also** add `@request.body.album_id:isset = false &&
  @request.body.album_index:isset = false` to **both** update-rule branches (R1: else any member can regroup another
  member's photos). Back up `data.db` first. Read back the fields and the rule after. **W1 lands before any phone
  runs the album build:** before it, the server drops the two fields silently and albums arrive as separate bubbles.

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence; `[ ]` pending.

---

## ⛔ Frozen (read first: a breach here is an automatic FAIL)

**Still frozen:** E2E and key code anywhere: `encryption.*`, `_encryptFileBytes`, `_getConvKey`, the store's
download → verify → decrypt section, `_lookupRecord`, the stall bound, the store's failure classes and one-day rule,
`mediaFileProvider`'s wait/retry shape, receipts, the decrypt pass, the SSE handler's control flow, the outbox
worker, `_uploadMediaMessage` except its create body, the resume pass, cancel, `MediaUploadDisc` (C15), the photo /
video / voice / document bubbles' state rules (media-send A–E), the editor's Crop / Draw / Trim tools (C14), the
quality sheet's **Normal / High** values, the voice recorder.

**Unfrozen by this page, and only these (decision 2):**
- `rep`: `sendMediaMessage` gains `albumId` / `albumIndex` (written on the row, sent in the create body, and an album
  send does **not** start its own upload: the caller runs `resumeMediaUploads()` once after the last item);
  `_uploadMediaMessage`'s create body gains the two fields; `_companionFromRecord` (`rep:5021`) copies them;
  new album helpers for delete-all and cancel-the-rest built on the existing delete and cancel calls.
- `mt` + messages DAO + `adb`: two nullable columns, schema **v13**, generated code **written by hand** (the
  media-send learning: `build_runner` crashes on SDK 3.13); one DAO query `rowsInAlbum(conversationId, albumId)`.
  Domain `Message` gains `albumId` / `albumIndex`.
- `cs`: `_buildItems`, `_findFlatIndex`, selection and run flags learn the album item.
- `mv`: split into a per-item page + a pager shell (E); behaviour of a single item unchanged, every existing
  viewer test passes **unedited**.
- `me`: an album mode with an item strip (B4). The tools themselves are untouched.
- `starred_messages_screen.dart`: one card per starred album (F7); the jump itself is unchanged.
- `mi` attach flow, `as` (one merged gallery row, a mixed-quality variant), `cm` (album menu variant), `rq`, the
  pinned banner preview and `ConversationPreviewText` (album label only).

When an edited file holds frozen code (`rep`, `mv`, `me`, `mb`, `mi`), every other method in it is diffed against
HEAD **at function level** and must be byte-identical. No timeout is ever wrapped around key resolution, encryption
or decrypt; a network bound covers the network call only. Read for context, do not re-solve:

- `.trail/learnings/2026-10-31-a-media-send-keeps-one-id-chaitanya.md` (one id from pick to sent; hand-written drift codegen)
- `.trail/learnings/2026-11-01-a-zoomable-photo-keeps-the-zoom-chaitanya.md` (zoom layer full-screen, clamp per axis; test outcomes, not flags)
- `.trail/learnings/2026-11-01-drawing-on-a-zoomable-photo-needs-chaitanya.md` (gesture arenas need a device check)
- `.trail/learnings/2026-10-30-a-fullscreen-video-must-pause-itself-chaitanya.md` (pause on every non-resumed state; buttons outside the double-tap detector)
- `.trail/learnings/2026-10-31-messages-sent-quickly-jumped-around-because-chaitanya.md` (ack re-stamps with server time; same-second ties)
- `.trail/learnings/2026-10-31-a-refetched-message-must-not-re-chaitanya.md` (second-precision times)
- `.trail/learnings/2026-10-31-reading-an-auto-disposed-provider-s-chaitanya.md` (never await an autoDispose future without a listener)
- `.trail/learnings/2026-10-31-a-screen-never-uses-ref-in-chaitanya.md` (no `ref` in dispose)
- `.trail/learnings/2026-10-29-a-sheet-row-s-offline-hint-chaitanya.md` (sheet rows at 200% text)

## A. Belonging together (S1; decisions 1, 3, 4)

- [ ] **A1 MUST (decision 1)** An album item carries `album_id` = the record id of the album's **first** item (index
  0, its own pre-assigned id; no extra id generator) and `album_index` 0…N−1 in pick order, on the server record and
  on the local row. Item 0 carries both too. A message without them is not in an album.
- [ ] **A2 MUST** Grouping happens **only** in the list builder, over loaded rows: rows with the same `albumId`
  **and** the same `senderId` form one album item. The album sits at the position of its **earliest** row; rows
  that arrive later (a slow upload, a Try again) join it even if another message landed in between (decision 3).
- [ ] **A3 MUST** An album with **one** visible row renders as that row's normal bubble (a cancelled or deleted
  sibling leaves a plain photo). Deleted rows are already filtered by `watchMessages`.
- [ ] **A4 MUST** Tiles are ordered by `albumIndex`; ties (never expected) by `createdAt`, then `localId`.
- [ ] **A5 MUST** Run flags (`crg`) are computed over the collapsed list: the album counts as one message
  (sender = its sender, time = its earliest row).
- [ ] **A6 MUST** `_findFlatIndex` maps any row of an album to the album item; search, reply jump and pinned jump
  scroll to the album and flash it.
- [ ] **A7 MUST** A page boundary may split an album: the loaded part shows; the rest joins when the older page loads.
  No fetch is added for it.
- [ ] **A8 MUST (decision 4)** Older app versions: unchanged behaviour, N separate bubbles. Nothing is sent to them
  that they could show wrongly.

## B. Send (S2–S4; decisions 5–11)

- [ ] **B1 MUST (decision 6)** The attach sheet's **Photo library** and **Video library** rows become one row,
  **Photos and videos** (`Icons.photo_library_outlined`, value `gallery`), which runs
  `pickMultipleMedia(limit: 20)`. Take a photo, Record a video and Document are unchanged.
- [ ] **B2 MUST** One item picked → **exactly today's flow** (single editor → quality sheet by type → one bubble).
  Two or more → the album flow below.
- [ ] **B3 MUST (decision 5)** At most **20** items. The picker gets `limit: 20`; if a platform ignores it, the first
  20 are kept and the toast **Only the first 20 were added.** shows (R5).
- [ ] **B4 MUST (decision 7)** `MediaEditScreen` album mode (C14 amended): a strip of 56dp thumbnails above the tool
  row, the selected one ringed in accent (2dp). The tools act on the selected item; each item keeps its own edits in
  memory. A **Remove** button (✕, 48dp target) on the selected thumbnail drops it from the album; down to one item the
  strip hides and the screen is the single editor. GIF / animated WebP items show no tools and the existing caption.
  Close with any edit → the existing R20 **Discard changes?** dialog. **Send** returns `List<MediaEditResult>`.
- [ ] **B5 MUST (decision 8)** **One** quality sheet per album. All photos → today's photo sheet; all videos →
  today's video sheet; mixed → title **Quality**, rows **Normal** / **High** with subtitles built from the existing
  constants: **Photos up to 1280px, videos 720p · kept 60 and 30 days** / **Photos up to 2560px, videos 1080p · kept
  30 and 15 days** (numbers from `AppConstants`, never literals). All GIFs → no sheet (media-send decision 12).
- [ ] **B6 MUST (decision 9)** Compression runs item by item in the composer's existing floating row, which reads
  **Preparing 2 of 5**; its existing cancel stops the whole album (nothing sent). An item over 100 MB is left out
  before compression with **1 item is over 100 MB and was left out.** / **2 items are over 100 MB and were left
  out.**; if none is left, the existing **Too big to send. The limit is 100 MB.**
- [ ] **B7 MUST** After the last compression: N `sendMediaMessage(..., albumId: firstId, albumIndex: i)` calls in
  pick order (each its own transaction, as today; the first call's pre-assigned id is the album id, so the caller
  generates it with `generateOpId()` and passes it as item 0's id), then **one** `resumeMediaUploads()`.
- [ ] **B8 MUST (decision 10)** Uploads run **one at a time in index order** (the resume pass, unchanged). A network
  failure on item k holds k+1…N (the pass stops, retries in 10 s, on reconnect and on start); a terminal failure
  (`failed`) on item k does not hold the rest.
- [ ] **B9 MUST (decision 11)** Per-item progress and cancel: each sending tile shows C15 (arc + ✕ cancels that item
  only). The album's long-press menu adds **Cancel sending** while any own item is unsent: it cancels every unsent
  item (existing `cancelMediaUpload` per item), sent items stay, then toast **Upload cancelled** (existing).
- [ ] **B10 MUST** The create body carries `album_id` and `album_index`; a re-run (resume, Try again, duplicate-id
  path) sends the same values. Documents and voice notes are never album items.

## C. Schema and ingest (S11; decisions 1, 2)

- [ ] **C1 MUST** (schema half done 2026-11-01, see W1; the client proof below is phase 2's) Live W1 applied and read back: `messages.album_id` text optional with
  the 15-char pattern, `messages.album_index` number optional, integer, 0–19; both update-rule branches refuse
  `album_id` / `album_index`. Proof with the phase 2 build: a created album item read back from the server carries
  both fields; a member's update that sets `album_index` on another member's message is refused (400/403).
- [ ] **C2 MUST** Drift v13: `albumId` text nullable, `albumIndex` int nullable on `messages`; migration =
  two `addColumn`; generated code hand-written in `app_database.g.dart`; migration test v12 → v13 keeps every row
  with both columns null.
- [ ] **C3 MUST** `_companionFromRecord` maps `album_id` (empty → null) and `album_index` (only when `album_id` is
  set). Nothing else in the ingest or decrypt pass changes (function-level diff).
- [ ] **C4 MUST** `rowsInAlbum(conversationId, albumId)` DAO query (not deleted, ordered by index) feeds the reply
  quote, pinned banner and home preview labels (F).

## D. The album bubble (S5, S6; decisions 12–15)

- [ ] **D1 MUST (decision 12)** `AlbumBubble` (new, C16) = the media bubble shell (own: accent border like a single
  photo; theirs: surface) holding a horizontal list of tiles. Tile height **180dp**; tile width = 180 × the item's
  aspect, clamped to **[100dp, bubble width − 40dp]** so the next tile always peeks. Gap 4dp, inner radius 12,
  `BoxFit.cover`. Bubble width = the single photo bubble's width. Aspect from the stored metadata; unknown → 1.0.
- [ ] **D2 MUST** Fixed overlays that do not scroll: a **count pill** top-right (stack glyph + **5**, 50% black,
  white ink, the `.ts` style) and the time + ticks pill bottom-right. Ticks = the least advanced status among the
  album's own rows (clock until every item is sent). One expiry badge (existing `ExpiryBadge`) with the **earliest**
  expiry among the items.
- [ ] **D3 MUST** Each tile reuses the single bubble's state rules (media-send A1): loading skeleton (R11), sending
  disc (C15), waiting, **Not sent** + **Try again**, failed download **Tap to retry** (invalidates first), offline
  38% + **Available online**, ended captions (**Media expired** / **No longer available** / **Can't decrypt**, 12px,
  `FittedBox.scaleDown`), Page 9's not-downloaded disc. A video tile adds ▶ and its length chip (tabular figures).
  The rules are called, not copied (one source, A2 of media-send).
- [ ] **D4 MUST (decision 13)** No swipe-to-reply on an album: `SwipeToReply` is not wrapped around `AlbumBubble`;
  Reply stays in the long-press menu. The sideways scroll owns horizontal drags.
- [ ] **D5 MUST (decision 14)** Tap a tile → the collage (`AlbumScreen`), scrolled so that tile is visible. Tap on
  a tile's own button (✕, Try again, Tap to retry, download disc) does that button's action instead.
- [ ] **D6 MUST** Reactions under the album = the **cover**'s (the lowest-index visible row): `ReactionBar(messageServerId:
  cover.serverId)` once, under the bubble (decision 15).
- [ ] **D7 MUST** Semantics: the bubble is one container node **Album, 3 photos and 2 videos, from Asha, 12:41**
  ("from You" on own); each tile a button **Photo 1 of 5** / **Video 2 of 5, 0:14**, with its state appended
  (**sending, 40 percent**, **not sent**, **media expired** …). The count pill is `ExcludeSemantics`.
- [ ] **D8 MUST** Reduced motion: the list scrolls without fling animation effects added by us (none are), no
  Hero on open.

## E. Collage and viewer (S7–S10; decisions 16–20)

- [ ] **E1 MUST (decision 16)** `AlbumScreen(conversationId, albumId, senderName, timestamp)` (new, C17), pushed with
  `MaterialPageRoute` and constructor args (no route extras). Theme background (light / dark / AMOLED), not forced
  black. App bar: back, title = sender (**You** on own), subtitle = **3 photos and 2 videos · 12:41**. It watches
  the album's rows, so a late item appears and a deleted one leaves; one row left → it pops to the chat.
- [ ] **E2 MUST (decision 17)** Layout = a pure function `albumLayout(List<double> aspects, double width, {gap = 2})
  → List<Rect>`, in index order: aspect ≥ 1.2 (landscape) → its own full-width row, height = width / aspect, at most
  2:1 crop; portrait or square → paired with the next item if that one is also portrait or square, side by side, widths
  in proportion to their aspects, one shared height; else alone, full width, at most 4:5. Tiles `BoxFit.cover`.
  Deterministic, unit-tested, no randomness.
- [ ] **E3 MUST** Collage tiles show the same per-item states as the bubble's tiles (D3). Thumbnails load as bubbles
  do; full files only in the viewer.
- [ ] **E4 MUST** Tap a tile → the pager viewer at that index. Long-press a tile → per-item menu (R19, C4a style):
  **Reply**, **Select**, **Delete for me**, **Delete for everyone** (own, online only, offline hint as today). Delete
  asks the existing R20 **Delete message?**.
- [ ] **E4a MUST (decision 27, user 2026-11-01)** **Select** in the collage: it opens selection mode with that tile
  selected. The app bar becomes the chat's selection bar look (✕ **Exit selection**, **2 selected**, delete icon
  **Delete selected**, 38% and disabled at 0 selected). Tap or long-press a tile toggles it; tiles never open the
  viewer while selecting. Selected = a 3dp accent ring inside the tile + a 24dp accent disc with an `onAccent` ✓
  top-right; unselected = an empty white ring disc on 50% black. Android back exits selection first.
- [ ] **E4b MUST** Delete selected: when every selected item is your own → an R19 sheet (C4a, no header) with **Delete
  for me** and **Delete for everyone** (online only, the existing offline hint); otherwise straight to delete for me.
  Delete for me = wave 4's `confirmAndDeleteForMe` (**Delete 3 messages?** / **These messages will be deleted for
  you only.**; one item → the existing single copy). Delete for everyone = R20 **Delete 3 messages?** / **These
  messages will be deleted for everyone in this chat.** (one item → the existing single copy), then the existing
  delete-for-everyone call per item. After a delete, selection ends; one item left → the screen pops (E1).
- [ ] **E4c MUST** Semantics: tiles in selection mode are buttons **Photo 3 of 5, selected** / **not selected**; the
  count is a live region. Reduced motion: the ring and disc switch with no animation. 360×200%: **20 selected** fits
  the bar (one line, scale down).
- [ ] **E5 MUST (decision 18)** Viewer = Page 9's viewer split into `MediaViewerPage` (one item: zoom layer, clamp,
  double-tap, video controller, loading / errors) and a shell (system UI, chrome auto-hide, top bar, swipe-down)
  hosting a `PageView`. One item = a pager of one, no counter: **identical to today** (existing viewer tests unedited).
- [ ] **E6 MUST** Paging only at fit: while the current page's scale > 1.01 (the same test swipe-down uses) the
  `PageView` is `NeverScrollableScrollPhysics`; back at fit it pages again. Swipe-down closes only at fit (Page 9 C4).
- [ ] **E7 MUST** Top bar shows the sender and time as today plus a counter **2 of 5** (tabular figures). Chrome
  visibility is shared across pages (paging does not show or hide it). Save and Share act on the current item
  (Page 9 F, unchanged copy).
- [ ] **E8 MUST** Video: one controller at a time. Leaving a page pauses and disposes its controller; arriving at a
  video page behaves as opening it today. The lifecycle pause rule (learning) holds on every page.
- [ ] **E9 MUST (decision 19)** The full file loads for the **current** page only; neighbours show their thumbnail
  with R3a until they become current. No prefetch.
- [ ] **E10 MUST** Hero: tag `mediaHeroTag(serverId)` per item. The opened item flies in from the collage tile;
  closing flies back to the current item's tile when it is built, else no flight. Reduced motion: no Hero,
  zero-duration push and page changes jump (`jumpToPage`).
- [ ] **E11 MUST (decision 20)** Swiping is **within the album only**. Swiping across all of a chat's media stays
  out of scope (Page 9 decision 6 for single items is unchanged).

## F. Actions, quotes and labels (S9; decisions 15, 21–24)

- [ ] **F1 MUST** Album long-press menu (C4 variant, same quick reactions row):
  React → the cover · **Reply** → quotes the cover · **Select** → the album is one selectable unit (its N rows) ·
  **Star** / **Unstar** → every row (decision 21) · **Pin** / **Unpin** → the cover · **Delete for me** → every row ·
  **Delete for everyone** → every own row, online only · **Cancel sending** (B9). No Copy.
- [ ] **F2 MUST** Deleting the album reuses wave 4's multi-delete confirm (**Delete 5 messages?**, its existing bodies), confirm
  **Delete**; for everyone, the E4b copy.
- [ ] **F3 MUST (decision 22)** Album label = `albumLabel(photos, videos)`: **5 photos** · **2 videos** · **3 photos
  and 2 videos** (singular **1 photo** / **1 video**). Counts = visible rows from `rowsInAlbum`.
- [ ] **F4 MUST** A reply quote of an album row shows the cover's 36px thumbnail (existing) and the album label
  instead of **Photo** / **Video**. The quote of a single item replied to from the collage shows **Photo** / **Video**
  as today. Old clients show the cover photo quote (their behaviour, unchanged).
- [ ] **F5 MUST (decision 23)** Home preview and the pinned banner show the album label when the latest / pinned row
  is in an album.
- [ ] **F6 MUST (decision 24)** Unread counts and notifications are unchanged (each item counts; the conversation's
  one notification is replaced per item, fact 8).
- [ ] **F7 MUST (decision 21, user 2026-11-01)** **Star** on an album stars every row (one star record per row, the
  existing star path, ids only) and shows the album as starred; **Unstar** clears every row. Starred
  (`starred_messages_screen.dart`) shows an album's starred rows as **one card**: the cover's thumbnail and the album
  label (**5 photos**), the existing **Tap to jump to message** line. Tapping it uses the existing jump (pop, then
  `onJump`), which lands on the album item (A6) and flashes it. Rows whose local row is missing (not loaded yet) show
  as single cards, as today.

## G. Motion, a11y, large text

- [ ] **G1 MUST** Reduced motion: no Hero, zero-duration routes, `jumpToPage`, no arc sweep (C15 rule), R11 parks.
- [ ] **G2 MUST** 360×640 at `textScaler 2.0`, system font and Plus Jakarta Sans: the album bubble (pills scale down
  inside fixed slots), the collage app bar (title and subtitle one line, ellipsis), the editor strip, the mixed
  quality sheet (the sheet-row learning) and the pager's top bar fit with no overflow.
- [ ] **G3 MUST** TalkBack: D7's labels; the strip's thumbnails are buttons **Item 2 of 5, selected** with **Remove**
  as its own button; the collage tiles are buttons **Photo 3 of 5**; the pager announces **Photo 2 of 5** on page
  change (`SemanticsService.announce`, or a live region on the counter).

## H. Copy (verbatim)

New: `Photos and videos` · `Only the first 20 were added.` · `Quality` · `Photos up to 1280px, videos 720p · kept 60
and 30 days` · `Photos up to 2560px, videos 1080p · kept 30 and 15 days` (numbers from constants) · `Preparing 2 of 5`
· `1 item is over 100 MB and was left out.` · `2 items are over 100 MB and were left out.` · `Remove` · `Cancel
sending` · `These messages will be deleted for everyone in this chat.` · `5 photos` · `1 photo` · `2 videos` · `1 video` · `3 photos and 2 videos` · `2 of 5` ·
`Album, … from …` (semantics) · `Item 2 of 5` (semantics).
Reused: `Upload cancelled` · `Too big to send. The limit is 100 MB.` · `Discard changes?` · `Delete message?` ·
`Delete` · `Reply` · `Delete for me` · `Delete for everyone` · `Available online` · every media-send state caption.
No `$e` in any of it.

## K. Hygiene and gates

- [ ] **K1 MUST** NEW grep test **inside `main()`** of `test/grep_gates_test.dart`, "albums": in the new files
  (`album_bubble.dart`, `album_screen.dart`, `album_layout.dart`, `media_pager` / page files), none of `Colors.`,
  `Color(0x`, `LinearGradient`, `SnackBar(`, `CircularProgressIndicator`, `LinearProgressIndicator`,
  `showModalBottomSheet`, `$e` / `e.toString()` outside `debugPrint`, `extra:`; in `lib/`, no `pickMultiImage`
  (one picker call, B1). Prove RED once, then GREEN.
- [ ] **K2 MUST** Registry C16 + C17 added, C14 and the viewer row amended (below), same commit.
- [ ] **K3 MUST** No `ref` in any `dispose()`; the pager's page controller and video controllers are disposed in
  their own state's `dispose` without `ref`; no `await ref.read(<autoDispose>.future)` without a listener.

## Registry amendments (same commit, L2)

| ID | Amendment |
|---|---|
| C16 | `AlbumBubble(messages, isMine, …)`: one bubble for 2–20 photos/videos sent together. Horizontal tiles 180dp high, width by aspect clamped so the next one peeks; fixed count pill + time pill; one expiry badge (earliest); per-tile states = the single media bubble's rules; no swipe-to-reply; reactions = the cover's. |
| C17 | `AlbumScreen(conversationId, albumId, senderName, timestamp)` + `albumLayout(aspects, width)`: the collage. Landscape full row (≤2:1), portrait/square paired, a lone portrait ≤4:5; theme background; tap → pager, long-press → per-item Reply / Select / Delete; Select mode (selection bar, ring + ✓ disc) deletes several at once. |
| (amend C14) | `MediaEditScreen` album mode: a 56dp item strip, per-item edits, Remove, Send returns a list. |
| (amend viewer) | `MediaViewerScreen` = shell + `MediaViewerPage` in a `PageView`; one item = a pager of one; paging only at fit; counter **2 of 5**; full file for the current page only. |

## Test gates (mandatory)

Bubble / screen tests override `mediaFileProvider`, `mediaFullLocalProvider`, `mediaBlobStatusProvider`,
`isOnlineProvider` and `uploadProgressProvider`; repo tests use the in-memory drift database and a fake PocketBase
client (media-send's seams). Semantics via `tester.getSemantics`. Large text = 360×640, `textScaler 2.0`, system font
and `PlusJakartaSans`.

- [ ] NEW `test/chat/album_grouping_test.dart`: same `albumId` + sender → one item at the earliest row's position ·
  another message between two rows → still one album · different sender with the same `albumId` → not grouped · one
  visible row → a normal `_MsgItem` · tiles in `albumIndex` order · run flags treat the album as one · `_findFlatIndex`
  of a middle row → the album item · a split page → the loaded part shows.
- [ ] NEW `test/media/album_layout_test.dart`: landscape → full row, ≤2:1 · two portraits → one row, shared height ·
  portrait then landscape → portrait alone ≤4:5, then the landscape row · square + portrait pair · unknown aspect → 1.0
  · 20 items: every rect inside the width, no overlap, index order top-to-bottom, left-to-right.
- [ ] NEW `test/offline/album_send_test.dart`: 3 sends → 3 rows, `albumId` = item 0's id, index 0/1/2, create bodies
  carry both fields · album sends start no upload of their own; one resume uploads them **one at a time** in index
  order (max concurrent = 1) · offline on item 1 → items 2… untouched, all `pending`; reconnect → all sent, in order ·
  item 1 → 413 `failed` → item 2 still uploads · Cancel sending → unsent rows gone, sent rows stay · re-run after a
  duplicate id sends the same album fields · `_companionFromRecord` maps both fields; a record without them → nulls ·
  migration v12 → v13 keeps rows, columns null.
- [ ] NEW `test/chat/album_bubble_test.dart`: tiles for 2 and 20 items, the next tile peeks · count pill + one time
  pill + earliest expiry badge · each D3 state on a tile (reusing media-send's fixtures) · no `SwipeToReply` ancestor
  · tap tile → `AlbumScreen`; tap a tile's ✕ → cancel that item only · long-press → album menu with F1's rows (and
  Cancel sending only while unsent) · reactions bar keyed by the cover · semantics labels (D7) · 360×200% + Jakarta
  · no `Text` coloured `t.accent` / `t.error`.
- [ ] NEW `test/chat/starred_album_test.dart`: starring an album writes one star per row; unstar clears all · Starred
  with 3 starred rows of one album + 1 single → 2 cards, the album card reads **3 photos** with the cover thumbnail ·
  tapping it pops and calls `onJump` with an album row, and `_findFlatIndex` lands on the album item · a starred row
  whose siblings aren't loaded → a single card.
- [ ] NEW `test/media/album_screen_test.dart`: rects from `albumLayout` · title / subtitle text · tap tile → pager at
  that index · long-press → Reply / Select / Delete for me / Delete for everyone (offline: dimmed + hint) · a deleted row
  leaves; one left → pops · Hero tags per item; reduced motion → no `Hero` · 360×200% + Jakarta · **Select:** long-press
  → Select → bar reads **1 selected**, tap two more → **3 selected**, a tap does not open the viewer, tap again
  deselects; 0 selected → delete disabled; back exits selection before popping · all own → sheet with both deletes;
  one theirs → straight to the delete-for-me confirm (**Delete 3 messages?**); offline → Delete for everyone dimmed
  with **Available online** · confirm deletes exactly the selected rows (count delete calls) and ends selection ·
  semantics **selected** / **not selected** via getSemantics · 20 selected at 360×200% fits.
- [ ] NEW `test/media/media_pager_test.dart`: one item → no counter, same tree as before (existing viewer tests also
  green unedited) · swipe left at fit → page 2, counter **2 of 5**, announced · zoomed in (scale 2) → a horizontal drag
  pans, does not page · back at fit → pages · leaving a video page disposes its controller · Save acts on the current
  item · only the current page requests the full file (count `mediaFileProvider(full)` reads) · reduced motion →
  `jumpToPage`.
- [ ] NEW `test/media/media_edit_album_test.dart`: 3 items → strip with 3 thumbnails, first selected · Crop on item 2
  keeps item 1 unchanged · Remove down to 1 → strip hidden, single editor · GIF item → no tools + caption · close with
  an edit → R20 · Send returns 3 results in order · 360×200% + Jakarta.
- [ ] AMEND `test/chat/attach_sheets_test.dart` (the one allowed edit, decision 6): four rows, **Photos and videos**
  returns `gallery`; the mixed quality sheet's subtitles come from the constants; all-photo and all-video sheets
  unchanged.
- [ ] `test/grep_gates_test.dart`: K1 inside `main()`; RED once, then GREEN, both in the work log.
- [ ] Existing tests stay green **unedited**: `media_viewer_screen_test`, `media_viewer_video_test`,
  `media_entry_points_test`, `media_edit_screen_test`, `media_bubble_states_test`, `reply_quote_expired_test`,
  `run_grouping_test`, `message_menu_sheet_test`, `reaction_bar_test`, every `test/offline/media_*`.
- [ ] Count: the work log records **baseline + N = total**.
- [ ] Function-level diff vs HEAD of every frozen method in an edited file: empty.
- [ ] Full suite green · analyze 0 errors · `git diff --check` clean · `trail check` clean · hand-written v13 codegen
  committed with the table change.

## Device check list (phase 2, M52 + Redmi S2; you do every send)

1. **Older client first (before installing the new build on the second phone):** send an album of 4 from the new
   build → the old build shows 4 normal bubbles, each opens, nothing errors.
2. Pick 5 photos and 2 videos in **Photos and videos** → the editor shows a strip of 7; crop item 2, trim the first
   video, remove item 4 → Send → one **Quality** sheet → **Preparing 1 of 6** … → one album bubble with 6 tiles.
3. The tiles upload one by one, each ring filling in order; the ticks stay a clock until the last is sent. The other
   phone shows one album that fills in.
4. Airplane mode mid-album → the unsent tiles show "Waiting for connection"; network on → they finish in order.
5. Tap ✕ on one sending tile → only that tile goes. Long-press → **Cancel sending** → the unsent ones go, the sent
   ones stay; two left → still an album; one left → a normal photo bubble.
6. Scroll the album sideways in the chat: smooth, no reply swipe fires; vertical chat scroll still works when the drag
   starts on the album.
7. Tap a tile → the collage: landscape photos full width, portraits in pairs; the tapped tile visible.
8. Tap a collage tile → fullscreen at that item; swipe through all of them; a video plays and pauses when you swipe
   away; **2 of 5** updates; Save saves the one on screen.
9. Zoom into a photo, drag sideways → it pans inside the photo and does **not** change page; back to fit → swipes
   again; swipe down at fit closes. (Gesture arenas: widget tests can't prove this.)
10. React to the album, reply to it (quote shows the cover and **5 photos**), star it (Starred shows **one** card with **5 photos**;
    tapping it jumps to the album and flashes it), pin it (banner says **5 photos**; tapping it jumps to the album), delete it (**Delete 5 messages?**).
11. From the collage, long-press one item → Reply → the quote shows **Photo**; Delete for everyone → it leaves the album
    on both phones.
11a. In the collage, long-press → **Select**, tap two more → **3 selected** → delete → **Delete for everyone** → they
    leave the album on both phones; with one item left the collage closes and the chat shows a single photo.
12. Home row shows **3 photos and 2 videos** for an album as the latest message.
13. Kill the app mid-album, reopen → the rest uploads by itself, in order.
14. Largest text + Plus Jakarta Sans, 360dp if available: bubble, collage, editor strip, quality sheet, pager top bar.
15. Reduce animations: no Hero, pages jump; TalkBack reads the album, a tile, the strip and the page counter.
16. An expired or can't-decrypt item inside an album shows its caption on its tile and in the collage; the others work.

## Out of scope (do NOT build on this page)

Everything still in ⛔ · documents and voice notes in albums · captions on albums · swipe across a whole chat's media
(decision 20) · share-into-app (12.1) beyond S13's hooks · server push text per album · unread-as-one · per-item
reactions or stars from the collage · Select all, or Save / Share of a selection · prefetching neighbours · Save all / Share all · Media & docs grouping · mascots.

---

## Diff vs current implementation

| # | Area | Today (file:line) | Spec | Checklist |
|---|---|---|---|---|
| 1 | Picking | one photo or one video per pick (`mi:362-397`), two library rows (`as:22-24`) | one **Photos and videos** row, up to 20 mixed (`pickMultipleMedia`) | B1–B3 |
| 2 | Editing several | n/a | editor strip, per-item edits, Remove | B4 |
| 3 | Quality | one sheet per item type (`as:34-66`) | one sheet per album; mixed variant | B5 |
| 4 | Upload order | each send starts its own upload at once (`rep:1753`) | album sends serial through the resume pass (`rep:2100-2121`) | B7, B8 |
| 5 | Grouping data | none (`mt:11-70`, `rep:1873-1886`) | `album_id` + `album_index`, server and drift v13 | A1, C1–C3 |
| 6 | Chat list | one bubble per row (`cs:334-357`) | album item at the earliest row; late rows join | A2–A7 |
| 7 | Bubble | single photo/video bubble | `AlbumBubble`, sideways tiles, count pill, earliest expiry | D1–D3 |
| 8 | Reply swipe | on every bubble (`mb:379`) | not on albums | D4 |
| 9 | Opening | viewer for one item (`ib:47-64`) | collage → pager | D5, E1–E4 |
| 10 | Viewer | one item, 821-line state (`mv:76-821`) | page + shell in a `PageView`; paging only at fit | E5–E10 |
| 11 | Actions | per row (`cm:379-455`) | album menu: reaction/reply/pin on the cover, star/delete on all, Cancel sending | F1, F2 |
| 12 | Labels | **Photo** / **Video** (`rq:80-81`, banner, home) | **3 photos and 2 videos** | F3–F5 |
| 13 | Older clients | n/a | N separate bubbles, unchanged | A8 |
| 14 | Starred | one card per starred row; tap jumps to it (`starred_messages_screen.dart`) | an album = one card (**5 photos**); tap jumps to the album | F7 |

---

### Deferred decisions (you decide at spec review; default = recommended)

1. **A shared id on each message** (`album_id` = item 0's record id, `album_index` = position), on the server and in
   drift. Survives offline sends, resume, Try again and restarts; exact order; no false merges. Costs a live schema
   change (W1) and a hand-written drift v13. Alternative A: **group by sender + a time window** (e.g. consecutive
   photos/videos from one sender within 60 s): no schema, works on old messages, but two separate photos sent a minute
   apart merge, an album resumed after a drop splits, and order depends on upload timing. Alternative B: **the id
   inside the encrypted body** (hidden from the server): the decrypted body is a session cache, never stored, so the
   list builder could not group without touching the frozen decrypt pass; and the server already sees the same sender
   sending N records in the same minute, so the gain is small. Not recommended.
2. **Unfreeze narrowly** (⛔ "Unfrozen" list): the send path gains two fields and a no-autostart flag, ingest copies
   two fields, the viewer is split into page + shell. Containment: function-level diff, existing viewer tests
   unedited, Claude implements B–C, one fresh-context review, device items 1, 3–5, 8–9. Alternative: none that ships
   albums.
3. **Late rows join the album** at its earliest row's position, even if another message landed between (a slow
   upload, a Try again much later). Alternative: group adjacent rows only (an interrupted album splits into two).
4. **Older app versions see N separate bubbles.** No compatibility shim. Alternative: none needed.
5. **At most 20 items per album** (user, 2026-11-01). The picker's `limit: 20`. Watch: 20 videos upload one at a
   time, so a big album takes a while to fill in on the other phone; the bubble and collage scroll further.
6. **One merged row "Photos and videos"** replacing Photo library + Video library (the system picker shows both
   anyway; a mixed album needs one call). The only existing test edited is `attach_sheets_test.dart`. Alternative:
   keep both rows, each multi-pick of its own type (no mixed albums).
7. **The editor opens for albums too, with a strip** (crop / draw / trim any item, remove items). Alternative: albums
   skip the editor and send as picked (smaller; editing then needs single sends).
8. **One quality choice per album**, a mixed sheet when photos and videos are mixed. Alternative: ask once per type
   (two sheets for a mixed album).
9. **Compress everything first, then the album appears whole**; the floating row says **Preparing 2 of 5** and its
   cancel drops the whole album. Alternative: each item appears in the bubble as soon as it is compressed (the album
   grows while you watch; cancel becomes per item earlier).
10. **Upload one item at a time in pick order** (the resume pass), so the other phone fills the album in order and a
    weak link isn't split ten ways. Alternative: parallel uploads (faster on good Wi-Fi, scrambled arrival order).
11. **Progress and ✕ per tile, plus "Cancel sending" for the rest** in the long-press menu. Alternative: one album-level
    progress ring and one ✕ (hides which item is stuck).
12. **Sideways tiles at 180dp height, the next tile peeking** (the user's mock). Alternative: a fixed 2×2 grid preview
    with "+3" on the last cell (no horizontal gesture at all, and swipe-to-reply keeps working).
13. **No swipe-to-reply on albums** (the sideways scroll owns horizontal drags; Reply is in the long-press menu).
    Alternative: reply swipe from the bubble's time row only (a narrow target, easy to miss).
14. **Tap a tile → the collage first**, as you described. Alternative: tap a tile → straight to fullscreen at that
    item, the count pill → the collage.
15. **Album reactions live on the cover** (the lowest-index visible item): old clients see them under the first
    photo. A reaction an old client puts on another item doesn't show on the album. Alternative: merge all items'
    reactions under the album (new combined bar, more code).
16. **The collage uses the app theme** (light / dark / AMOLED), since it's a list you scroll; the viewer stays black
    (Page 9 decision 1). Alternative: black like the viewer.
17. **Collage rules:** landscape full width (≤2:1), portrait/square in pairs, a lone portrait ≤4:5, in pick order.
    Alternative: a justified-rows layout (rows filled to a target height, like a photo gallery): denser, less
    predictable.
18. **The viewer becomes a pager of pages**; a single item is a pager of one (one code path). Alternative: a separate
    album pager next to the untouched single viewer (two viewers to keep in sync).
19. **Full file for the current page only** (data and battery; thumbnails show instantly). Alternative: prefetch ±1
    neighbour.
20. **Swipe within the album only.** Swiping across a whole chat's media (Page 9 decision 6 in full) stays a separate
    task. Alternative: in scope now (needs a chat-wide media list source).
21. **Star = the whole album** (user, 2026-11-01): every item gets a star; Starred shows the album as one card, and
    tapping it jumps to the album in the chat (F7).
22. **Labels say what's inside**: **5 photos** / **2 videos** / **3 photos and 2 videos**. Alternative: **Album · 5
    items**.
23. **Home preview and pinned banner use that label.** Alternative: keep **Photo** / **Video** there.
24. **Unread counts and notifications stay per item** (the server hook sends one push per message; the phone replaces
    one notification per chat). Alternative: a server hook change so an album pushes once (live hook edit, separate).
25. **Live read R1 before phase 2, write W1 during it**, each with your OK at the time. Alternative: none (the fields
    must exist before an album can be sent).
26. **Hooks only for 12.1** (S13): the album send takes a list of files, not picker results, and the editor's album
    mode takes files, so share-in with several photos lands in the same flow. No share-in code here.
27. **Select inside the collage** (user, 2026-11-01): pick several items and delete them (for me, or for everyone when
    they're all yours). Selection only deletes; Save / Share several stay out of scope. Needs wave 4's multi-delete
    confirm committed first (it lives uncommitted in this checkout today).
