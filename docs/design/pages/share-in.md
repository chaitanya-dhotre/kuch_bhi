# Share into the app: photos, videos, files and text from other apps (acceptance checklist)

Date: 2026-11-02. Backlog **12.1**. Visual ground truth: **`docs/design/pages/share-in.html`** (sections S1–S10,
numbered; S1 = the four entry flows; S3 = the **Send to** picker in every state; S6 = how a mixed share is split;
S7 = receive plugin comparison; S8 = where the shared files live and when they are deleted; S10 = diff summary).
Authority: `docs/design/00-foundation.md` (tokens/laws) → `docs/design/10-registry.md` (shared pieces) → this
checklist. Page letters A–K are page-local; decisions are numbered (bottom). Line refs as of `5580d1e`:
`mf` = `android/app/src/main/AndroidManifest.xml`, `ma` = `android/app/src/main/kotlin/com/chai/kuch_bhi/MainActivity.kt`,
`mi` = `lib/features/chat/widgets/message_input.dart`, `as` = `lib/features/chat/widgets/attach_sheets.dart`,
`cs` = `lib/features/chat/screens/chat_screen.dart`, `rt` = `lib/core/router/app_router.dart`,
`fcm` = `lib/services/fcm_service.dart`, `hs` = `lib/features/home/screens/home_screen.dart`,
`cp` = `lib/features/home/providers/conversations_provider.dart`, `mbs` = `lib/infrastructure/media/media_blob_store.dart`,
`mus` = `lib/services/media_upload_service.dart`, `rep` = `lib/infrastructure/repositories/message_repository_impl.dart`,
`crg` = `lib/features/chat/chat_run_grouping.dart`, `ac` = `lib/core/constants/app_constants.dart`.

**Starting point (audited 2026-11-02, `trail ask/skeleton/grep` + `sed -n` ranges; no code run on a phone, no live
PocketBase read).** Suite baseline at `5580d1e` (2026-11-02, clean `lib/` and `test/`): **899/900**. The one failure,
`send_fetch_char_test.dart` "send persists optimistic pending row before the network ack", passes 3/3 when run alone:
a timing flake under full-suite load (its insert log lands after the `expect`), not a regression. A sibling session
("multi-select that works") may land first, so phase 2 re-runs the baseline and records it.

**Facts, confirmed in code (not assumed).**
1. **Nothing receives a share today.** `mf:34-44` has only `MAIN/LAUNCHER` and the `VIEW kuchbhi://` deep link; no
   `SEND` / `SEND_MULTIPLE` filter, so kuch_bhi never shows in Android's share sheet. The activity is
   `launchMode="singleTop"` with `taskAffinity=""` (`mf:19-20`).
2. **No receive plugin is installed.** `share_plus` (installed) only sends. `MainActivity` already hosts one small
   `MethodChannel` (`kuch_bhi/clipboard`, `ma:13-45`), so a second channel for shares follows an existing pattern.
3. **The in-app send paths are three methods on the composer's state**, each taking local files:
   `_sendSinglePicked(File, type)` = editor → quality sheet → one bubble (`mi:425-464`);
   `_sendAlbumPicked(List<XFile>)` = album editor → one quality sheet → album (`mi:486-560`, 12.5);
   `_sendDocument(File)` = straight send, no confirm (`mi:779-800`). `_mediaTypeOf` sorts photo vs video by MIME, then
   extension (`mi:466-482`). The album flow already handles over-100 MB items (**1 item is over 100 MB and was left
   out.**) and the 20 cap (**Only the first 20 were added.**, `mi:376-388`, `ac:18`).
4. **A document's name on the other phone is the file's own name** (`fileName: p.basename(f.path)`, `rep:1711`), and
   the send **moves** the file into the blob store (13.8). A shared document must therefore be copied under its real
   display name, and its copy is gone after the send. Photos and videos are re-encoded into new temp files; their
   shared copies stay behind unless deleted.
5. **The router decides where a fresh start lands** (`rt:88-133`): not signed in → `/login`; key sync loading →
   splash; `needsRestore` → `/backup-pin/restore`; `needsSetup` → `/backup-pin/setup`; `keyOk` → `/home`.
   A chat is opened with `context.push(AppRoutes.chat, extra: conversation)` (`rt:182-187`, `hs:543`, `fcm:311`).
6. **The notification tap is the precedent for "open a chat from outside"** (`fcm:284-312`): wait for the router to
   leave splash, avoid stacking the same chat twice. Its wait gives up after 12 s (`fcm:366-374`), too short for a
   share that waits through sign-in or a key restore.
