# History sync: fast first download (spec, rev 1)

Status: **spec PASS 2026-11-12, all defaults (D1 A, D2 yes, D3 accept). Built and device PASS 2026-11-12 (60 s target moved to the next revision).** Item 4 of
`docs/design/feedback-2026-11-plan.md`, steps S1 + S4. Friends saw ~5 minutes
on mobile data between the restore and Home.
Nothing visible changes except the wait. No live server change and no
server read are needed for this build.

## Why it is slow (code read, 2026-11-12)

The restore screen awaits `syncAllHistory`
(`message_repository_impl.dart:3312-3417`) and only then goes to Home
(`backup_pin_screen.dart:424-426`). Inside it, one after another:

| Cost | Count | Where |
|---|---|---|
| **Tick status for my own message: 3 requests in a row** (receipts of that message, the message again, the chat's member list) | per **own** message, fresh install | `_cacheMsgInner` `:5346-5349` → `_computeSenderStatus` `:5730-5783` |
| Same tick lookup in the normal catch-up batch | per own message with no stored status | `_cacheMessagesBatch` `:4676-4680` |
| Tick reconcile after every chat fetch and every SSE-down poll: 2 requests in a row (receipts, members) | per own message **not yet read**, every time | `_reconcileReceiptsForConversation` `:4985-5001` → `_updateMsgReceiptStatus` `:5785-5883`; callers `:737`, `:4614` |
| Count request just for the progress label | per chat | `:3331-3338` |
| Every page also counts the total | per page of 200 | `:3366-3374` |
| Progress `setState` | per message | `backup_pin_screen.dart:395` |

With a 200 ms round trip, 500 own messages × 3 × 0.2 s = **300 s**. The
reconcile row is the same pattern: a chat with 300 own messages the other
person has not read costs 600 requests on every open (a likely part of the
receipt-429 floods).

## Behaviour (what the user sees)

| # | Case | After this build |
|---|---|---|
| H1 | Restore after sign-in | Same screens, same steps. The wait drops from minutes to seconds (target below). |
| H2 | Ticks after restore | Exactly the ticks the old code would show, same rules (D1 is the one edge). |
| H3 | Opening a chat | Same ticks; the reconcile costs 2 requests per chat instead of 2 per unread own message. |
| H4 | Progress label | Updates at most 10 times a second; numbers unchanged ("chat 3 of 12", "240 of 900"). |
| H5 | Offline or a request fails | Same as today: status falls back to `sent`, never regresses a stronger stored status, history still lands. |

Target, measured on the Redmi S2 over mobile data with the test account
(device check below): **restore to Home under 60 s**, and at least 5× faster
than the same account on the current build.

**Target moved (user, 2026-11-12):** device run on mobile data gave Redmi 75.1 s,
M52 67.9 s, with ticks down to 3 requests per chat. S1 + S4 pass without the
60 s target; the target moves to the next revision (S2/S3/S5 plus
`group-key-restore.md`). See `history-sync-work-log.md`.

## Change S1: tick status per chat, not per message

1. New pure function, one place for the tick rule (today it is written twice,
   in `_computeSenderStatus` and `_updateMsgReceiptStatus`):
   `String senderStatusFor(Iterable<Receipt> receiptsOfThatMessage, Set<String> required)`
   with `required` = chat members minus the sender. `read` if every required
   id has `read_at`, else `delivered` if every one has `delivered_at`, else
   `sent`. Empty `required` → D1.
2. New repository step, once per chat, before its pages are cached: **one**
   receipts list and **one** member list.
   - Receipts: `getFullList` on `message_receipts`,
     filter `conversation_id="<id>" && recipient_id!="<me>"`, `batch: 500`,
     `fields: message_id,recipient_id,delivered_at,read_at,updated`. Grouped
     in memory by `message_id`.
   - Members: `getFullList` on `conversation_members`, filter
     `conversation_id="<id>"`, `batch: 200` (as today).
3. `syncAllHistory` and `_cacheMessagesBatch` read status from that index.
   No `messages.getOne` any more: the sender and chat come from the record in
   hand.
4. `_reconcileReceiptsForConversation` builds the same index once, then runs
   today's write rules per row unchanged: never regress (read > delivered >
   sent), skip a same-value write (13.2), and the one transaction that writes
   `read` and starts the disappearing clock from the last receipt's
   `updated` (disappearing spec B6).
5. `_cacheMsgInner` keeps the per-message call only when no index is passed
   (single SSE records, where an own row nearly always exists already).
6. If the receipts or members list fails, the index is "unknown" and the
   status falls back exactly as today (H5). A failed index never blocks the
   history from landing.

## Change S4: small request and rebuild cuts

1. Drop the `perPage: 1` count request; take `totalItems` from page 1.
2. Pages 2 and later pass `skipTotal: true`; the loop ends when a page has
   fewer than 200 items.
