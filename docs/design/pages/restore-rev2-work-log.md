# Restore rev 2 (R1–R5): implementation work log

Date: 2026-11-14.
Scope: `docs/design/pages/restore-rev2.md` (spec PASS 2026-11-14, all defaults: D1 A, D2 A, D3 skip,
D4 60 s, D5 skip, D6 not now, D7 no live read, D8 chat-open fallback, D9 A, D10 not in this build).
Built on top of the uncommitted history-sync S1 + S4 and group-key G1–G6 work in this checkout.
Built by Claude. No live PocketBase read or write. PocketBase's filter cap was read from the
public v0.37.5 source (`tools/search/provider.go`: `MaxFilterLength = 3500`,
`DefaultFilterExprLimit = 200`), not from the live server.

## Status

| Step | Result |
|---|---|
| Spec | user PASS 2026-11-14, all defaults |
| Implementation | DONE 2026-11-14, R1–R5 |
| Gates | baseline `flutter test` **1272/1272** (taken first) → after **1292/1292** (+20: 18 in `test/offline/restore_rev2_test.dart`, 2 in `test/auth/restore_overlay_test.dart`) · 16 spec gates written (18 tests in `test/offline/restore_rev2_test.dart` + 2 in `test/auth/restore_overlay_test.dart`), all green · listed existing files green · `flutter analyze` 0 errors (the two warnings in the touched lib files, `message_repository_impl.dart:3970` admin check and `encryption_service.dart:459` cast, were there before) · `trail check` no conflicts · gates 9, 10, 11 and 12 mutation-checked (removing the R3 first-sight check, the R4 single-flight, the 60 s window or the D5 prefetch guard fails its gate) |
| Device check | 2026-11-14, release arm64, both phones, two rounds. Round 1: items 1, 2, 4, 5 pass from the logs, item 6 FAILED (Finish later bounced back) and was fixed. Round 2 (fixed build): item 6 passes, item 7 passes; the user confirmed items 3, 5 and 7. Item 8 is a borderline miss (chat 1 started ~5.5 s after the start, target 5 s). Awaiting the user's overall PASS |
| Commit | none. After the user's device PASS and only when the user says: one commit with `restore-rev2.md`, this log, `.trail/learnings/2026-11-13-a-fresh-install-of-a-group-chaitanya.md`, `.trail/learnings/2026-11-14-a-restore-that-loses-the-connection-chaitanya.md`, the four lib files and the test files below. The repository and encryption files also hold the uncommitted history-sync and G1–G6 builds; commit order with them is the user's call. |

## What changed

`lib/domain/repositories/message_repository.dart`

- `syncAllHistory({onProgress, ConnectivitySignal? net})`; `HistorySyncPhase.waitingForNetwork`;
  `HistorySyncProgress.chatsLeft`. The domain file imports `connectivity_signal.dart` (a file
  path, not `connectivity_plus`), so gate 13 holds.

`lib/infrastructure/repositories/message_repository_impl.dart`

- **R1** `syncAllHistory` runs each chat through `runChat`, which returns "left" for a
  `ClientException` with status 0 or 429, or for an empty key step while `net` says offline. Any
  other failure is logged and skipped (R-B6). `pass(order)`: a left chat while offline reports
  `waitingForNetwork` (`chatsLeft` = left so far in this pass + this chat + the ones not started),
  waits for `net.changes` to say online, reports `downloadingMessages` for that chat (counts 0),
  and runs the same chat again; while online it is kept for the retry rounds. Up to 2 rounds,
  `historyRetryGap` (15 s, `@visibleForTesting`) before each. Still left → one log line, they
  fall back to the chat-open fetch (D8). With `net == null` a left chat is only logged, as before.
- `[Sync] total` gains `left= rounds= waitedMs=`; `ms` excludes the offline waits **and** the
  retry gaps (both counted in `waitedMs`).
- One log line when the wait starts (`[Sync] offline: N chats left, waiting`): if the app is
  closed while offline, that is the count that falls back to the chat-open fetch (D8).
- **R5** per chat: `Future.wait` of the key step (`_historyKeys`, the G1 retry loop moved out
  unchanged), `_tickIndex(..., members: local)` and page 1 (`_historyPage`); page 1 is cached once
  all three are in, pages 2+ follow one by one. Tick members come from local rows
  (`getMembersForConversation`: `left` excluded, me removed); the SSE and reconcile paths still call
  `_tickIndex` without `members` and keep the request. No per-chat deleted/starred: one
  `_syncDeletedForMeUser` and one `_syncStarredMessagesUser` after the retry rounds, before
  `complete`.