7. **Who may send is decided inside the chat** (`cs:568-579`): a group you left, a group whose key hasn't arrived,
   or an admins-only group when you're not an admin turn the composer off with a banner.
8. **The home list is `conversationsProvider`** (`cp:13`), drawn with `_ConversationTile` → R6 `ChatTile`
   (`hs:398`, `hs:1009`); home search filters by name (`hs:455-463`) and shows **No chats match ‘x’.**
9. **Logout already wipes decrypted media** from the temp directory (`wipeMediaCache`, `mbs:69-78`, the media-send
   learning). Android's `cacheDir` is that same temp directory.
10. **Android re-delivers the original intent** when an app killed in the background is reopened from Recents (the
    intent then carries `FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`). Without a check, an old share would come back.

**Routing.** Spec: Claude (this session). Phase 2: the Kotlin channel, the manifest and the pending-share service
(B, C) touch app start and the router, so **Claude implements B–C**; the picker and the composer hand-off (D, E) are
small and reuse registry pieces, so **Claude does them too** (decision 22). The grading pass is a fresh-context
reviewer, never the implementer.

**Pass criteria (page complete when):** all MUSTs ✓ · `flutter analyze` 0 errors · `flutter test` green (baseline
re-run at phase 2 start, plus the new tests; no existing test edited) · test-gate files below green ·
`git diff --check` clean · K1 grep gate green (proved RED once) · `trail check` clean · frozen-method diff vs HEAD
empty · `flutter build apk --debug` succeeds · fresh-context review with no open BLOCK, findings in
`share-in-work-log.md` · device captures of the device-check list · user device PASS (no commit without it).

**Spec status: user PASS 2026-11-02; every deferred decision = its default (1–22).** Phase 2 goes in a fresh session.

**Live PocketBase.** None needed: shares use the existing send paths and fields. Ask the user before any read anyway.

**Status key:** `[x]` implemented AND verified by code/tests or recorded device evidence; `[ ]` pending.

---

## ⛔ Frozen (read first: a breach here is an automatic FAIL)

E2E and key code anywhere (`encryption.*`, `_encryptFileBytes`, `_getConvKey`, the store's download → verify →
decrypt section), the whole send path in `rep` (`sendMediaMessage`, `_uploadMediaMessage`, the resume pass, cancel),
`mus` compression and re-encode (GPS strip), the editor (C14) and its album mode, the quality sheet's values, the album
flow's compression loop `_prepareAndSendAlbum`, the voice recorder, receipts, the decrypt pass, the SSE handler, the
outbox worker, the router's redirect rules (`rt:88-133`), the existing clipboard channel in `ma`.

**Unfrozen by this page, and only these (decision 2):**
- `mf`: two intent filters added, `launchMode` changed (decision 2). Nothing else in the manifest.
- `ma`: a second channel `kuch_bhi/share` next to the clipboard one, plus `onNewIntent`. The clipboard handler is
  byte-identical.
- `mi`: `_onAttachPressed`'s callers untouched; a new `_runShare(ShareInPayload)` entry that calls the existing
  `_sendSinglePicked` / `_sendAlbumPicked` / `_sendDocument` **unchanged**, and an `initState` / listener hook that
  picks up a share handed to this chat.
- `mbs` / logout: the existing wipe also deletes `share_in/` (one line, or a sibling helper called from the same place).
- New files: `lib/services/share_in_service.dart` (channel, payload, pending state), `lib/features/share/share_target_screen.dart`
  (the picker), `lib/features/share/share_payload.dart` (pure sorting / summary helpers).

When an edited file holds frozen code (`mi`, `ma`), every other method in it is diffed against HEAD **at function
level** and must be byte-identical. Read for context, do not re-solve:

- `.trail/learnings/2026-10-31-a-media-send-keeps-one-id-chaitanya.md` (one id from pick to sent; logout wipes media)
- `.trail/learnings/2026-11-01-photos-sent-together-are-grouped-by-chaitanya.md` (album id; uploads start at once)
- `.trail/learnings/2026-10-30-a-send-that-fails-gives-the-chaitanya.md` (a failed send gives the input back)
- `.trail/learnings/2026-10-31-a-screen-never-uses-ref-in-chaitanya.md` (no `ref` in dispose; a draft belongs to one chat)
- `.trail/learnings/2026-10-31-reading-an-auto-disposed-provider-s-chaitanya.md` (never await an autoDispose future without a listener)
- `.trail/learnings/2026-10-29-user-photos-only-load-from-a-chaitanya.md` (every uploaded photo is re-encoded to drop GPS)
- `.trail/learnings/2026-10-29-a-sheet-row-s-offline-hint-chaitanya.md` (rows at 200% text)

