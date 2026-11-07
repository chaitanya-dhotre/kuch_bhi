# Disappearing messages: stop the history loss (spec, rev 3)

Status: spec PASS 2026-11-05, rev 3 user-approved 2026-11-07 (server time, no-content row, phone file deleted). W1 and W2 live. Backlog §7 item, reported 2026-10-12.
Rev 2 (2026-11-05, user): the timer starts when the message is read, and changing the timer never touches messages already sent.

## What the live read found (2026-11-05, read-only)

- The server `messages` collection already has `expires_at`, and both branches of its update rule lock it.
- `disappearing_messages.pb.js` is an hourly cron that deletes rows where `expires_at != '' && expires_at <= now`, 500 per run. It is **not** retroactive.
- **No client has ever set `messages.expires_at`, and 0 of 633 rows have one.** So the cron has never deleted a message. Timer messages stay on the server for good; the feature only exists on the phone, as a guess made at ingest.
- **The 2026-10-12 scroll-up test proved nothing.** `_onScroll` in `chat_screen.dart` declares history exhausted when `loadedCount < _offset` (7 < 40) without calling the server.
- **Avium: nothing was lost on the server.** The direct chat `d8zam3bst08ybzt` holds 173 messages from 2026-07-21 to 2026-11-03. Timer off. Only that phone's copy was purged.
- Group `znpkwq6sof7sma3` read 86400 on the first query and 0 on the second, so no chat has a timer on now.
- Deleting a message cascades to `message_media` (and its file) only.
- The SSE message handler never checks the event's action, so a server delete would re-ingest the deleted record. It has never fired because nothing has ever been deleted.

## Behaviour

| # | Case | What happens |
|---|---|---|
| B1 | A message reaches the server | It takes the chat's timer as a fixed length, set once by the server. Timer off: no length, it never disappears. System rows ("X joined") never disappear. Clients cannot set either field. |
| B2 | Timer turned on | Nothing older changes. Older messages have no length, so nothing can ever stamp them. |
| B3 | Timer changed or turned off | Only new messages are affected. A message already sent keeps its length, and a clock already running keeps running. This is what the dialog says: "Applies to new messages only". |
| B4 | Unread message | Its clock has not started, so it stays, however long it takes. |
| B5 | I read a message (open the chat in the foreground, or Mark as read) | My copy's clock starts: **server time** + its length. Works offline if the app has heard from the server since it launched; otherwise it starts at the next read. After deep sleep the start uses the later of server time and the device's elapsed time, so a clock is never backdated. A row I cannot show (no key yet, or not on this phone) is not read: no clock, no read receipt. |
| B6 | I sent the message | My copy's clock starts when everyone it was sent to has read it (the blue tick moment), counted from the last receipt's server time, not the reader's clock. |
| B7 | Server copy | Same moment as B6: when every other member has read it, `expires_at` = now + length. From then on no client can fetch it. Within the hour the cron removes its content and media and keeps a no-content row (sender, chat, type, time) for 90 days, visible only to a superuser. Then the row goes. |
| B8 | A clock runs out | The phone removes the row and its decrypted files on the next chat open, judged by **server time only**, once the server has my read receipt (with no network the row waits, so the sender's copy and the server's still go). Moving the phone's clock does nothing, and with no server time yet nothing is deleted. A reply to it shows "Message not available". This is the one exception to "decrypted media has no age limit". |
| B9 | Someone never reads | The message never disappears, for anyone in that chat who is waiting on them. Nothing is lost by a timer. |
| B10 | First launch of this build | Every expiry stored on the phone is cleared, once. They are all guesses. Nothing is deleted. Messages sent under a timer before this build stop disappearing. |
| B11 | A queued (offline) message | No clock until the server accepts it and it is read, so a queued message cannot be purged. |
| B12 | The server still holds a message my clock removed | It stays gone: a fetch skips a timed record whose time from my own read has run out, by server time. No badge. If that check fails, the record is kept. |

## Live change (W1), needs a go-ahead

This replaces the earlier "one hook, no field" plan, because a per-message length has to be stored.

1. Migration: add `messages.disappear_after` (number, optional, whole seconds, 0 or more). Add `@request.body.disappear_after:isset = false` to **both** update-rule branches.
2. New hook `pb_hooks/disappearing_stamp.pb.js`:
   - `onRecordCreate` on `messages`: overwrite any client value, set `disappear_after` from the chat's timer, skip `system` rows, blank `expires_at`.
   - On a `message_receipts` create or update with `read_at`: if every other member of the chat has read that message, set `expires_at` with a direct SQL update. Direct SQL so no realtime event re-ingests the row on phones. "Every member" matches the tick rule in `_computeSenderStatus`.