- `[Sync] chat` `requests=` now counts receipts pages + message pages + group-key walks
  (`encryption.groupKeyWalks` delta). Shortcut noted in code: the delta counts any walk started
  meanwhile; exact while the sync is the only walker (R4).
- **R4 step 4** `prefetchGroupKeys` returns at once while `_historySyncRunning`.
- **R2** `_syncConversations` is a single-flight wrapper (`_convPass`, `_convRerun`,
  `_convQueued`) over `_syncConversationsPass`: a call during a pass waits; all such calls are
  answered by exactly one more pass; a rerun re-reads `_myId()` (the account may have changed).
  Memberships: `getFullList` (no 30-row cap). Other members: one `getFullList` per 40
  conversations with `(conversation_id="a"||…)&&user_id!="<me>"`, `expand: user_id`,
  `batch: 500`, grouped by `conversation_id`. All member requests run before any write, so a
  failed request still ends the pass with `[Conv] sync: <error>` and writes nothing (as before,
  now for the whole pass rather than the rest). `[Conv] sync chats= members= requests= ms=
  queued=` (no ids) after the loop.
- **R3** the local member ids are read before the pass writes any row of that conversation;
  `_maybeScheduleRotate` runs only when that set is non-empty (the phone already knew the
  conversation). `_rotateGroupKeyNow` logs `[Group] rotated v<n> members=<k> ms=<t>` on success.

`lib/services/encryption_service.dart`

- **R4** the network part of `getOrFetchGroupKeyCandidates` moved into `_walkGroupKeys` (request,
  G2 unwrap, G3 slot writes, base slot), returning `_GroupKeyWalk(newestVersion, newestKey,
  candidates)`. `_sharedGroupKeyWalk` keeps one in-flight walk per group; joiners await it. Each
  caller still applies its own G4 check (before joining), `requireCurrent` check, merge with its
  own cached candidates and `onGroupKeysRefreshed`. The G6 line gains `joined=`.
- **D4** `_groupKeyWalkedAt` is set when a walk opens a key; `_scheduleGroupKeyRefresh` skips a
  group walked in the last 60 s (`groupKeyFreshFor`). Send paths and `refreshFromServer` callers
  never skip. Cleared in `clearAllGroupKeyCache` (sign-out / account switch). Clock seam:
  `@visibleForTesting now`.
- `groupKeyWalks`: walks started (for the `[Sync] chat` request count).
- Found while building: `whenComplete(() => map.remove(id))` returns the removed Future, and
  `whenComplete` awaits a returned Future, so the walk waited on itself (every group-key test hung).
  The callback has a block body, with a comment.

`lib/features/auth/screens/backup_pin_screen.dart`

- Passes `ref.read(connectivitySignalProvider)` to the sync.
- `RestorePhase.waitingForNetwork`: cancels the 100 ms progress timer and drops the pending paint
  (a queued download paint would otherwise overwrite the pause), stores `chatsLeft`.