## A. Receiving (S1, S2, S7; decisions 1, 2, 18)

- [ ] **A1 MUST** `mf` gains two filters on `MainActivity`: `SEND` and `SEND_MULTIPLE`, each with category `DEFAULT`
  and `mimeType="*/*"`. kuch_bhi then shows in the share sheet for photos, videos, files, text and links.
- [ ] **A2 MUST (decision 2)** `launchMode="singleTask"` (was `singleTop`; `taskAffinity=""` stays). A share while the
  app runs reaches the running app through `onNewIntent`; there is never a second app instance in the sharing app's
  task.
- [ ] **A3 MUST (decision 1)** No new dependency. `MainActivity` gets a channel `kuch_bhi/share` with:
  `takeShare()` → `{items: [{uri, mime, name, size}], text}` or `null`, consumed once (a second call returns `null`);
  `copyShared(uri, name, maxBytes)` → the copied path, or an error code `too_big` / `unreadable`; `clearShared()` →
  deletes `cacheDir/share_in/`. On `onNewIntent` with a share it calls the Dart method `shareArrived` (no data; Dart
  then calls `takeShare`).
- [ ] **A4 MUST** `takeShare` reads `EXTRA_STREAM` (one URI or a list) and `EXTRA_TEXT`. Per item: MIME from
  `contentResolver.getType`, else the intent's type, else by extension; `name` from `OpenableColumns.DISPLAY_NAME`
  (else `shared_<n>.<ext>`); `size` from `OpenableColumns.SIZE` (else `-1`). Reading these columns copies nothing.
- [ ] **A5 MUST (decision 18)** An intent with `FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY` is ignored (Recents never
  replays an old share). After `takeShare`, the activity's intent is replaced with a plain `MAIN` one.
- [ ] **A6 MUST** `copyShared` runs off the main thread (an executor), streams through a 64 KB buffer, stops and
  deletes the partial file once it passes `maxBytes` (100 MB from `ac:17`), and writes to
  `cacheDir/share_in/<n>/<safe name>`: one folder per item so two files called `IMG_0001.jpg` never overwrite each
  other, and the real name reaches the other phone (fact 4). Safe name = the display name with `/`, `\` and leading
  dots removed, at most 120 characters.
- [ ] **A7 MUST** The Kotlin side never logs a URI, file name, size or the shared text. Logs say counts and MIME
  families only (`[Share] 3 items: image, image, video`).
- [ ] **A8 MUST** The `VIEW kuchbhi://` filter and the clipboard channel behave exactly as today.

## B. Waiting until the app can send (S1; decisions 15, 16)

- [ ] **B1 MUST** `ShareInService` (new, `lib/services/share_in_service.dart`) calls `takeShare` once at start and on
  every `shareArrived`, and holds the result in a `pendingShareProvider` (`StateProvider<ShareInPayload?>`). Nothing
  is copied yet.
- [ ] **B2 MUST** When a share is pending and the router's location is `/home` with `encryptionSyncProvider` =
  `keyOk`, the picker is pushed on the root navigator, once. The service listens to the router (its delegate or the
  existing refresh notifier); it does **not** poll with a give-up like `fcm:366-374`.
- [ ] **B3 MUST** Warm start on any other screen (a chat, Settings, the album collage, the editor): the picker is pushed
  on top of it. Back from the picker returns to that screen untouched (draft, editor state, scroll).
- [ ] **B4 MUST (decision 15)** Signed out: the share waits in memory; the login screen shows the toast
  **Sign in to share.** once. After sign-in, the restore or setup screen if the router sends there, then the picker.
  Logout or a sign-in that is abandoned and the app killed: the share is gone (nothing was copied).
- [ ] **B5 MUST** Key not restored yet (`needsRestore` / `needsSetup`): no toast; the picker opens right after the
  restore or setup reaches home.
- [ ] **B6 MUST (decision 16)** A second share while one is waiting or the picker is open replaces the first. An open
  picker updates its summary line to the new share.
- [ ] **B7 MUST** A share whose items are all unreadable and has no text → toast **Couldn't open what was shared.**
  and no picker.

## C. Sorting the share (S6; decisions 9, 12, 13, 14, 20)

