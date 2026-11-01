# Wave 4: media-send SHOULDs, burst order, multi-delete confirm, group icon EXIF (2026-11-01)

Base `b90bf4f` (810/810). Claude end to end (sync/outbox). User device PASS 2026-11-01 (all items); one commit.

## Items

| # | Item | Confirmed in code | Fix | Test (RED → GREEN) |
|---|---|---|---|---|
| 1 | Offline cancel after the create ack comes back (media-send review SHOULD 4) | The cancel only set local `is_deleted_for_everyone`. The page fetch (`_companionFromRecord`) and live update (`ssePinDeleteCompanion`) rebuild the row from the server copy, which isn't marked yet, so the bubble returned. `pendingOwnMedia` needs `status == pending`, so after the fetch (flag false) or a receipt (status delivered) resume never marked the server. | Tombstone: `markCancelledLocally` also sets status `cancelled`. `IngestBoundary.commit` (the one writer for fetch, SSE and single-message caching) re-reads the target rows inside its transaction and keeps hidden + `cancelled` on any row that is `cancelled` now. That also covers a cancel landing between the caller's read and the commit (review SHOULD 2). `updateMessageStatus` (every status writer, receipts included) never overwrites `cancelled`. `pendingOwnMedia` includes `cancelled`. The row is still deleted once the server mark lands. | `media_send_followups_test` "offline cancel after the create ack…": RED at the page fetch → GREEN through fetch, a live update built *before* the cancel, and a receipt (status still `cancelled`), then resume marks and deletes the row. Mutation (guard off) → RED. |
| 2 | A failed row's latched blobs stay pinned after delete (SHOULD 6) | `deleteMessage` never touched blob rows. Eviction skips `upload_pending` rows (`_isProtected`), and resume skips `failed` rows, so the files stayed forever. | `deleteMessage` calls `cancelMediaUpload` only for an own latched send that cannot have reached anyone complete: **no server id yet, or status `failed`**. That frees the blob rows and files, hides the row, and hides the empty server copy. A pending acked upload deleted "for me" keeps uploading; receivers get it, and the latch clears when it finishes (resume re-runs it after a kill). That matches "deleted for you only". | "deleting a failed own media row frees its latched blobs": RED → GREEN. "delete for me while the upload runs: never unsent…" (review SHOULD 1): no server mark, latch cleared after; mutation (cancel on every delete) → RED. |
| 3 | Voice retry tap fails the first time (SHOULD 9) | `_loadAndPlay` invalidated the cached failure, then read `ref.read(voice).valueOrNull`, which is null while reloading, so it threw "No media found". | `await ref.read(voice.future)`. `mediaFileProvider` is a plain `FutureProvider.family` (not autoDispose) and is watched in build, so the future always completes (learning 2026-10-31 respected). | `voice_retry_tap_test`: after a failed load, the first tap shows the spinner while the reload is pending, then the error again if it finds nothing. RED (no spinner, immediate error) → GREEN. Re-RED with the old line restored, and GREEN on 3 runs. |
| 4 | Burst-send follow-ups (send the id on media create; lift queued texts at the media ack) | **Already shipped in `d0e3c85`:** the create body has `'id': localId` (a `generateOpId()` id) and the create-ack transaction calls `liftQueuedSends` (texts and media). The memory pointer was stale. | No code change. | Guard test "a text queued behind a media send stays behind it at the media ack" (also checks the create carries the id). GREEN at baseline. **Mutation RED:** with the `liftQueuedSends` line removed it fails "after the media ack"; file restored byte-identical. |
| 5 | Multi-select delete has no confirmation | `_deleteSelected` looped `deleteMessage` at once. | New `confirmAndDeleteForMe` (message_context_menu.dart) uses R20 `showConfirmDialog`, destructive, `Icons.delete_outline`. Title "Delete N messages?" ("Delete message?" for 1). **Wording matched the app's existing single "Delete for me" confirm**: "These messages will be deleted for you only." / "This message will be deleted for you only.", button "Delete", instead of the brief's "They're removed from this phone." Cancel keeps the selection. | `multi_delete_confirm_test` (3 tests). RED = the function didn't exist (compile error; no ChatScreen test harness exists to pump the screen) → GREEN. |
| 6 | Security §7.1: group icon uploads raw picked bytes with EXIF | `GroupCreateService.createConversation` and `updateGroupInfo` both sent `iconFile.readAsBytes()`. | The avatar's private `_avatarJpegWithoutExif` was lifted to `lib/core/utils/jpeg_without_exif.dart` (`jpegWithoutExif`, same settings), and the avatar, group create and group settings all use it. | `group_icon_exif_test` (2 tests, faked `FlutterImageCompressPlatform`): the upload holds only the re-encoder's output, never the picked bytes (a fake GPS EXIF block), and the re-encoder is asked for `keepExif: false`. RED on both sites → GREEN. The native encoder's stripping itself is the plugin's job (device check 6). |
| 7 | Security §4.3: decrypted media in the temp cache has no TTL | **Not covered.** The janitor deletes only `*.part` files. Eviction is size-only LRU above `kMediaCacheMaxBytes`, and `upload_pending`, starred and pinned media are never evicted. Logout does wipe `media_clear` (`wipeMediaCache`, auth_repository_impl.dart:392). | **WONTFIX (user, 2026-11-01):** the server deletes media after its retention, so the phone's copy is the only one left; an age sweep would lose it for good. Nothing changed. (Was proposed: a janitor TTL sweep that evicts `ready` blobs whose `lastAccess` is older than 30 days. File deleted, state `evicted`, metadata kept; it re-downloads on view while the server still has it. It would skip `upload_pending` blobs. Open choice: should starred/pinned also age out?) | none |
| 8 | 13.10 wording: "Message expired" vs "Message not available" | `reply_quote.dart` shows "Message expired" whenever the parent row is absent, including a parent older than the loaded history. | **User let Claude pick: "Message not available"** (true for expired, deleted and not-loaded-yet). `reply_quote.dart:175`. | `reply_quote_expired_test` copy updated to the new string (a requested copy change, not a behaviour fix). |