- The card line is `offlineRestoreLine(n)` ("You're offline. 3 chats left. We'll carry on when
  you're back.", "1 chat" singular) in a live region; a **Finish later** text `AppButton` replaces
  "Keep the app open…" while offline and calls `context.go(AppRoutes.home)` without touching the
  sync. The capybara stays docked in the vault pose with `CapyMood.sleepy`; envelope filing stops
  (it runs only while downloading). The saving card's icon switch has a `wifi_off` case.
- Back online, the sync's `downloadingMessages` progress for the left chat returns the card to
  "Downloading messages…" with "i of N chats".

## Tests

New `test/offline/restore_rev2_test.dart` (charHarness; one MockClient server with a request log,
arrival times, an optional per-answer delay and a hook; `ConnectivitySignal` over a fake
`Connectivity`; a dropped connection is `http.ClientException`, which the SDK reports as status 0):

1. Gate 1: 5 chats, the server drops and the fake goes offline at chat 3's page 1 →
   `waitingForNetwork` with `chatsLeft` 3, no `complete` 100 ms later; back online → every chat
   has its 3 rows once, `complete` once.
2. Gate 2: chat 2 drops twice, signal online → 3 page-1 requests for it, rows land, `complete`
   once (`historyRetryGap` 20 ms instead of fake async).
3. Gate 3: chat 2 answers 403 → 1 request for it, the others land, `complete` once.
4. Gate 4: no signal, chat 2 drops → 1 request, 0 rows for it, never `waitingForNetwork`.
5. Gate 6: 26 chats × 3 members → 2 `conversation_members` requests; 45 → 3; member rows (id,
   user, role) and user rows (public key) per chat as the fixture says; a 45-chat run with long
   ids keeps every filter under 3500 characters.
   Deviation: the spec's "compare with a fixture run through today's code path" is an explicit
   expected-rows table instead (today's code path is gone after the change).
6. Gate 7: four calls (one, then three during its pass, 40 ms answers) → 2 membership lists,
   pass 2's list after pass 1's member request, all four futures complete.
7. Gate 8: 35 memberships → 35 conversations stored.
8. Gate 9: fresh install, admin, smallest admin id, 3 other members → no `group_keys` POST in
   3.4 s (real wait, past the 3 s debounce; fake async does not drive Drift). A phone that knew
   the group (me + u_x) sees u_y → a rotation with 3 POSTs.
9. Gate 10: two plain callers and one `requireCurrent` caller of a cold group (v2 dead, v1 good)
   → 1 request; both plain callers get `[v1]`; `requireCurrent` throws `MissingKeyException`.
10. Gate 11: fake clock: refresh 30 s after a good walk → 0 requests; 61 s → 1; `requireCurrent`
    right after → 1 more.
11. Gate 12: page 1 held after the sync's own walk answered; `prefetchGroupKeys` → no request;
    after the sync it walks again (the guard lifts).
12. Gate 13: every answer 300 ms late; the chat's key, receipts and page-1 requests all leave
    within 300 ms of its first one; ticks read / delivered / sent as the receipts say, 6 rows.
13. Gate 14: memberships + one member list are the only member requests; a 3-member group's own
    message with one read receipt stays `sent`, with both it is `read`.
14. Gate 15: 5 chats → 1 deleted and 1 starred request, both after the last messages request;
    chat 4's rows are flagged when `complete` is reported.
15. Gate 16: a 429 on page 1 → 2 page-1 requests, rows land.

`test/auth/restore_overlay_test.dart`: gate 5, two widget tests (offline line + sleepy vault
capybara + Finish later → Home while the fake sync still waits, then progress and completion after
the screen is gone throw nothing; back online the label returns). The fake `_Sync` takes `net`.

`test/auth/backup_secret_screen_test.dart`: the fake `_Sync` takes `net` (signature only).

`test/offline/history_sync_test.dart` gate 2: the history sync now sends **no** `conversation_id="g1"`
member list (was 1). R5 step 2 removes that request on purpose; the spec lists this file as
"must stay green" and gate 14 asks for 0, so the count assertion follows gate 14. Ticks are
unchanged (the seed has no other member rows, so the receipts present decide, as before).

## Not built / left

- Receipts failing with status 0 or 429 while page 1 succeeds still degrade that chat's ticks
  to `sent` (as before R5); only page and key failures leave a chat.
- The spec's "found while specifying" items (rotation `users.getOne` per member, key-pair guard
  at the top of `_rotateGroupKeyNow`, election never cancelling a set timer, the resume backfill
  overlapping the restore).

## Device check list (user, every sign-in)

Test account pair from two-device testing, never your real chats. Release build,
`--split-per-abi` arm64. Log:
`adb logcat | grep -E "\[Sync\]|\[Conv\] sync|group keys|\[Group\] rotated"`.

1. M52 on **mobile data**, clear app data, sign in, restore. "Full history sync starting" to chat
   1 **under 5 s**; one `[Conv] sync` line with `requests=2`; **no** `[Group] rotated` line.
2. Redmi on **mobile data** (hotspot), same steps: restore to Home **under 60 s** (stopwatch from
   Restore; the clean rerun before this build was 76.6 s). One `group keys` line per group, each
   under 1 s. Small chats' `[Sync] chat` lines about 1.5–2 s. If the total is still over 60 s,
   note the `[Sync] chat` lines: that is the input for D10 (several chats at once).
3. Same run: open three chats with a starred message and one with a message deleted for you: star
   and deletion are there.
4. Same run: after Home, wait 30 s: no new `group keys` lines.
5. Redmi again, clear data, restore; at chat 5 or so turn the M52's hotspot off: the screen shows
   the offline line and Finish later, and stays. Turn the hotspot on: it carries on and goes Home.
   Open the chats that were left: full history there before opening, nothing doubled.
6. Same as 5, but tap Finish later while offline: Home at once; turn the hotspot on, wait a minute,
   open a chat that was left: its history is there.
7. M52: send a message in two groups from each phone: the other phone reads it. In one test group,
   remove the other phone's account and add it back: new messages read on both (a real join still
   rotates: one `[Group] rotated` line on the admin's phone).
8. Restore with the M52 account switching to another app and back on the recovery-key screen (copy
   the key from where you keep it): step 1's numbers still hold.

## Device run 1 (2026-11-14, release arm64, logs read by Claude)

"Sync time" = `[Enc] Private key successfully restored` to the router reaching Home. The
stopwatch from Restore adds the key check before that.

| # | Phone, run | From the logs | Verdict |
|---|---|---|---|
| 1 | M52, 11:03 | conversations step 1.5 s, `requests=2`; chat 1 done 3.6 s after the start; no `[Group] rotated`; 26 chats, 660 msgs, sync time **56.9 s** (chat loop 55.4 s, 77 requests) | PASS |
| 2 | Redmi, 11:06 | conversations step 2.4 s; 17 chats, 549 msgs, sync time **48.8 s** (was 76.6 s); later chats 0.3–2.2 s | PASS on the target. Chats 1–3 took 5–7 s: the light resume after sign-in (`resync light — delta convs=17`) was backfilling every chat 3 at a time and walked 8 cold groups at once next to the sync (3–6 s walks). This is the spec's "resume backfill overlaps the restore" follow-up, on the light path |
| 3 | Redmi | stars / deleted-for-me: not in the logs | user to confirm |
| 4 | M52 run 1, Redmi run 1 | no `group keys` line for 2.5 min (M52) and 54 s (Redmi) after Home | PASS. Redmi run 2 did walk 2 groups 1.5 s after Home: its offline wait (104 s) pushed those groups past the 60 s window (D4, as designed) |
| 5 | Redmi, 11:09 | offline at chat 5 (`13 chats left`), resumed at 11:10:15; offline again at chat 14 (`4 chats left`), resumed 11:11:46; `left=0 rounds=0 waitedMs=104164`, work time 59.1 s | PASS for the pause/carry-on; "nothing doubled" for the user |
| 6 | Redmi, 11:11:05–11:11:19 | about 20 Finish later taps, each `location: /home` → `/backup-pin/restore` | **FAIL**, fixed below |
| 7 | both | no `[Group] rotated`, no removal or join lines in either log | not seen: user to say whether the remove/re-add was done and on which phone |
| 8 | M52, 11:14 | app switches on the key screen started passes; the sync's own pass waited for one and its rerun (`queued=1`, `queued=2`, never two at once); chat 1 started ~5.5 s and finished 8.0 s after the start; sync time **62.7 s** | borderline miss on "under 5 s"; single-flight did its job, the light resume's work around it costs ~3 s |

### Fix: Finish later went straight back to the restore screen

The router's key-sync gate still held `needsRestore` from before the key came back, so
`go(home)` was redirected to `/backup-pin/restore`. The restore screen only re-checks it
(`invalidate(encryptionSyncProvider)`) when the sync ends. Finish later now invalidates it first
(the key is on the phone, so the re-check answers keyOk; while it loads the router shows the
splash), then goes Home. The sync is untouched. `restore_overlay_test` gate 5 now runs with a
redirect that applies the gate's rule (a settled `needsRestore` sends `/home` back) and an
`encryptionSyncProvider` override (needsRestore, then keyOk); it fails without the fix.

## Device run 2 (2026-11-14, the build with the Finish later fix, installed 11:20:52)

| # | From the logs | Verdict |
|---|---|---|
| 6 | Redmi 11:25: offline at `12 chats left` (11:25:35); Finish later at 11:25:37 → `location: /home` and it stayed there (no `/backup-pin/restore` after it). The sync carried on in the background when the connection came back and finished at 11:27:58 with `left=0`, `waitedMs=100530`, 558 msgs | PASS |
| 7 | M52 (admin) removed the Redmi account from a test group at 11:28:47 → `[Group] rotated v25 members=2`; added it back → `[Group] rotated v26 members=3` (11:29:19). Redmi: "You were removed from this group" (11:28:55), then the group back (11:29:13); its walk then opened v26 (17 → 18 versions), it sent a message there and the M52 received it | PASS (user confirmed too) |
| 3, 5 | not visible in the logs | PASS, the user's word (round 2) |