- [ ] **C1 MUST** `share_payload.dart` (pure, unit-tested) sorts each item: `image/*` except `image/svg+xml` → photo
  (GIF and animated WebP stay photos and keep their format, media-send decision 12); `video/*` → video; everything
  else (PDF, audio, archives, APK, SVG, contacts) → document (decision 20). Unknown MIME → by extension with
  `_mediaTypeOf`'s video list, then the photo extensions `jpg jpeg png gif webp heic heif`, else document.
- [ ] **C2 MUST (decision 9)** At most **20** items per share (`ac:18`), counted in the order shared, before any copy.
  Extra items are dropped with the existing toast **Only the first 20 were added.**
- [ ] **C3 MUST** Items whose known `size` is over 100 MB are dropped **before** copying, with the existing album
  toasts **1 item is over 100 MB and was left out.** / **2 items are over 100 MB and were left out.**; if that leaves
  nothing, **Too big to send. The limit is 100 MB.** An unknown size is checked by `copyShared`'s byte limit (A6)
  and counts the same way.
- [ ] **C4 MUST (decision 12)** Order of sending in the chosen chat: photos and videos first (one → the single
  flow; two or more → the album flow), then each document in shared order, then the text into the composer.
- [ ] **C5 MUST (decision 13)** Text: `EXTRA_TEXT` goes into the chosen chat's composer, never sent by itself. An
  empty composer gets the text; a composer with a draft gets a new line and the text after it. The cursor ends after
  the text and the keyboard opens.
- [ ] **C6 MUST (decision 14)** `EXTRA_SUBJECT` is ignored (Chrome puts the page title there and the URL in the text).
- [ ] **C7 MUST** Summary line (`shareSummary`, pure): photos and videos only → the album wording through the same
  counting as `albumLabel` (`crg:75`): **1 photo** · **5 photos** · **2 videos** · **3 photos and 2 videos**;
  documents only → **1 file** / **3 files**; photos or videos plus documents → **6 items**; text only → **Text**, or
  **Link** when the trimmed text is one `http(s)://` URL. Text alongside items is not counted.

## D. The "Send to" picker (S3, S4; decisions 3–8, 11)

- [ ] **D1 MUST (decision 4)** `ShareTargetScreen` (new, C18) is a full page pushed with `MaterialPageRoute` (no route
  extras). App bar = R14 `pageAppBar` with a ✕ leading (**Cancel sharing**, 48dp), title **Send to**, and the summary
  line under it (13/18 inkSoft, one line, ellipsis).
- [ ] **D2 MUST** Under the bar: R8 `SearchField`, hint **Search chats**, filtering by name as home does (`hs:455-463`).
  Then R9 header **Chats** and one R6 `ChatTile` per conversation from `conversationsProvider`, in the home list's order
  (most recent first, pinned on top as on home). The tile's subtitle is the member count for a group (**5 members**) and
  empty for a direct chat; no unread badge, no time.