## New finding (not fixed, needs a decision)

- **Burst order, reverse race (item 4).** A photo queued *before* a text can still be overtaken. On reconnect the text outbox and the media resume run independently, and if the text's create lands first, the server orders text before photo for every device. The photo's later ack then stamps it after the text. The text ack's lift (`liftQueuedTextSends`) lifts only texts, and lifting the photo locally wouldn't help, because the server order is already reversed. The real fix is for the text outbox to wait for an earlier queued media *create* (not its upload) in the same chat. That changes the frozen text send path (decision in the media-send learning), so it stays open. **User 2026-11-01: fine for now; backlog 14.7, fix only if it becomes a nuisance.**
- Same-second clock skew (server ahead of the phone) can show a message sent right after an ack above it until its own ack. This affects text and media alike and is old behaviour.

## Existing test changed

- `test/chat/reply_quote_expired_test.dart`: expected copy changed to "Message not available" (item 8, user decision).
- Harness only: `test/offline/media_send_harness.dart` gained a `createGate` (no existing test uses it).
- `test/offline/media_send_resume_test.dart:166` "cancel offline…": the kept hidden row's status is expected to be `cancelled` instead of `pending`. The assertion is the same strength (the row is kept for the mark) and only the tombstone's value changed. No other existing test was touched.

## Gates

- `flutter test`: 822/822 (810 + 12 new: followups 6, voice 1, multi-delete 3, group icon 2).
- `flutter analyze`: 0 errors (81 issues, all pre-existing; the one new warning, an unused import in a new test, was fixed).
- `git diff --check`: clean.
- `trail check`: exit 1 on one word-match "conflict": the backlog §14 heading ("…group icon EXIF") vs the learning on a UI guard for group remove/leave. Unrelated; it will be explained in the commit message. Other word matches: voice_message_bubble.dart:115 ("failed retry" vs the send-failure learning, but this is a download retry, not a send) and message_repository_impl.dart:434 ("server … yet" vs the expired-media 404 learning, but this is a cancel comment); ingest_boundary.dart:165 vs this wave's own learning (that learning ruled out a sticky flag on *every* row; this guard keeps it only for `cancelled` rows).
- Frozen E2E: function-level diff touches only `IngestBoundary.commit` (phase 3a), `MessagesDao.cancelledSendIds` (new), `deleteMessage`, `_markCancelledOnServer`, `updateGroupInfo`, `AuthRepositoryImpl.updateProfile` (avatar call) and DAO helpers. No encrypt/decrypt/key function changed; no encryption file in the diff.
- No `ref` in dispose; no `$e` in user text.
- Independent review: see below.

## Review

Round 1 (fresh-context general agent): **FAIL**, no BLOCK. All three SHOULDs fixed:

