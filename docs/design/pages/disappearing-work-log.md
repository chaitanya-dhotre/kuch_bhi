# Disappearing messages: work log

Spec: `disappearing.md`. Backlog §7.

## Gates, 2026-11-05

1140/1140 tests (1121 at start), `flutter analyze` no new errors, `git diff --check` clean.
`trail check`: 6 flagged, all word-match false positives or followed: the schema bump edits the three version asserts, and the drift column is hand-written.

## Independent review

First pass: FAIL, 1 BLOCK.

| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | BLOCK | A raw `customUpdate` notifies even with 0 rows, so every open chat re-emitted, re-ran mark-read and looped (the 13.2 storm) | Typed `update().write()`, which notifies only when a row changed. Test: nothing to stamp, no emission |
| 2 | SHOULD | Rows cached by the push handler had no length and could be dropped as unchanged | Length on the FCM companion, and in `_filterUnresolvedOrChanged` |
| 3 | SHOULD | A lost-ack re-run never stored the length | Written in `resolveDuplicateSend` |
| 4 | SHOULD | A purged row came back from a fetch with a new clock and a phantom badge | `_withoutRunOut`, spec B12 |
| 5 | SHOULD | Mark-read stamped and receipted rows nobody could read, so the server could delete them before the key arrived | Clock and receipts only for local `ready` rows |
| 6 | SHOULD | A chat open in the background marked new rows read | Foreground check in the debounce; `_enter` marks on resume |
| 7 | SHOULD | Deleting could hit other relations to `messages` | Live read: only `message_media` relates to it, and it cascades. Nothing to fix |
| 8 | NIT | A kill between status and clock left the sender's clock unstarted | One transaction |