- [ ] **D3 MUST (decision 5)** Chats only. Friends without a chat yet are not listed.
- [ ] **D4 MUST** No search match → `No chats match ‘x’.` (home's string). No chats at all → R7 `EmptyState` **No chats
  yet** / **Add a friend first, then share again.**, no mascot.
- [ ] **D5 MUST (decision 3)** One chat per share. Tap a row → that chat.
- [ ] **D6 MUST (decision 6)** Before leaving the picker, the same rule as `cs:568-579` is checked for the tapped chat
  (extracted into one shared function `canSendIn(conv, …)` that `cs` then calls, so the rule stays in one place). A chat
  you can't send in → toast **You can't send messages in this chat.**, the picker stays.
- [ ] **D7 MUST (decision 7)** Copying starts **only after** a chat is tapped. While it runs the list is covered by a
  scrim on `t.bg` at 92% with R3a `BusySpinner` and **Opening 2 of 5** (one item: **Opening…**). Android back or ✕
  during the copy stops it (no further `copyShared` calls) and deletes what was copied.
- [ ] **D8 MUST** Items that fail to copy are left out with **1 item couldn't be opened and was left out.** /
  **2 items couldn't be opened and were left out.**; if nothing is left and there is no text → **Couldn't open what was
  shared.**, the picker stays.
- [ ] **D9 MUST** After the copy the picker is **replaced** by the chat (`pushReplacement` on the chat route with the
  conversation as `extra`), so Back from the chat goes where Back from the picker would have gone. If the chat is
  already the screen under the picker, the picker just pops (no second copy of the chat, as `fcm:289-292`).
- [ ] **D10 MUST** The ready share is handed to that chat through `chatShareProvider(conversationId)` (a family
  `StateProvider<ReadyShare?>`). The chat's composer reads and clears it on first build and on change (E1).
- [ ] **D11 MUST** ✕, Android back, or a swipe-back on the picker → `clearShared()` and the pending share is dropped.
  No toast.
- [ ] **D12 MUST** Offline: the picker works from the local list; the chat queues sends exactly as an in-app pick does.

## E. Handing off to the chat (S5; decisions 10, 11)

- [ ] **E1 MUST** `MessageInput` gains `_runShare(ReadyShare)`, run once per share after the first frame. It calls
  the existing methods unchanged: one photo/video → `_sendSinglePicked(file, type)`; two or more →
  `_sendAlbumPicked(items as XFile(path, mimeType))`; documents → E3; text → C5. A composer that can't send
  (`canSendMessages` false) never runs it (D6 should have caught it; this is the backstop) and clears the share.
- [ ] **E2 MUST (decision 10)** Shared photos and videos always go through the editor and the quality sheet, exactly
  like an in-app pick: same GPS strip and re-encode, same Normal / High values, same GIF rule.
- [ ] **E3 MUST (decision 11)** Shared documents ask once first: R20 `showConfirmDialog`, title **Send to Asha?**
  (the chat's name: the friend's name or the group name), body = the file name for one (**report.pdf**) or **3 files**,
  confirm **Send**, cancel **Cancel**. Send → `_sendDocument` for each, one after another, in shared order. Cancel →
  nothing sent, copies deleted.
- [ ] **E4 MUST** If the media part is cancelled (editor closed, quality sheet dismissed), the documents and text
  still follow (each part is its own choice).
- [ ] **E5 MUST** When `_runShare` ends (sent, cancelled, failed), the share's folders under `share_in/` are deleted.
  A document already moved by its send is simply not there any more.

## F. Privacy and cleanup (S8; decisions 7, 8)

- [ ] **F1 MUST** Shared files are copied **only** into the app's private `cacheDir/share_in/`; never to external or
  shared storage, never into the media store, never into `media_clear/`.
- [ ] **F2 MUST** Nothing is copied before a chat is chosen (D7); nothing over 100 MB is ever fully copied (A6, C3).
- [ ] **F3 MUST** `share_in/` is deleted: at the end of each share (E5), when the picker is closed (D11), at every app
  start before `takeShare` (no share can be in flight then), and at logout next to `wipeMediaCache`.
- [ ] **F4 MUST** No URI, file name or shared text in any `debugPrint` or Kotlin log (A7). Error toasts never include
  `$e`.
- [ ] **F5 MUST** Shared text lives only in the composer (the existing in-memory draft map, `mi:60`). It is not stored
  in drift or secure storage.
- [ ] **F6 SHOULD** Photos shared as photos lose GPS through the existing re-encode. A photo shared as a **file** (from
  a file manager with a non-image MIME) keeps its metadata, as an in-app **Document** pick does today. Noted, not changed.

## G. Motion, a11y, large text

- [ ] **G1 MUST** Reduced motion: the picker push uses zero duration; R3a parks as its static ring.
- [ ] **G2 MUST** 360×640 at `textScaler 2.0`, system font and Plus Jakarta Sans: the picker bar (title + summary one
  line each, ellipsis), search field, rows, empty state, the scrim's text and the confirm dialog fit with no overflow.
- [ ] **G3 MUST** TalkBack: the bar reads **Send to, 3 photos and 2 videos**; ✕ is a button **Cancel sharing**; rows
  keep R6's semantics; the scrim's **Opening 2 of 5** is a live region; the confirm dialog is R20's.

## H. Copy (verbatim)

New: `Send to` · `Cancel sharing` (semantics + tooltip) · `Search chats` · `Chats` · `No chats yet` · `Add a friend
first, then share again.` · `5 members` (R6 subtitle, the group's member count) · `You can't send messages in this
chat.` · `Opening 2 of 5` · `Opening…` · `1 item couldn't be opened and was left out.` · `2 items couldn't be opened
and were left out.` · `Couldn't open what was shared.` · `Sign in to share.` · `Send to Asha?` · `3 files` · `1 file` ·
`6 items` · `Text` · `Link` · `Send`.
Reused: `No chats match ‘x’.` · `Only the first 20 were added.` · `1 item is over 100 MB and was left out.` · `2 items
are over 100 MB and were left out.` · `Too big to send. The limit is 100 MB.` · `1 photo` · `5 photos` · `2 videos` ·
`3 photos and 2 videos` · `Cancel` · `Discard changes?` · `Couldn't send document. Try again.` · the quality sheets.
No `$e` in any of it. The share-sheet label is the activity label `kuch_bhi` (`mf:11`), unchanged (out of scope).

## K. Hygiene and gates

- [ ] **K1 MUST** NEW grep test **inside `main()`** of `test/grep_gates_test.dart`, "share-in": `pubspec.yaml` has no
  `receive_sharing_intent` / `share_handler` / `flutter_sharing_intent`; in `share_in_service.dart`,
  `share_target_screen.dart`, `share_payload.dart`: none of `Colors.`, `Color(0x`, `SnackBar(`,
  `CircularProgressIndicator`, `showModalBottomSheet`, `extra:` other than the chat route's conversation, `$e` /
  `e.toString()` outside `debugPrint`, and no `debugPrint(` line containing `path`, `name`, `uri` or `text`. Prove RED
  once, then GREEN.
- [ ] **K2 MUST** Registry C18 added, R6 amended (below), same commit.
- [ ] **K3 MUST** No `ref` in any `dispose()`; the service's channel handler is set once and survives hot restart
  without doubling (`setMethodCallHandler` replaces).

## Registry amendments (same commit)

| ID | Amendment |
|---|---|
| C18 | `ShareTargetScreen()` + `ShareInService` + `shareSummary(items)`: the **Send to** picker for shares from other apps. R14 bar with ✕ and the summary line, R8 search, R9 **Chats**, R6 rows in home order, R7 empty state, one chat per share, copy after the tap with **Opening 2 of 5**, then replaced by the chat; the chat's composer runs the existing single / album / document paths and puts text in the draft. |
| (amend R6) | `ChatTile` used without time or unread badge (picker rows); no new parameters if `time` and `unreadCount` already accept null / 0. |

## Test gates (mandatory)

The channel is faked with `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler`
on `kuch_bhi/share`; screen tests override `conversationsProvider`, `authProvider`, `encryptionSyncProvider` and
`isOnlineProvider`. Large text = 360×640, `textScaler 2.0`, system font and `PlusJakartaSans`.

- [ ] NEW `test/share/share_payload_test.dart`: MIME sorting (jpeg/png/gif/webp/heic → photo, svg → document, mp4/
  3gp → video, pdf/mp3/zip → document, unknown with `.mov` → video, unknown with no extension → document) · 25 items →
  20 kept + the toast flag · known size 150 MB → dropped before copy, toast wording for 1 and 2 · summary strings for
  every C7 case · `Link` only for a single URL, `Text` for a URL plus words.
- [ ] NEW `test/share/share_in_service_test.dart`: start with a share → pending, `copyShared` never called · signed
  out → login toast once, picker after sign-in + `keyOk` · `needsRestore` → no toast, picker after `keyOk` · a second
  share replaces the first · all unreadable → **Couldn't open what was shared.**, no picker · `clearShared` called
  at start before `takeShare` · logout calls `clearShared` (or deletes `share_in/`).
- [ ] NEW `test/share/share_target_screen_test.dart`: rows in `conversationsProvider` order, group subtitle **5
  members** · search filters, no match line · empty state · tap a chat you can't send in → toast, stays, no copy ·
  tap a chat → `copyShared` called once per kept item **only now**, scrim **Opening 2 of 5** · one copy fails → the
  left-out toast · ✕ during the copy → no further copies, `clearShared` · after the copy → the chat route replaces
  the picker and `chatShareProvider(id)` holds the share · already under the picker → pops, no second chat route ·
  semantics (bar label, ✕ button, live region) · reduced motion · 360×200% + Jakarta.
- [ ] NEW `test/chat/message_input_share_test.dart`: one photo → `MediaEditScreen` pushed with that file · three items
  → album editor with three · two documents → R20 **Send to Asha?** / **2 files** → Send → two document sends in
  order; Cancel → none · photos + a document: editor closed → the document confirm still shows · text into an empty
  composer, then into one with a draft (new line) · share cleared after it runs (a rebuild does not run it twice) ·
  a composer that can't send never runs it · the share's folders are deleted at the end.
- [ ] `test/chat/chat_screen*` / existing `cs` tests: green **unedited** after `canSendIn` is extracted.
- [ ] `test/grep_gates_test.dart`: K1 inside `main()`; RED once, then GREEN, both in the work log.
- [ ] Existing tests stay green **unedited**: `attach_sheets_test.dart`, every `test/media/media_edit_*`,
  `test/offline/media_*`, `test/offline/album_send_test.dart`, `home_search_test.dart`, `chat_tile_test.dart`.
- [ ] Count: the work log records **baseline + N = total**.
- [ ] Function-level diff vs HEAD of every frozen method in an edited file (`mi`, `ma`, `cs`): empty, apart from the
  `canSendIn` extraction in `cs`'s build (same values, one call).
- [ ] `flutter build apk --debug` succeeds (the manifest and Kotlin compile); full suite green · analyze 0 errors ·
  `git diff --check` clean · `trail check` clean.

## Device check list (phase 2, M52 + Redmi; you do every share and every send)

1. Gallery → share **one photo** → kuch_bhi is in the share sheet → **Send to** with **1 photo** → pick a chat →
   editor → quality sheet → one photo bubble; the other phone gets it.
2. Gallery → select **5 photos and 2 videos** → share → **3 photos and 2 videos**… (summary matches) → album editor
   with 7 → one quality sheet → one album.
3. Share **25 photos** → **Only the first 20 were added.**; the album has 20.
4. Files app (Files by Google or My Files) → share a **PDF** → **Send to Asha?** / the file name → Send → the
   document bubble shows the original name on both phones.
5. Share a **video over 100 MB** → **Too big to send. The limit is 100 MB.**; then
   `adb shell run-as com.chai.kuch_bhi ls cache/share_in` → empty or missing.
6. Chrome → Share a page → **Link** → pick a chat → the URL is in the composer, **not sent**; you tap Send.
7. **Cold start:** swipe kuch_bhi out of Recents → share a photo → splash → **Send to** opens by itself.
8. **Warm start:** be in a chat with a half-typed draft → switch apps → share text to the **same** chat → the
   picker pops back to it, the text sits on a new line under your draft.
9. **Signed out:** sign out → share a photo → login with **Sign in to share.** → sign in (restore if asked) →
   **Send to** opens.
10. After a share, swipe the app away, open it from **Recents** → no picker, no share comes back.
11. Back from the picker → you're where you were (or the sharing app). After a send, press Back from the chat and
    write down where you land (singleTask, decision 2).
12. After the launchMode change: a **notification tap** still opens its chat, and scanning a friend QR (deep link)
    still opens Add friend.
13. In an admins-only group where you're not an admin → **You can't send messages in this chat.**, picker stays.
14. **Airplane mode** → share 3 photos → album queued with the waiting look → network on → sends in order.
15. Share from kuch_bhi's own fullscreen viewer (Share) back into kuch_bhi → works like any other app.
16. Largest text + Plus Jakarta Sans: the picker, the scrim and the confirm dialog. TalkBack reads **Send to, 1
    photo** and **Cancel sharing**.
17. After items 1–6, `adb shell run-as com.chai.kuch_bhi ls cache/share_in` → empty or missing each time.

## Out of scope (do NOT build on this page)

Everything still in ⛔ · Direct Share (chats shown inside Android's share sheet, decision 19) · sending to several
chats at once (decision 3) · captions on shared media · "Open with" (`ACTION_VIEW` for files) · iOS · renaming the
share-sheet label `kuch_bhi` · a share that survives the app being killed before a chat is chosen · voice notes from
shared audio · a progress bar per copied file · sharing contacts as anything but a file.

---

## Diff vs current implementation

| # | Area | Today (file:line) | Spec | Checklist |
|---|---|---|---|---|
| 1 | Share sheet | kuch_bhi not listed (`mf:34-44`) | `SEND` + `SEND_MULTIPLE`, `*/*` | A1 |
| 2 | Launch mode | `singleTop` (`mf:19`): a share can start a second instance in the sharer's task | `singleTask`; shares arrive by `onNewIntent` | A2 |
| 3 | Receiving | nothing; one clipboard channel (`ma:13-45`) | `kuch_bhi/share` channel: take, copy off-thread with a byte cap, clear | A3–A7 |
| 4 | Recents replay | n/a | old share ignored (`LAUNCHED_FROM_HISTORY`) | A5 |
| 5 | Waiting for sign-in / key | FCM taps give up after 12 s (`fcm:366-374`) | the share waits in memory until home + `keyOk` | B1–B7 |
| 6 | Picking a chat | n/a | **Send to** page: search, chats in home order, one chat | D1–D12 |
| 7 | Who can send | checked inside the chat (`cs:568-579`) | same rule, one function, also checked in the picker | D6 |
| 8 | Sending | in-app pick only (`mi:361-422`) | the same single / album / document paths, fed by the share | E1–E4 |
| 9 | Documents | sent straight after the pick (`mi:779-800`) | shared documents ask **Send to Asha?** first | E3 |
| 10 | Text | n/a | into the composer, never auto-sent | C5 |
| 11 | Cleanup | logout wipes `media_clear/` (`mbs:69-78`) | also `share_in/`: after each share, on close, at start, at logout | F3 |

---

### Deferred decisions (you decide at spec review; default = recommended)

1. **No new dependency: a small channel in `MainActivity`** (about 100 lines of Kotlin next to the clipboard channel)
   instead of `receive_sharing_intent` 1.9.0 (the most used plugin; S7). Read in its 1.9.0 source: it copies every
   shared file **on the main thread while the app starts** (a 100 MB video freezes the launch); for files from the
   phone's main storage it hands back a raw `/storage/emulated/0/...` path **without copying**, which the app can't
   read on Android 13+ without broad storage permission; it copies into the cache under the **original name** (two
   `IMG_0001.jpg` overwrite each other) and **never deletes** the copies or the video thumbnails it makes; it **logs
   every file name**; its `VIEW` branch would also grab the `kuchbhi://` link; and 1.9.0 builds with AGP 9.2.1 /
   compileSdk 37 against this app's AGP 8.11.1 / compileSdk 36. Ours copies only after a chat is picked, off the main
   thread, with a 100 MB stop, into its own folder, and cleans up. Alternative: the plugin (less Kotlin to own; the
   issues above stay).
2. **`singleTask` launch mode** so a share always lands in the one running app. Watch: after sending, Back from the
   chat's root goes to the launcher or the previous app, not back into the sharing app's screen (device item 11).
   Alternative: keep `singleTop` (a share can open a **second** kuch_bhi on top of Gallery: two databases open, two
   live connections).
3. **One chat per share.** Alternative: pick up to 5 chats (then the editor and quality sheet run once and the same
   files go to each; more code, and a wrong tap sends to more people).
4. **A full page "Send to"**, not a bottom sheet: it holds search and a long list and works at 200% text.
   Alternative: an R19 sheet.
5. **Chats only.** Friends without a chat aren't listed (open the chat once first). Alternative: a **Friends** section
   that creates the direct chat on tap (home's `_openChat`).
6. **Every chat is listed; one you can't send in says so on tap** and the picker stays. Alternative: hide those chats
   (needs each group's members and key state before the list draws).
7. **Copy after the tap, not on arrival.** Cancelling the picker copies nothing, and a share that waits through
   sign-in holds only links. Watch: Android's read permission for the shared links lasts while the app runs; if the
   app is killed before you pick a chat, the share is lost (out of scope).
8. **Size checked before copying, and the copy stops at 100 MB**, so a 4 GB video never fills the phone.
9. **At most 20 items per share** (the album cap), the rest dropped with **Only the first 20 were added.**
   Alternative: refuse the whole share over 20.
10. **Shared photos and videos go through the editor and the quality sheet**, like an in-app pick. Alternative: send
    as is at Normal (faster, no chance to crop or pick High).
11. **Shared documents ask "Send to Asha?" once**, since the chat tap is the only other check and a wrong tap would
    send a file at once. In-app **Document** stays as it is (no confirm). Alternative: send documents straight away.
12. **Mixed share order:** photos and videos (album or single) first, then documents, then the text into the
    composer. Alternative: keep the shared order item by item (an album could not form).
13. **Text and links go into the composer, never sent by themselves.** Alternative: send text straight away.
14. **The share's subject line is dropped** (Chrome's page title). Alternative: put **subject + new line + text** in
    the composer.
15. **Signed out: hold the share in memory**, show **Sign in to share.**, open the picker after sign-in and restore.
    Alternative: drop it with **Sign in first, then share again.**
16. **A newer share replaces a waiting one.** Alternative: queue them (two pickers in a row).
17. **Shared text after an existing draft goes on a new line.** Alternative: replace the draft.
18. **Reopening from Recents never replays a share.**
19. **No Direct Share targets** (your recent chats inside Android's share sheet). Alternative: in scope now (sharing
    shortcuts per chat, updated as chats change; a separate task).
20. **Audio and every other non-photo, non-video file goes as a document.** Alternative: shared audio as a voice note
    (it would need its own player rules for foreign formats).
21. **No live PocketBase read or write.** Nothing on the server changes.
22. **Claude implements everything** (Kotlin, manifest, service, picker, composer hand-off): it is small and touches
    app start. Alternative: Astra or Mimo for the picker screen (D) with Claude grading.