| # | Finding | Fix | Proof |
|---|---|---|---|
| S1 | Delete-for-me went through the cancel route whenever the upload latch was set, so a still-uploading photo (or a stale latch after a kill, upload already on the server) was unsent for everyone | Cancel only when there's no server id yet or status is `failed` (item 2 row) | new test + mutation RED |
| S2 | Fetch/SSE build companions from a row read before the decrypt step; a cancel landing in that gap was overwritten (pending, visible, files gone = stuck forever) | Guard moved into `IngestBoundary.commit`, inside its transaction; the two companion-level guards removed | test 1 commits a companion built before the cancel; mutation RED |
| S3 (old) | `_markCancelledOnServer` deleted the local row on a 404 while the create was still in flight; if the late mark then failed, receivers kept an empty copy | A 404 with the upload ticket still registered keeps the row; the upload's own post-create mark, or the next resume, handles it | "cancel while the create is in flight…" with a new harness `createGate`; mutation RED |

NITs left: the voice retry spinner can now sit up to the provider's 45 s wait for a fresh (<10 min) voice note, where it used to error at once. The multi-select loop stops at the first failing delete (same as before). `jpegWithoutExif` makes a transparent PNG or a GIF icon an opaque single-frame JPEG (same as the avatar). Starred/pinned lists don't filter hidden rows (pre-existing).

Round 2 (narrow re-review of the three fixes, fresh context): **PASS**, no BLOCK. Two SHOULDs fixed:

| # | Finding | Fix | Proof |
|---|---|---|---|
| R2-1 | The ingest guard matched only on server id. A send cancelled during its create keeps serverId null (the create-ack stamp skips cancelled rows); if the late mark then failed, a page fetch inserted the unmarked copy as a second, visible row until the next resume. (The reviewer's path, "DoUpdate on the same localId", is wrong, since the fetched copy gets a new uuid, but the window is real.) | `MessagesDao.cancelledSendIds` matches `cancelled` rows on server id **or** local id (a media send's local id is its server record id) | "cancel while the create is in flight…" now does a page fetch before resume; mutation (server id only) → RED |
| R2-2 | Delete for everyone on an acked, still-uploading send wasn't a cancel: the upload kept going, and after a kill resume skipped the row, so the latch stayed pinned | Delete for everyone on a latched send = cancel | "delete for everyone while the upload runs = a cancel…"; mutation → RED |

NITs not taken: a delete-for-me write from a snapshot can race the create-ack stamp (row stays hidden; pre-existing); `upsertMessageByServerId` (FCM isolate) bypasses the guard but returns early when the row exists.

## Device check (M52 `RFCRA047WSJ`, use a test chat)

1. Offline cancel after the ack: send a long video, wait for the progress ring (create acked), airplane mode on, tap ✕. Reopen the chat and scroll up (page fetch): it stays gone. Airplane off: the other phone never shows it, or it disappears.
2. Delete an unsent upload: (a) airplane on, send a photo, long-press it, Delete for me, airplane off: nothing is sent (it never left the phone). (b) Online, send a long video, and while the ring shows, Delete for me: it disappears here, and the other phone still gets the video. (c) Same, but Delete for everyone: gone on both phones, and the upload stops.
3. Voice retry: airplane on, tap play on a voice note not on the phone (error). Airplane off, tap once: it plays on the first tap.
4. Burst order: offline, send a photo then a text quickly, go online. Photo then text on both phones. (The reverse race in "New finding" may still show here.)
5. Multi-select: long-press, select 3, tap the bin. "Delete 3 messages?": Cancel keeps the selection, Delete removes them.
6. Group icon: set a group icon from a camera photo taken with location on. Optional: with your OK, Claude downloads the icon from the server and checks it has no GPS EXIF (a live read).
7. Reply quote: reply to a message, let the original disappear (or open a reply to a message older than the loaded history). The quote reads "Message not available" in soft ink, with no loading bar.

## Device run (Claude, M52, 2026-11-01, debug build of this tree on both phones)

Read-only checks only; nothing sent, reacted, starred or deleted.
- 5 (cancel path): PASS. "Things To Fix Lol", Select ×1 → bin → "Delete message?" / "This message will be deleted for you only." / destructive Delete; Cancel keeps "1 selected". Select a 2nd → "Delete 2 messages?" / "These messages will be deleted for you only."; Cancel, ✕; both messages still there. The Delete tap itself is left to the user (unit-tested).
- 7: PASS. Avium DM, 22 July reply whose original isn't on the phone: the quote reads "Avium / Message not available" in soft ink, no loading bar.
- Seen in passing, not from this change: "Couldn't load older messages" at the top of Avium on a weak 4G link (log: loadMore, reactions and media all hit the 8 s timeout); Retry loaded the rest. Tapping a bubble in selection mode doesn't add it (only the menu's Select does); pre-existing.
- The user ran 1, 2a/2b/2c, 3, 4, 6 (and the Delete tap of 5): **all PASS** (2026-11-01).
