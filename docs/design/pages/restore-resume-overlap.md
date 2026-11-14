# Restore and resume: the resume catch-up waits while the first history download runs (spec, rev 1)

Status: **spec PASS 2026-11-14, all defaults (D1 A, D2 same as D1 A, D3 stop at the next chunk, D4 A).** Follow-up to
`docs/design/pages/restore-rev2.md` (R1–R5, commit `4cae195`, device PASS
2026-11-14), "Found while specifying", last item. Evidence from
`docs/design/pages/restore-rev2-work-log.md`, "Device run 1", items 2 and 8.
No live server change and no server read are needed.

Target: **nothing but the restore's own download talks to the server while it
runs.** Measured cost of today's overlap: Redmi chats 1–3 took 5–7 s instead of
about 2 s (sync time 48.8 s); M52 chat 1 started about 5.5 s after the start
(target under 5 s), about 3 s of it waiting for resume work.

## Why (code read, 2026-11-14)

### What happened on the two phones

| Phone | What the log showed | What caused it |
|---|---|---|
| Redmi (run 1, item 2) | Right after sign-in: `resync light — delta convs=17` (every chat). The resume backfilled chats 3 at a time and walked 8 cold groups at once next to `syncAllHistory` (walks 3–6 s). Chats 1–3: 5–7 s. | Google sign-in leaves the app for the account picker, so coming back is a resume under 60 s: the **light path**. On a fresh install there are no local messages, so `_deltaBackfillTargets` has no watermark and returns **every membership** (`message_repository_impl.dart:4516-4521`). The light path then backfills all 17 chats (`:4454`). |
| M52 (run 1, item 8) | App switches on the recovery-key screen started conversation passes. The sync's own pass waited for one and its rerun (`queued=1`, `queued=2`). Chat 1 started ~5.5 s after the start. | Every resume runs `_syncConversations` (`:4440`) before anything else. R2's single-flight (`:6374`) did its job (never two at once), but the sync's call was folded into the rerun **after** the resume's pass, so it waited for both. |

### What a resume does today (`_resyncRun`, `:4412-4504`)

Called from `app.dart:70` (cold start, `awayFor` null → full path) and
`app.dart:104` (every return to the app; under 60 s → light path).
`resyncOnResume` (`:4397`) is single-flight against itself only.

| Step | Light path | Full path | Talks to the server | Useful during a restore? |
|---|---|---|---|---|
| `_reconnect()` SSE re-subscribe | yes | yes | yes | **Yes.** Android drops the socket in the background; without it no live message arrives until the next reconnect. |
| `prewarmHomePreviews` | only if the body cache was purged | yes | no (local decrypt) | Only after Finish later (Home is visible). Local and unawaited. |
| `_syncConversations` | yes | yes | yes (2 requests, R2) | No: the sync runs its own pass first thing. |
| Delta discovery (`_deltaBackfillTargets`) | yes | no | yes | No: the sync fetches every chat. |
| `prefetchGroupKeys` | no | yes | yes | No: already returns at once while the sync runs (R4, D5). |
| `_backfillTargets` → `_fetchAndCacheMessages` per chat, 3 at a time | targets only | every chat | yes: newest 40 rows + key step (group walk) + deleted, starred, receipts (**about 5 requests per chat**) | **No.** On a fresh install the sync fetches every row of every chat (pages of 200) a moment later; ingest is idempotent, so the backfill's rows are thrown away work. |
| `_syncDeletedForMeUser`, `_syncStarredMessagesUser` | yes | no | yes | No: the sync runs both once at its end (R5). |
| `_reconcileReceiptsUser` | yes | no | yes | No: the sync builds each chat's ticks from its receipts (tick index). |
| `_reconcileGroupKeyGaps` | no | yes | yes (2 per admin group) | No: nothing to reconcile before the history is in. |
| `retryPendingMessages`, join emits | yes | yes | only if something is queued | **Yes after Finish later**: the user can send from Home while the sync still runs. |

### Two kinds of "during the restore"

1. **On the recovery-key screen, before Restore is tapped.** There is no device
   key pair yet (`EncryptionService._readKeyPair`,
   `lib/services/encryption_service.dart:216`; G4 throws
   `no device key pair (restore pending)` at `:694`). Anything the resume
   fetches lands as `key_missing` and the sync redoes it. The router keeps
   Home hidden. Nothing is lost by skipping the server work: the SSE reconnect
   makes the connection live again, and the sync, which starts later,
   downloads everything up to that moment. If you choose "start fresh"
   instead, messages from before the new key cannot be read on this phone
   anyway.