3. The restore screen applies progress at most every 100 ms (a timestamp
   check in the `onProgress` callback); `complete` always applies at once.
4. A timing log line per chat and one total:
   `[Sync] chat 3/12 msgs=240 requests=5 ms=1830` and
   `[Sync] total chats=12 msgs=2104 requests=41 ms=…`. `debugPrint` only,
   no message content, no ids beyond the chat index.

## Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| D1 | A chat with no other members left (everyone left or deleted their account). Today history ingest says `sent` forever, the reconcile uses the receipts it finds. | **A: one rule, the reconcile's: fall back to the receipts present** · B: keep both behaviours |
| D2 | Change the reconcile too (S1 step 4)? | **Yes**, same helper, removes 2 requests per unread own message on every open · No, history only |
| D3 | Big groups: one receipts list per chat is messages × (members − 1) rows. A 5-person group with 2,000 messages is ~8,000 rows, 16 requests of 500, about 1 MB with `fields`. | **Accept** (still far fewer requests than today) · page-sized receipt queries (more code) |

## Found while specifying (not built here)

- **Receipt list rule.** The project bible (§7.8) records
  `listRule: @request.auth.id = recipient_id || @collection.messages.sender_id ?= @request.auth.id`.
  As written, the second half is true for anyone who has ever sent a message,
  which would let them list every receipt on the server (who read what,
  when). The bible may be out of date. Checking the live rule is a read-only
  server check and needs your yes; a fix would be its own spec. S1 works
  either way, because it filters by chat and groups by message id.
- The restore screen switches its label to "decrypting" at 20 % of the
  download "for visual variety" (`backup_pin_screen.dart:399-406`); the
  phases are not real. Leave for the S3 rework of this screen.
- S2 (batch decrypt and one commit per page), S3 (newest messages first,
  Home early, background backfill) and S5 (parallel chats) are the next
  revision of this spec, after S1 + S4 are measured.

## Must not undo

- Tick rule: every non-sender member, not just the receipts present
  (`_updateMsgReceiptStatus` comment, 13.2 same-value skip).
- Disappearing B6: `read` and the clock start stay in one transaction.
- History rows land even when the key or the receipts fail (Task 7, H5).
- Session epoch guard: a sign-out mid-sync writes nothing
  (`sessionStillValid` in `_cacheMsgInner`).
- The restore overlay tests (`test/auth/restore_overlay_test.dart`).

## Test gates

New:

1. `senderStatusFor`: no receipts → `sent`; all delivered → `delivered`;
   all read → `read`; group of 3 with one receipt missing → `sent`; one read,
   one only delivered → `delivered`; empty `required` → D1 rule.
2. Request count, with the `MockClient` harness used in
   `test/offline/disappearing_test.dart`: one chat, 450 messages, 300 mine,
   `syncAllHistory` makes **≤ 1** `message_receipts` list call (one page of
   500) for status, **1** `conversation_members` call for status, **0**
   `messages/<id>` single-record calls, **0** `perPage=1` calls, and pages
   2+ carry `skipTotal`.
3. Same statuses as the old code for a fixed set of 20 receipts/members
   cases (golden table run through both the old function and the new path).
4. Reconcile: 50 own `delivered` rows → **1** receipts call and **1**
   members call; a row already `read` is never written; regression and
   same-value rules still hold; the clock starts on the `read` write.
5. Index fetch fails → statuses fall back as today and all rows still land.
6. Restore screen: 1,000 progress events in 1 s cause ≤ 11 rebuilds;
   `complete` is applied at once.

Existing, must stay green: `test/offline/mark_read_receipts_test.dart`,
`test/offline/disappearing_test.dart`, `test/offline/refetch_churn_test.dart`,
`test/offline/short_resume_test.dart`, `test/auth/restore_overlay_test.dart`,
`test/auth/backup_secret_screen_test.dart`. Full `flutter test` green against
the baseline taken at build start; `flutter analyze` 0 errors.

## Device check list (you do every sign-in)

Test account pair from two-device testing, never your real chats. If the
test account has fewer than 300 own messages, send a burst from it first with
the app.

1. Current build: uninstall, install, sign in on the Redmi on **mobile data**,
   restore. Note the time from "Restore" to Home (stopwatch, plus the
   `[Sync] total` line after the build).
2. New build: same steps. Time is under 60 s and at least 5× faster.
3. Open three chats: ticks match what the other phone shows (single, double,
   blue).
4. On the M52, send 5 messages the Redmi has not read; open that chat on
   the M52: ticks stay double grey, then turn blue after the Redmi reads.
5. A disappearing chat: an own message read by both still disappears on time.
6. Airplane mode mid-restore, then back on: history still lands, no crash.

## Out of scope

S2, S3, S5; the restore screen's design; the receipt list rule; any server
change.