Left as is: 9 and 11 (safe direction, need a stall of 24 h or more), 10 (only when the member fetch fails), 12 (in the spec's edges), 14 (follow-up in the spec).

## Rev 3 review, 2026-11-07

Server time, no-content row, phone file deleted. First pass: FAIL, 1 BLOCK.

| # | Severity | Finding | Fix |
|---|---|---|---|
| B1 | BLOCK | The stopwatch pauses in deep sleep, so a start stamp after a long sleep was backdated and a 24-hour message could vanish early | `ServerClock.latest` for starting clocks; `now` stays for purges |
| S1 | SHOULD | An offline read that outlived its timer never sent its receipt, so the sender's and server's copies stayed for good | The purge confirms the receipt first; with no network the row waits |
| S2 | SHOULD | `getOne` is hidden after expiry, so the tick fell back to present receipts and the sender's clock could never start | Read chat and sender from the local row |
| S3 | SHOULD | A running download could leave a decrypted file, or a bubble could re-request a purged row | `_forgotten` set, prefix sweep in `forgetLocal`, purge before the first emission (bounded to 2 s) |
| S4 | SHOULD | Hiding covered `messages` but not `message_media` | Same rule on `message_media`, through `message_id`. The file URL is not protected, so it lasts until the cron |
| S5 | SHOULD | `loadedCount < _offset` stranded history as soon as any row expired: the Avium symptom | `loadMoreMessages` returns whether the page was full, and that decides the end of history |
| N3 | NIT | Restore skipped the run-out check | `_withoutRunOut` in `syncAllHistory` |

Left as is: N1 (a lost ack plus a day offline reads as an id collision), N2 (a purge can abandon a stalled upload), and share and edit temp copies of a photo, which are not swept.

## W1, live 2026-11-05 (user approved, including the cron fix)

Dry run on a copy, results in the spec. Then:

- Migration `pb_migrations/1793900000_updated_messages_disappear_after.js`, applied by restart. 633 rows read `disappear_after = 0`. Both rule branches locked.
- New `pb_hooks/disappearing_stamp.pb.js`. `disappearing_messages.pb.js` now compares with `@now`.
- Health 200, service active, no errors in the log. Timer chats 0, rows with an expiry 0.
- Backups: `/home/ubuntu/pb_backups/data.db.20261105-disappearing-pre`, `/home/ubuntu/pb_backups/pb_hooks.20261105-disappearing-pre`.

Rollback: restore the two hook files from the backup, then run the migration's down step.

## W2, live 2026-11-07 (user approved)

Dry run on a copy, results in the spec. Migration `pb_migrations/1793900100_updated_messages_hide_expired.js` applied by restart; `disappearing_messages.pb.js` now blanks instead of deleting. Health 200 locally and publicly, service active, no errors in the log. Both collections' list and view rules carry the hide. Backups: `/home/ubuntu/pb_backups/data.db.20261107-disappearing-w2-pre`, `/home/ubuntu/pb_backups/pb_hooks.20261107-disappearing-w2-pre`.

Rollback: restore `disappearing_messages.pb.js` from the backup, then run the migration's down step.

## Device note, 2026-11-07

After the grey-screen test build (still schema v13) went on the M52, this build stuck on the splash: `duplicate column name: disappear_after`. Opening v14 with an older build resets `user_version` to 13 and keeps the column, so the v14 step ran again and failed on every open. The step now checks for the column first and leaves the clocks alone in that case. No data was lost: the failed upgrade rolled back.

## Short-expiry test, 2026-11-07

Group "Disappointed Disappee" (M52 + Redmi only), timer set to 120 s by SQL on the server. Server: PASS. The three new messages (2 texts, 1 photo) got `disappear_after = 120` and `expires_at` = the M52's read + 120 s, to the millisecond.

Phone: FAIL first. The M52 still showed them a minute after expiry. The chat's message provider is not auto-disposed, so `watchMessages` and its purge ran once per app run, and here that was before the expiry. Fixed: `markConversationRead`, which every open and resume runs, purges first. Test: a chat reopened in the same app run still purges.

Phone after the fix: PASS. The M52 opened the chat and the two texts and the photo were gone; the rest of the chat stayed.

Cron: PASS. Run by the user at 09:22 UTC (`blanked 3 removed 0`). All three rows keep sender, chat, type and time; `encrypted_body` and `iv` are empty and the `message_media` record is gone. No row outside the test group was blanked. The group's timer was then set back to 0.

## Device check (M52 + Redmi)

Use a **new throwaway group** for everything except item 1. Never set a timer in a real chat. Where it says "server", tell me and I read that row, read-only.

1. **Upgrade.** Install on both. Open a few real chats twice. Nothing is missing, and the Avium chat still scrolls back to July.
2. In the test group, send 3 messages with the timer Off. Turn the timer to 24 hours.
3. **The bug.** Close and reopen the chat twice on each phone. The 3 old messages stay.
4. **Unread waits.** With the Redmi out of the chat, send from the M52. Server: length 86400, no expiry.
5. **Read starts it.** Open the chat on the Redmi. The M52 goes blue. Server: expiry about 24 hours from now.
6. **No loop.** Leave the chat open for a minute. No flicker, no heat, home stays calm.
7. **Queued send.** M52 in flight mode, send, go back online. It sends and stays.
8. **Push path.** Kill the app on the Redmi, send from the M52, wait for the notification, open from it. The message shows. Server: expiry set after the open.
9. **Background.** Open the chat on the Redmi, press home, send from the M52. No blue tick until the Redmi returns to the chat.
10. **Timer change.** Set 7 days and send one. Then set Off and send one. Server: lengths 604800 and 0, and the earlier expiries have not moved.
11. **Photo.** With the timer on, send a photo. It sends and opens normally.
12. **Expiry.** After 24 hours plus the hourly cron, or sooner if you want me to shorten a test row's expiry, reopen on both. The timed messages leave, a reply to one reads "Message not available", no badge, and they do not come back on the next open. Old messages stay.
13. **Clock ahead.** Read a timed message, set the phone's clock 2 days ahead, reopen the chat. It stays. Set the clock back.
14. **Real expiry.** After the 24 hours, reopen with the correct time. The message and its photo leave. Server: the row has no content, no media record, and sender and time remain.
15. **Scroll-up.** In a chat with over 40 messages, scroll to the top. Older history still loads.