3. `disappearing_messages.pb.js`: compare with `@now` instead of a bound ISO string. Stored dates read `2026-11-05 07:10:00.000Z`, the bound value `2026-11-05T07:10:00.000Z`, and text comparison puts the space first. So the cron as written hits anything expiring later the same UTC day. Found in the dry run. `media_expiry.pb.js` has the same flaw (follow-up).

Rollback: delete the hook, restore the cron from backup, run the migration's down step. Existing rows read `disappear_after = 0`.

Going live makes the cron real: it deletes rows for the first time.

**Dry run, 2026-11-05, on a copy:** create takes the chat's timer and ignores client values; system rows get 0; `disappear_after` and `expires_at` refused on update, pin still allowed; `expires_at` stays blank until the last member reads; timer off leaves sent messages alone; no old row touched; the cron removes the expired row and its `message_media`, leaves receipts, and keeps a row expiring in 30 minutes.

## Live change (W2), rev 3

1. Migration `1793900100_updated_messages_hide_expired.js`: the `messages` list and view rules gain `(expires_at = "" || expires_at > @now)`, and `message_media` the same through `message_id`. An expired message and its media record are hidden from every client, before the cron runs. The encrypted media file is not protected, so its URL works until the cron removes it, up to an hour later.
2. `disappearing_messages.pb.js`: blank `encrypted_body`, `iv`, `reply_preview` by direct SQL and delete `message_media`, instead of deleting the row. Delete the row 90 days after expiry.

Rollback: restore the cron from backup, run the migration's down step. Deploy W2 before or with the client, or an expired own row can reappear for up to an hour.

**Dry run, 2026-11-07, on a copy:** a member gets 404 on an expired message and its media, a superuser 200; list excludes both; realtime create and update still reach the other member; the cron blanks body and iv, removes the media record and its stored file, keeps the row, leaves a row expiring in 30 minutes, removes a 91-day row, changes nothing on a rerun; the down step restores both rules.

Reports (learned 2026-11-07, not built): the no-content row keeps who messaged whom and when. Message content can never be recovered from it. Receipts, reactions and stars keep their message ids after the 90 days. The privacy policy must say so.

## Client change

- Drift v14: `messages.disappear_after`, plus the one-time clear (B10). Carried through `ssePinDeleteCompanion`.
- `_companionFromRecord`: store `disappear_after`; keep the row's existing expiry, else copy the record's `expires_at` (reinstall). Never compute from the chat's timer.
- `markConversationRead`: stamp my unread timed rows first, before any network call (B5).
- `_updateMsgReceiptStatus`: on the flip to read, stamp my own row from the last read receipt's server time (B6). The existing reconcile covers a phone that was offline.
- SSE message handler: ignore `delete` events.
- Remove `_computeExpiry`, `_computeExpirySync` and `_disappearingDurations`.

## Accepted edges

- A timed photo nobody has finished reading is still deleted at its media retention (30 or 60 days): the message stays, its photo shows as expired. Follow-up: hold media deletion until read.
- The purge runs on chat open, so a chat left open past expiry keeps showing the message until the next open.
- In a group, the Media page still lists a photo my clock removed until the server copy goes, and opening it downloads it again.
- In a group, my copy can go before the server's if someone else has not read yet (B12 keeps it gone). A pin on such a message while it waits would bring it back with a new clock. It never loses anything.
- If the last unread member leaves, no receipt fires, so the server copy stays until someone reads again.
- A member added after a message counts as a reader, like the blue tick does, so that message waits for them too.
- Old builds keep guessing until they update, and they ingest the cron's delete event, which brings the row back with a badge. Only their own phone is affected, and only in a chat with a timer on.

## Must not undo

SSE `expiresAt` preservation (`595efe2`), expired media (`a4b6f25`), reply quote "Message not available", multi-select D7/F6 (`a9d40e1`), decrypted media with no age limit.

## Out of scope, for follow-up

- `setDisappearingDuration` swallows errors, so a failed write shows the success toast.
- The purge also removes starred rows, as it does today.
- The four companions in `_syncDeletedForMe` and `_syncStarredMessages` omit `albumId`/`albumIndex`, so that rebuild resets the album.