2. **While `syncAllHistory` runs** (`_historySyncRunning`, `:3360`, set at
   `:3370`, cleared in `finally` at `:3542`): the download itself, and after
   Finish later, the background download on Home (rev 2 R-B4). Chats the sync
   **has not reached yet** get everything when it reaches them. Chats it
   **already finished** can miss a message sent while the app was in the
   background, because SSE does not replay. That is the only gap if the resume
   just waits.

## Behaviour (what you see)

| # | Case | After this build |
|---|---|---|
| O-B1 | Sign in with Google, then restore | Same screens. Chats 1–3 download as fast as the rest (about 2 s on the Redmi). |
| O-B2 | Switch apps on the recovery-key screen (copying the key), then Restore | Chat 1 starts within the target (under 5 s on the M52). |
| O-B3 | Switch apps during the download, and someone writes to a chat that has already downloaded | When the download ends, that chat's message shows on Home (preview and unread count) without opening it. |
| O-B4 | Finish later, then use Home while the download carries on | Sending and receiving work as today. Switching apps and back does not start a second download next to it. |
| O-B5 | Every resume after the restore has ended | Unchanged (light under 60 s, full otherwise). |

## Changes

### O1: a resume during the restore reconnects and does local work only (D1 A, D2)

In `_resyncRun`, right after `_reconnect()` and `_myId()`:

1. If `_historySyncRunning` is true, or the device has no key pair (D2), the
   resume **skips every server step** in the table above. It still runs the
   local ones: `prewarmHomePreviews` (same condition as today),
   `retryPendingMessages` and the join-emit retries.
2. The key-pair check is a new read-only `EncryptionService.hasDeviceKeyPair()`
   returning `_readKeyPair() != null` (one secure-storage read per resume).
   No new state: the key pair already is the "restore pending" signal G4 uses.
3. One log line, no ids: `[Msg] resync deferred — reason=sync|nokey path=light|full`.
   The existing `resync done … total=` line still closes the run.

### O2: a backfill already running stops when the sync starts (D3)

In `_backfillTargets` (`:4560`): before each chunk of 3, if
`_historySyncRunning` is true, stop and log
`[Msg] resync backfill stopped — history sync, left=<n>`. The resume then
returns without the steps after the backfill (same rule as O1). This covers a
resume that started in the gap between the key coming back and the sync
setting its flag. Chats in a chunk already running finish; a chunk is never
cut in the middle.

### O3: one catch-up after the sync for chats a resume could have missed (D4 A)

1. `syncAllHistory` keeps the ids of chats it has finished in this run (a
   `Set<String>`, cleared at its start).
2. When O1 defers a resume because the sync runs (reason `sync`, not `nokey`),
   it adds the current finished set to an **owed** set.
3. In the sync's `finally`, after `_historySyncRunning = false`: if the owed
   set is not empty, take it, clear it, and run `_backfillTargets` on it
   unawaited (the restore screen does not wait; it is already Home or going
   there). Log `[Sync] owed catch-up chats=<n>`.
4. Each owed chat costs one `_fetchAndCacheMessages`: the newest 40 rows (rows
   already stored are dropped before decrypt, F2a) plus its deleted, starred
   and receipts passes. Nothing owed (the usual case) means nothing runs.
5. A sign-out clears the owed set with the rest of the session state.

## Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| D1 | What does a resume do while the history sync runs (O1)? | **A: SSE reconnect and local work only; server catch-up waits for the sync (O3)** · B: skip only the backfill, keep the conversations pass and the user-wide passes (the M52's wait stays) · C: today's behaviour |
| D2 | And on the recovery-key screen, before Restore is tapped (no device key pair)? | **Same as D1 A, nothing owed** · keep today's (the M52's ~3 s stays) · use a flag the restore screen sets instead of the key-pair check (more wiring; the key pair is already the signal) |
| D3 | A resume backfill that is already running when the sync starts (O2)? | **Stop at the next chunk of 3** · let it finish (the Redmi's 5–7 s chats stay possible when the timing lines up) |
| D4 | Catching up chats the sync finished before an app switch (O3)? | **A: after the sync, refetch only the chats it had finished at the switch** · B: after the sync, one full resume (every chat, about 5 requests each, plus key-gap reconcile) right as you land on Home · C: none: such a message shows when the chat is opened or on the next resume; the notification still arrives |

Considered and not offered: a light-path delta query after the sync. Its
watermark is the newest stored message, and during a sync rows land out of
time order, so a message missed in chat 1 can sit below a newer row from
chat 9 and be skipped.

## Expected (estimates, not measured)

- Redmi: chats 1–3 at about 2 s like the rest, so roughly 10 s off the 48.8 s
  sync time: **about 38–42 s**.
- M52: chat 1 about 2.5 s after the start (the ~3 s of waiting goes), sync
  time a few seconds under run 1's 62.7 s / 56.9 s.

## Found while specifying (not built here)

- The light path on a phone with no stored messages falls back to every chat
  (`_deltaBackfillTargets` `:4516`). After O1 that only happens outside a
  restore (an account with no history at all: one empty request per chat).
- The full resume's per-chat deleted, starred and receipts passes
  (`:4781-4784`, 3 requests per chat) could use the user-wide versions the
  light path already uses. Matters for every long-away resume, not the restore.
- SSE conversation and member events during the restore still start
  `_syncConversationsBackground` passes; R2's single-flight folds them, and
  the `[Conv] sync … queued=` line shows when one delayed the sync. Not changed.

## Must not undo

- SSE reconnect on every resume, during the restore too.
- Rev 2 R1–R5: offline pause and Finish later, the 2-request conversations
  pass and its single-flight, no rotation on first sight, one key walk per
  group, one round trip per chat.
- F2b light-path contract outside a restore (`short_resume_test.dart` A–C).
- `resyncOnResume` single-flight against itself.
- Chat-open fetch (`_fetchAndCacheMessages` from the chat screen, `:1075`) is
  never gated: opening a chat during a Finish-later download still fetches it.
- Session-epoch checks in `_fetchAndCacheMessages` (C1).

## Test gates

New, next to `test/offline/short_resume_test.dart` (char harness, MockClient,
its `ResyncFeed` request counters), and `test/offline/restore_rev2_test.dart`
for the sync side:

1. O1 sync: a sync held mid-chat by a MockClient completer; `resyncOnResume`
   with `awayFor: 5 s` and with null → **0** per-chat message fetches, **0**
   delta queries, **0** extra `conversation_members` requests from the resume;
   SSE re-subscribe count +1; a queued text in the outbox is retried.
2. O1 nokey: no device key pair, signed in, 3 memberships → same zeros; SSE
   re-subscribe +1; nothing owed (gate 5's counter stays 0 after a later sync).
3. O2: a full resume with 9 chats, first chunk held; start `syncAllHistory`;
   release the chunk → the resume fetched exactly 3 chats and no user-wide
   passes; the log has `left=6`.
4. O3: 5-chat sync; after chat 2 finishes, a resume (deferred); the server
   gains a new row in chat 1 → after `complete`, chats 1 and 2 are each
   fetched once more, the new row is stored, chats 3–5 are not fetched again.
5. O3 nothing owed: a sync with no resume → no message fetches after
   `complete`.
6. Gate releases: after the sync ends, a short resume runs the normal light
   path (1 delta query issued).
7. O3 + sign-out: owed set present, sign out before the sync ends → no fetch
   after it.

Existing, must stay green: `test/offline/short_resume_test.dart`,
`test/offline/restore_rev2_test.dart`, `test/offline/history_sync_test.dart`,
`test/auth/restore_overlay_test.dart`, `test/app_lock/presence_gate_test.dart`.
Full `flutter test` green against the baseline taken at build start;
`flutter analyze` 0 errors; `grep_gates_test.dart` green. Each new gate
mutation-checked (removing its guard fails it).

## Device check list (you do every sign-in)

Test account pair from two-device testing, never your real chats. Release
build, `--split-per-abi` arm64. Log:
`adb logcat | grep -E "\[Sync\]|\[Conv\] sync|resync|group keys|_fetchAndCacheMessages"`.

1. Redmi on **mobile data**, clear app data, sign in **with Google**, restore.
   After sign-in: `resync deferred — reason=nokey`, and **no**
   `resync light — delta convs=` line. Between `Full history sync starting`
   and `[Sync] total`: **no** `_fetchAndCacheMessages` lines. Chats 1–3 about
   2 s each; sync time under run 1's 48.8 s.
2. M52 on **mobile data**, clear app data, sign in, switch to another app and
   back twice on the recovery-key screen, then Restore: one
   `reason=nokey` line per switch; the sync's `[Conv] sync` line has
   `queued=0`; chat 1 starts **under 5 s** after the start.
3. Redmi, clear data, restore; around chat 5 switch away for about 20 s while
   the M52 sends a message into one of the first two chats:
   `reason=sync` on return; after `[Sync] total`, `[Sync] owed catch-up chats=`
   with a small number; on Home that chat shows the message and an unread
   count **before** you open it.
4. Redmi, clear data, restore; turn the hotspot off at about chat 5, tap
   Finish later, switch apps and back on Home, then send a message from Home
   and turn the hotspot on: the message goes out once; the download carries
   on and ends; no second download (`_fetchAndCacheMessages` lines) during it.
5. After any of the above, on Home: pull the notification shade and let go:
   `path=light` with `delta convs=0`; leave for over a minute and come back:
   `path=full` as before.

## Out of scope

The items under "Found while specifying"; history-sync S2 (batch decrypt),
S3 (Home early), S5 (several chats at once); any live server read or change;
any screen change.
