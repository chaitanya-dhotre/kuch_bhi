# History sync S1 + S4 (fast first download): implementation work log

Date: 2026-11-12.
Scope: `docs/design/pages/history-sync.md` (spec PASS 2026-11-12, all defaults: D1 A, D2 yes,
D3 accept), plan item 4 of `docs/design/feedback-2026-11-plan.md`. Built by Claude. No live
PocketBase read or write.

## Status

| Step | Result |
|---|---|
| Spec | user PASS 2026-11-12, D1 A / D2 yes / D3 accept |
| Implementation | DONE 2026-11-12, S1 steps 1–6 + S4 steps 1–4 |
| Gates | baseline `flutter test` **1252/1252** (taken first, includes the uncommitted mascot 5a work in this checkout) → after **1263/1263** (+11: 10 in `history_sync_test.dart`, 1 in `restore_overlay_test.dart`). First full run had 1 failure in `server_created_watermark_test.dart` (drift "re-open after closing" from an unawaited media upload at teardown, a path not touched here); 5/5 green alone, full rerun green: a load flake · the 6 listed existing files green · `flutter analyze` 0 errors, no issue in the new test file; the one warning in the repository file (`:3867` admin check) predates this change · `git diff --check` clean · `trail check` 0 conflicts, nothing flagged on these files |
| Device check | release arm64 build, app data cleared before each run, user signed in. **Run 1, both on Wi-Fi:** M52 79.0 s (26 chats / 648 msgs / 78 requests), Redmi 45.1 s (17 / 534 / 51). **Run 2, mobile data** (M52 on LTE, Redmi on the M52's hotspot, one at a time): **M52 67.9 s, Redmi 75.1 s**. Every chat = 3 sync requests (tick lookups gone). **Target (Redmi on mobile data < 60 s) NOT met: 75.1 s.** User decision 2026-11-12: S1 + S4 pass without it; the target moves to the next revision. No old-build baseline (phones wiped before install), so "5× faster" is unmeasured. Items 3–6 (ticks match, blue after read, disappearing on time, airplane mode mid-restore): **user PASS 2026-11-12. Device PASS.** |
| Commit | none. After the user's device PASS and only when the user says: one commit with `history-sync.md`, this log, `.trail/learnings/2026-11-12-the-first-history-download-after-sign-chaitanya.md`, `.trail/learnings/2026-11-12-restore-progress-repaints-are-throttled-with-chaitanya.md` (new, this build), the two code files and the two test files. |

## What changed

`lib/infrastructure/repositories/message_repository_impl.dart`

- **`senderStatusFor(receipts, required)`** (top level, pure): the one tick rule. `read` if
  every required id has `read_at`, else `delivered` if every one has `delivered_at`, else
  `sent`. Empty `required` → the receipts present stand in (D1 A); no receipts → `sent`.
- **`_TickIndex`** + **`_tickIndex(convId, myId)`**: one `message_receipts` getFullList
  (`conversation_id="X" && recipient_id!="me"`, batch 500,
  `fields: message_id,recipient_id,delivered_at,read_at,updated`), grouped by `message_id`,
  plus one `conversation_members` list (members minus me). A failed receipts list leaves
  `byMessage` null and every status falls back to `sent` (H5); a failed member list leaves
  `required` empty and the receipts present decide (as today).
- **`_requiredRecipients(convId, senderId)`**: the member lookup, shared by the index and the
  per-message paths.
- **`syncAllHistory`**: builds the index once per chat and passes it to `_cacheMsg(ticks:)`.
  The `perPage: 1` count request is gone (page 1's `totalItems`); pages 2+ send
  `skipTotal: true`; the loop ends on a short page. The count fetch moved inside the per-chat
  `try`, so one chat's failure no longer ends the whole sync. Timing lines:
  `[Sync] chat i/N msgs= requests= ms=` and `[Sync] total chats= msgs= requests= ms=`
  (no content, no ids). `requests` counts message pages + tick-index calls only (key
  lookups and the deleted/starred passes are not counted).
- **`_cacheMsgInner`**: uses `ticks.statusFor(id)` when an index is passed; otherwise (single
  SSE records) the per-message **`_computeSenderStatus(record)`**, which now takes the chat and
  sender from the record in hand, so the `messages.getOne` request is gone.
- **`_cacheMessagesBatch`**: builds the index lazily, at most once per batch, only when an own
  row has no stored status.
- **`_reconcileReceiptsForConversation`**: builds the index once (lazily, only if some own row
  is not `read`), then runs the unchanged write rules per row through
  **`_applyReceiptStatus`**: never regress, skip a same-value write (13.2), `read` +
  `startClockOnRow` in one transaction (disappearing B6). Index receipts failed → no writes.
- **`_updateMsgReceiptStatus`** (SSE receipt events, user-wide reconcile): same fetches as
  before, now through `_requiredRecipients` + `_applyReceiptStatus`.

`lib/features/auth/screens/backup_pin_screen.dart`

- Download progress paints at most every 100 ms: the first event applies at once, later ones
  wait in `_pendingProgress` and a 100 ms timer applies the latest (leading + trailing). `complete`
  cancels the timer and applies at once. The timer is cancelled in `dispose`.
  Deviation from the spec's wording ("a timestamp check"): a timer, not a timestamp, so the last
  event of a burst still lands (a timestamp check drops it until the next event) and widget
  tests can drive it on the fake clock. Same cap: ≤ 11 repaints per second.

## Tests

New `test/offline/history_sync_test.dart` (MockClient harness as in
`test/offline/disappearing_test.dart`, paging like the real server):

1. Gate 1: `senderStatusFor` cases: no receipts, all delivered, all read, group of 3 with one
   missing, one read + one delivered, D1.
2. Gate 2: one chat, 450 messages, 300 mine: **1** `message_receipts` call, **1** status
   `conversation_members` call, **0** `messages/<id>`, **0** `perPage=1`, pages 2+ carry
   `skipTotal`, 3 pages; every row lands with the expected status.
3. Gate 3: 20 golden cases run through copies of the old ingest and old reconcile rules; new =
   old reconcile in all 20, new = old ingest wherever someone else is in the chat (D1 is the
   one intended difference).
4. Gate 4: reconcile with 50 own `delivered` rows + 1 `read`: **1** receipts call, **1** members
   call; the `read` row, the regression row and same-value rows keep `updatedAt` (never
   written); the read write starts the clock from the receipt's `updated`.
5. Gate 5: receipts list fails → all 450 rows land, own rows `sent`; member list fails → all
   rows land, receipts present decide.

`test/auth/restore_overlay_test.dart`:

6. Gate 6 (new test): 1,000 progress events over 1 s → ≤ 11 distinct labels painted, first at
   once; `complete` shows "Your chats are ready" on the next frame.
- Existing test "K1b: centre check, one toss…" changed by one pump: after the two-event burst
  it now pumps 100 ms + 1,500 ms instead of one 1,600 ms pump. Why: the second event now paints
  100 ms later, and a single long `pump` draws only one frame at its end, so the envelope tick
  inside that pump saw the old count and the next tick counted a third envelope. A phone draws
  every 16 ms; with 100 ms pumps the old assertions (2 envelopes, never a backlog) hold
  unchanged.

## Found, not built here

- `_reconcileReceiptsUser` (resume, user-wide) still costs 2 requests per own non-read row
  (chunks of 8). Same index would fit, grouped by chat. Not in this spec.
- Spec "Found while specifying" items stand (receipt list rule check needs a live read and
  your yes; the fake "decrypting" phase; S2/S3/S5).

## Device run 1 finding

On the M52, six group chats with 1–8 messages took 5.4–12.2 s each (about 46 s of the 79 s)
while making only 3 sync requests each. The time goes to group key resolution: the log shows
the key path walking every group key version (`Skipping undecryptable group key version`, 94
times on the M52 and 69 on the Redmi). That is outside S1/S4; it's proposed as its own spec.
Without it the M52 restore would be about 33 s.

## Device run 2 finding (Redmi, hotspot, 75 s)

Where the Redmi's time goes, read from the log (estimates, not measured per step):
- Every chat pays a fixed run of sequential round trips, about 350–400 ms each over the
  hotspot: key lookup, tick index (2), first page, then the deleted-for-me and starred passes
  (about 1–1.5 s between one chat's `[Sync] chat` line and the next chat's key line, not
  counted in its `ms`). A 0-message chat still took 1.7 s; 1-message chats 2.6–4.4 s.
- Group chats add the key-version walk (29 undecryptable versions this run; 10–12 s for two
  group chats on the M52). Proposed as its own spec.
- Big chats pay per-message decrypt and commit on the slow CPU: 159 messages took ~6.6 s
  after the key.

The remaining levers are the spec's next revision (S5 parallel chats for the per-chat round
trips, S2 batch decrypt for big chats, S3 Home early) plus the group-key spec.

## Device check list (you do every sign-in; test account pair, never real chats)

If the test account has fewer than 300 own messages, send a burst from it first.

1. Current build (before this change; use the APK already on the Redmi or one built from
   `HEAD`, since this checkout's working tree has the change): clear app data or reinstall
   that APK, sign in on the Redmi on **mobile data**, restore. Stopwatch from "Restore" to
   Home.
2. This build: same steps. Under 60 s and at least 5× faster. Note the `[Sync] total` line
   (`adb logcat | grep "\[Sync\]"`, debug or profile build).
3. Open three chats: ticks match what the other phone shows (single, double, blue).
4. On the M52, send 5 messages the Redmi has not read; open that chat on the M52: double grey,
   then blue after the Redmi reads.
5. A disappearing chat: an own message read by both still disappears on time.
6. Airplane mode mid-restore, then back on: history still lands, no crash.
