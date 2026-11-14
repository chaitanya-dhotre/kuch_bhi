# Restore rev 2: offline pause, conversations step, one key walk per group, fewer round trips per chat (spec, rev 1)

Status: **spec PASS 2026-11-14, all defaults (D1 A, D2 A, D3 skip, D4 60 s, D5 skip, D6 not now, D7 not needed, D8 chat-open fallback, D9 A, D10 not in this build).** Follow-up to
`docs/design/pages/history-sync.md` (S1 + S4) and
`docs/design/pages/group-key-restore.md` (G1–G6), both built and uncommitted.
Four problems from the 2026-11-13 device runs of the G1–G6 build (release,
mobile data; Redmi on the M52's hotspot). Logs from those runs were not kept;
the numbers below are the ones quoted from them. No live server change and no
server read are needed for this build (D7 asks whether you want one).

Target stays: **restore to Home under 60 s on the Redmi over mobile data.**
The clean Redmi rerun (12:31, nothing interrupted) missed it: **76.6 s**
(conversations step ~7 s, chat loop 69.4 s; 17 chats, 540 messages,
51 counted requests), the same as history-sync run 2 (75.1 s). G1–G6 removed
the dead-version spikes; what is left is round trips one after another (P4).

## Why (code read, 2026-11-13)

### P1: going offline mid-restore goes Home early

At 12:23:17 the Redmi's Wi-Fi (the hotspot) was turned off mid-restore.
`syncAllHistory` (`message_repository_impl.dart:3353-3480`) wraps each chat
in its own `try` and only logs a failure (`:3466`,
`[Sync] conversation <id> failed: ClientException … Failed host lookup`), then
moves to the next chat. Offline, every remaining chat fails within about
1.5 s (the key step's 400 + 800 ms retry sleep, then the tick index throws).
The loop ends with 9 of 17 chats done, reports `complete`, and the restore
screen goes Home (`backup_pin_screen.dart:401-449`). The 8 failed chats'
history only arrives when each chat is opened.

What the app already has for connectivity:

| What | Where | Notes |
|---|---|---|
| `ConnectivitySignal` (+ `connectivitySignalProvider`) | `lib/infrastructure/offline/connectivity_signal.dart` | `isOnline` + a `changes` stream. Fail-safe default online. The only sanctioned `connectivity_plus` user outside the outbox (grep gate 13: `lib/infrastructure/` only). Takes a `Connectivity` for tests. |
| `isOnlineProvider` | same file `:63` | The restore screen already watches it to disable Restore and show `OfflineActionHint` (`backup_pin_screen.dart:160`, `:484`, `:661`). |
| `invalidateOnReconnect` | same file `:72` | Re-runs a provider on an offline → online flip. |
| OutboxWorker's own listener | `outbox_worker.dart:152-155` | Calls `onConnectivityRestored` (reset attempts, drain). |
| Test fake | `test/offline/encryption_sync_offline_test.dart:142-183` | `_FakeConnectivity.goOnline()`, injected as `ConnectivitySignal(connectivity: net)`. |

"Connected" here means a network interface is up, not that the server
answers. The Redmi (no SIM) losing the hotspot reports `none`, so the signal
sees this case. Mobile data with no signal reports `mobile` while requests
fail, so the fix also needs a plain retry.

A network failure is easy to tell: the PocketBase SDK (0.21.0,
`client.dart:281-298`) throws `ClientException` with `statusCode == 0` for
anything that never got an HTTP answer (host lookup, reset, timeout);
server answers carry their status (403, 404, 500).

### P2: the conversations step before the chat loop

From "[Sync] Full history sync starting" to chat 1, with no log lines in
between: **M52 about 58 s (26 chats), Redmi about 9 s (17 chats)**, same
network (Redmi on the M52's hotspot). Chat 1's own time (2.6–4.7 s) is inside
that, so the step itself is about 54 s vs 6–7 s: about **2.1 s per chat on
the M52 and 0.4 s on the Redmi**, on the faster phone.

What `_syncConversations` (`:6247-6487`) does, all in one sequential loop:

| Cost | Count | Where |
|---|---|---|
| My memberships, conversation expanded | 1 request, **`getList`: first 30 rows only** | `:6253-6259` |
| Members of this conversation except me, user expanded | **1 request per conversation** | `:6337-6344` |
| Local reads and writes: conversation, my member row, each other member's user row and member row, stale-row cleanup | ~6 Drift calls + ~3 per member, each its own transaction | `:6283-6411` |
| `_maybeScheduleRotate` for every member **new to this device** | per member; on a fresh install that is **every member of every group** | `:6350-6360` → `:601-639` |
| Removal probe for a local membership missing from the list | 1 request each (none on a fresh install) | `:6428-6435` |

That gives about 27 requests for 26 chats: about 10–15 s at the hotspot's
350–400 ms round trip, not 54 s. The step's own work does not explain the
M52's 2.1 s per chat. Something else runs next to it on the M52. The code
offers three things that can, none of them guarded:

1. **Rotations started by the restore itself (most likely).** On a fresh
   install no member is known locally, so the step calls
   `_maybeScheduleRotate` for every other member of every group. For a group
   where this account is an admin and (from the rows seen so far) the
   smallest admin id, that schedules `_rotateGroupKey` 3 s later. Once the
   key pair is restored the rotation runs for real
   (`_rotateGroupKeyNow` `:3949-4036`): 1 member list, 1 version read,
   **1 `users.getOne` per member, 1 ECDH wrap per member, 1 `group_keys`
   create per member**, all sequential: about 12 requests for a 5-member
   group, several groups at once, on the same connection as the step. A
   rotation that succeeds logs nothing, so the run would not show it. Run 1
   logged `auto-rotate on join failed: … no device key pair`, which proves
   the scheduling happens at sign-in; whether a later one succeeded depends on
   whether the key pair was back by then. If the M52 account administers the
   test groups and the Redmi account does not, this alone fits the
   difference. It also fits the 14–19 key versions per group seen on
   2026-11-13: every fresh install of an admin adds one per group.
   The election has a second flaw on a fresh install: it reads admins from
   the local rows, which hold only the ones upserted so far, and a later
   "not the owner" answer does not cancel a timer already set.
2. **Overlapping passes.** `_syncConversations` has no single-flight. Each
   `conversations` or `conversation_members` SSE event
   (`_subConversations` `:573-579`, `_subMembers` `:585-598`) and every
   resume (`resyncOnResume` → `_resyncRun` `:4332`) starts a full pass. A
   Google sign-in or a switch to another app to copy the recovery key causes
   a resume on the restore screen. A pass started then is still running when
   Restore is tapped (54 s at the M52's pace), and the full resume path also
   backfills every chat (`_backfillTargets` `:4452`) at the same time.
3. **Group-key walks** from the prefetch that each pass starts
   (`_syncConversationsBackground` `:809-820`), see P3.

Without logs the share of each cannot be measured. The fix removes all
three (R2, R3, R4) and adds lines that show them (R2 step 4, R3 step 3).

### P3: duplicate group-key walks

On the Redmi run with the network cut: **43 `[Enc] group keys` lines
(walks)** for a 17-chat account. A walk of one group alone took 0.5–0.9 s;
walks of one group that overlapped took **3–5 s** (one request each, but the
phone's secure storage and the `compute()` isolates are shared, and the
Redmi's CPU is slow). The clean rerun had **16 walks** (14 during the sync,
0.8–1.7 s, median 1.1 s): no storm. So the duplicates come mostly with
failures and retries (the cut run), not with every restore. R4 is still in
because the code allows them and they cost most exactly when the network is
bad, but it is not what stands between the Redmi and 60 s; P4 is.

Who walks a group during a restore (no shared in-flight state between them):

| Walker | When | Guard today |
|---|---|---|
| The sync's own key step | Once per group (up to 3 on a dropped connection, G1) | none |
| `prefetchGroupKeys` (`:925-963`) | Every group still cold; started by every `_syncConversationsBackground` (each SSE conversation or member event) and the full resume | `_prefetchKeysInFlight` blocks a second prefetch **run**, not a later one, and not the sync walking the same group |
| Background refresh (`_scheduleGroupKeyRefresh`, `encryption_service.dart:513-529`) | Any non-send key call that finds the group warm: so as soon as the prefetch warms a group, the sync's own call becomes "local-first + refresh walk"; Home's preview prewarm right after the restore does it again for every group | `_groupKeyRefreshInFlight` dedupes refresh against refresh only |
| A rotation (P2 cause 1) | Reads keys through the send path | none |

So a group can be walked by the prefetch, then again by the sync's refresh,
then again at Home, and two of those at once. This is group-key decision D3
("single-flight per group: not now, add only if the G6 line shows two walks
of one group at once"), now with that evidence.

### P4: every chat waits for its round trips one by one

Clean Redmi rerun: chats took 0.9–7.1 s, mostly 3–4 s, at about **1 s per
round trip** over the hotspot. In `syncAllHistory` (`:3372-3467`) each chat
does, strictly one after another:

| Round trip | Needs the one before? | Where |
|---|---|---|
| Key step (groups: `group_keys` walk; DMs: peer key, usually local) | no | `:3376-3389` |
| Tick index: receipts list | no | `_tickIndex` `:5807` |
| Tick index: member list (`_requiredRecipients`) | no; the conversations step fetched the same members seconds before | `:5835-5849` |
| Message page 1 (then 2, 3… for chats over 200) | no for page 1; each later page waits for the one before | `:3399-3434` |
| Deleted-for-me list for this chat | only on the rows having landed | `_syncDeletedForMe` `:5077` (`:3463`) |
| Starred list for this chat | same | `_syncStarredMessages` `:5139` (`:3464`) |

So a group chat costs 6 round trips and a DM 5, about 5–6 s at this link,
before any decrypt. 17 chats × ~4 s is the 69 s chat loop. Only the page
sequence truly has to wait; the rest is waiting by habit. The last two
already have user-wide versions, one request for every chat
(`_syncDeletedForMeUser` `:5211`, `_syncStarredMessagesUser` `:5264`, used
by the light resume), and the member list is already on the phone.

## Behaviour (what the user sees)

| # | Case | After this build |
|---|---|---|
| R-B1 | Restore, online throughout | Same screens and steps. The "Loading your conversations…" step takes a few seconds on both phones; each chat takes about one round trip plus its decrypt; Redmi on mobile data under 60 s. |
| R-B2 | Connection lost mid-restore | The capybara stays; the line reads "You're offline. 8 chats left. We'll carry on when you're back." with a **Finish later** button. Nothing is skipped. |
| R-B3 | Connection back | Carries on by itself from the chat that failed; goes Home when every chat is done. |
| R-B4 | Finish later | Home at once. The download carries on in the background while the app stays open and fills the chats in when the connection is back (D8). |
| R-B5 | Connected but the server cannot be reached (mobile data, no signal) | Failed chats are retried at the end, up to 2 more rounds 15 s apart, then Home as today. |
| R-B6 | A chat the server refuses (403, 404) | Not retried; logged; same as today. |
| R-B7 | Group admin restores on a new phone | No group key changes because of the restore. Real joins still rotate as today. |
| R-B8 | Group history, ticks, sending | Unchanged. |

## Changes

### R1: pause on a lost connection, carry on when it is back (D1 A)

In `syncAllHistory`:

1. New optional parameter `ConnectivitySignal? net`. Null keeps today's
   behaviour exactly (every existing caller and test). The restore screen
   passes `ref.read(connectivitySignalProvider)`. The repository and the
   signal are both in `lib/infrastructure/`, so gate 13 holds and the
   repository stays free of Riverpod.
2. A chat is **left** (kept for later) when it throws `ClientException` with
   `statusCode == 0` or `429` (the server's rate limit, seen before on
   receipts; R5 sends requests closer together), or when its key step ends
   empty while `net.isOnline` is false (the key step wraps the network error
   as a missing key). Any other failure is logged and skipped as today
   (R-B6).
3. When a chat is left and `net.isOnline` is false: report the new phase
   `HistorySyncPhase.waitingForNetwork` with `chatsLeft` (the left chat plus
   every chat not started), then wait for `net.changes` to say online. Then
   carry on: the left chat first, then the rest. Waiting offline has no time
   limit; Finish later is the way out.
4. When a chat is left but the signal says online (R-B5): go on to the next
   chat. After the loop, retry the left chats in order, up to 2 more rounds
   with 15 s between rounds (step 3 applies if the signal goes offline
   during a round). Still left after that: logged, the sync completes, and
   they fall back to the chat-open fetch, as today.
5. A retried chat is fetched again from page 1. Ingest is idempotent
   (`idempotent_ingest_test.dart`), so rows that landed before the drop are
   not doubled.
6. The `[Sync] total` line gains `left=<n> rounds=<n> waitedMs=<n>`
   (waiting time is not counted in `ms`).

On the restore screen (`backup_pin_screen.dart`):

7. New `RestorePhase.waitingForNetwork`: line "You're offline. {n} chats
   left. We'll carry on when you're back." (singular "1 chat"), the capybara
   in the vault pose with the existing `CapyMood.sleepy` (no new Rive work),
   and a **Finish later** text button under it.
8. Finish later goes Home (`context.go(AppRoutes.home)`) without cancelling
   the sync; the sync already outlives the screen (`:415-418`). Progress
   reports stop at `!mounted`, as today.
9. When the connection comes back on the screen, the phase returns to
   downloading and the progress label picks up from the left chat.

### R2: the conversations step in 2 requests

In `_syncConversations`:

1. My memberships: `getFullList` (same filter, expand and sort) instead of
   `getList`, so an account in more than 30 chats gets them all.
2. Other members (D2 A): **one** `conversation_members.getFullList` per 40
   conversations, filter
   `(conversation_id="a"||conversation_id="b"||…)&&user_id!="<me>"`,
   `expand: 'user_id'`, `batch: 500`, grouped by `conversation_id` in memory.
   40 ids keep the filter well under PocketBase's filter length cap (the
   build confirms the cap for the server's version from its source, not the
   live server). The list rule is the same one each per-chat request passes
   today, so no rule change. The per-conversation local work is unchanged
   and reads its rows from the map; a conversation with no rows in the answer
   is treated exactly as an empty per-chat answer is today.
3. Single-flight for the whole pass: a call that arrives while a pass runs
   waits for it; if any call arrived during the pass, exactly one more pass
   runs after it, and every waiting caller completes with that one. A member
   event that lands mid-pass is never lost, and two passes never run at once.
4. One timing line per pass, no ids:
   `[Conv] sync chats=26 members=74 requests=2 ms=1800 queued=1`
   (`queued` = calls folded into this pass).
5. A failed request still ends the pass with `[Conv] sync: <error>` and no
   writes for the rest, as today.

Expected: 26 chats in 2 requests instead of 27, about 1–3 s of local work,
and nothing running next to it once R3 and R4 are in.

### R3: no join rotation on first sight (D3)

1. In `_syncConversations`, call `_maybeScheduleRotate` for a new member only
   when this device already had member rows for that conversation before this
   pass. First sight of a conversation (a fresh install, or a group just
   joined) schedules nothing. A real join still rotates: the SSE create event
   (`_subMembers`) on an admin's phone, the sync-discovery path on a phone that
   already knew the group, and the key-gap reconcile on resume
   (`_reconcileGroupKeyGaps` `:4468`) for a member who still lacks the current
   key.
2. Same rule fixes the fresh-install election (P2 cause 1): no timer is set
   from a partial admin list.
3. `_rotateGroupKeyNow` logs one line on success:
   `[Group] rotated v<n> members=<k> ms=<t>` (no ids), so the device check
   and later runs can see rotations.

### R4: one key walk per group at a time (D3 of the group-key spec, now yes)

In `EncryptionService`:

1. Single-flight for the network walk: `Map<String, Future<…>>` keyed by
   conversation. A caller that arrives while a walk of that group runs awaits
   the same walk instead of starting one. The shared part is the request,
   the unwrap and the slot writes (G2, G3). Each caller then applies its own
   `requireCurrent` check and merge with its own local candidates, so the
   send path keeps its rule (G-B3).
2. Freshness window (D4): a background refresh (`_scheduleGroupKeyRefresh`)
   is skipped when a walk of that group succeeded in the last **60 s**
   (in-memory timestamp per group, cleared with the key memory on sign-out).
   Send paths (`requireCurrent`) and explicit `refreshFromServer` callers
   never skip.
3. The G6 line gains `joined=<n>` (callers that shared this walk); a skipped
   refresh logs nothing.

In `MessageRepositoryImpl`:

4. `prefetchGroupKeys` returns at once while `syncAllHistory` runs (D5): the
   sync walks every group itself, one at a time.

Expected on the Redmi: one walk per group during the restore, 0.5–0.9 s
each instead of up to 3–5 s; no second walk at Home within 60 s.

### R5: one round trip per chat (D9 A)

In `syncAllHistory`, per chat:

1. Start the key step, the receipts list and message page 1 **at the same
   time** (`Future.wait`); cache page 1 once all three are in (the key and
   the tick index are inputs to `_cacheMsg`). Pages 2+ still follow one after
   another, as today. The G1 retry rule and R1's left rule apply to each part
   as they do now; one part failing fails the chat as today.
2. The tick index's member set comes from the local member rows this sync's
   own conversations pass (R2) wrote seconds before (members minus me, `left`
   rows excluded), not from a `conversation_members` request. Only inside
   `syncAllHistory`; the SSE and reconcile paths keep the request.
3. Deleted-for-me and starred: no per-chat calls. After the last chat (and
   after R1's retry rounds), **one** `_syncDeletedForMeUser` and **one**
   `_syncStarredMessagesUser` for the whole account, before `complete`. Both
   exist and are idempotent; the user-wide deleted list is a full list,
   where the per-chat one stops at 500.
4. The `[Sync] chat` line's `requests` now counts every request the chat
   made (key, receipts, pages), so the device check can read round trips
   directly; the total line adds the two user-wide ones.

Expected on the Redmi (clean rerun, 1 s per round trip): a chat costs about
one round trip plus decrypt instead of 5–6, so about 1.5–2 s instead of
3–4 s; chat loop about 25–35 s, plus about 3 s for the conversations step
(R2) and 2 s for the user-wide passes: **about 30–40 s**, an estimate, not
measured. Big chats still pay their extra pages and decrypt (159 messages
took ~6.6 s after the key in history-sync run 2); that is history-sync S2.

## Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| D1 | What happens when the connection drops mid-restore (R1)? | **A: pause on the restore screen and carry on when the connection is back, with a Finish later button; a reachable-but-failing network gets 2 retry rounds at the end** · B: retry the failed chats once at the end, then Home as today (no wait) · C: go Home at once and download in the background with a visible state on Home (that is history-sync S3 "Home early": a Home indicator and a stored to-do list, its own spec) |
| D2 | How to fetch other members in the conversations step (R2 step 2)? | **A: one request per 40 conversations with an `||` filter** · B: one request with a back-relation filter (`conversation_id.conversation_members_via_conversation_id.user_id ?= me`): one request at any size, but a heavier server query and it relies on the rule evaluating the back-relation the same way · C: keep one request per conversation, 4 at a time (still 26 requests) |
| D3 | Join rotation when the device sees a conversation's members for the first time (R3)? | **Skip it; real joins and key gaps are still covered** · keep today's (a new admin phone rotates every group it administers on every restore) |
| D4 | Freshness window for background key refreshes (R4 step 2)? | **60 s** · none (single-flight only; Home still walks every group once more right after the restore) · 5 min |
| D5 | Group-key prefetch while the history sync runs (R4 step 4)? | **Skip it** · keep it (single-flight stops duplicates, but walks of different groups still compete for storage and CPU on the Redmi) |
| D6 | One Drift transaction per conversation in the conversations step? | **Not now: R2's timing line shows whether local work matters once the requests are gone** · yes, now |
| D7 | Prove P2's cause with a read-only live check first (the M52 test account's `group_keys` rows created on 2026-11-13 and its admin roles)? | **Not needed: the device check's `[Group] rotated` and `[Conv] sync` lines answer it on the next run** · yes, before the build (needs your yes for the live read) |
| D8 | After Finish later, if the app is closed before the connection is back? | **The chats left fall back to the chat-open fetch, as today; one log line names how many** · store the list and resume on the next start (more code; overlaps D1 C) |
| D9 | Fewer round trips inside one chat (R5)? | **A: key, receipts and page 1 at once; members from the phone; deleted and starred once per account at the end** · B: only the overlap (step 1), keep the per-chat deleted/starred calls (2 more round trips per chat) · C: none |
| D10 | Download several chats at once (history-sync S5)? | **Not in this build: R5 is estimated at 30–40 s, under target with one chat at a time; build a pool of 3 only if the device check still misses 60 s** · yes, 3 chats at a time now (about 3× less waiting on top of R5, but: the progress label becomes "chats done" instead of "chat i of N"; R1's pause has to stop every worker; group walks of different chats compete for the Redmi's secure storage and CPU, which made overlapping walks 3–5 s on 2026-11-13; up to 3× the request rate against the server's rate limit, unknown without a live read; more test surface) · yes, 4 at a time (same costs, more of them) |

## Found while specifying (not built here)

- Rotations wrap for each member with a `users.getOne` per member
  (`:3984`): one `users` list with an `||` filter would cut a 5-member
  rotation from about 12 requests to about 8. Matters for real joins and
  removals, not the restore once R3 is in.
- `_rotateGroupKeyNow` reads members and every member's user record before
  failing on a missing device key pair (group-key spec, "Rotate-on-join
  before the restore"). R3 stops the restore from reaching it; a key-pair
  check at its top is still the cheap guard.
- `_maybeScheduleRotate`'s election (`:601-639`) still never cancels a set
  timer when a later call finds another owner. R3 removes the fresh-install
  case; a phone that knew the group can still hit it after a missed admin
  change.
- The key step wraps a network error as a missing key
  (`_getConvKeyCandidates` `:6217`), so offline it sleeps 1.2 s per chat
  before failing. R1 copes without changing it.
- The full resume path backfills every chat (`_backfillTargets`) even while
  a restore is downloading the same chats. R2's single-flight covers the
  conversations pass, not this. If the device check still shows overlap, a
  "restore running" check in `_resyncRun` is the next step.

## Must not undo

- History rows land even when no key opens (history-sync H5, Task 7).
- G1–G6 (group-key spec): one walk when the server answered, batch unwrap,
  write only changed slots, no walk without the key pair, `fields`.
- Send path: `requireCurrent` still refuses a stale key (G-B3).
- The §7 false-removal guard: a conversation missing from the membership list
  is probed before it is marked left (`:6420-6487`).
- Rotation serialisation per group (`SerialPerKey`, `_rotations`).
- The restore screen's progress throttle (100 ms timer, history-sync S4) and
  K1b's capybara poses.
- Session-epoch bail-out inside the conversations loop (`:6262-6271`).

## Test gates

New, next to `test/offline/history_sync_test.dart` and
`test/offline/group_key_restore_test.dart` (charHarness, MockClient server,
`ConnectivitySignal` over a fake `Connectivity` like
`encryption_sync_offline_test.dart`):

1. R1 offline: 5 chats, the server drops (statusCode 0) from chat 3 on and
   the fake goes offline → progress reports `waitingForNetwork` with
   `chatsLeft = 3` and the sync does not complete; `goOnline()` and the
   server back → chats 3–5 land, then `complete`. No chat's rows doubled.
2. R1 online-but-failing: chat 2 fails with statusCode 0 twice, then works,
   signal online throughout → chat 2 lands in round 2, `complete` once
   (fake async for the 15 s gaps, or an injectable delay).
3. R1 refused: chat 2 answers 403 → not retried (1 request for it), sync
   completes.
4. R1 no signal passed → identical to today (existing `history_sync_test`
   cases unchanged).
5. Restore screen: `waitingForNetwork` shows the offline line and Finish
   later; tapping it goes Home while the fake sync is still waiting; the sync
   then completes without touching the disposed screen.
6. R2: 26 conversations, 3 members each → exactly **2** `conversation_members`
   requests (memberships + one members list); 45 conversations → **3**;
   local member rows and user rows identical to the per-chat version
   (compare with a fixture run through today's code path).
7. R2 single-flight: three calls during one pass → 2 passes total, all three
   futures complete; no two passes overlap (request log ordering).
8. R2: 35 memberships → all 35 conversations stored (the 30-row cap is gone).
9. R3: fresh install, this account admin and the smallest admin id of a group
   with 3 other members → no `group_keys` create within 5 s of the pass
   (fake timer); a member added to a group the device already knew → rotation
   scheduled as today (existing join-rotate tests stay green).
10. R4: sync key step and prefetch for the same cold group at once → **1**
    `group_keys` request, both get the same candidates; `requireCurrent: true`
    joining a walk whose newest version is dead → still throws.
11. R4 window: a refresh within 60 s of a good walk → 0 requests; after 61 s
    (fake clock) → 1; a send path inside the window → 1 request.
12. R4: `prefetchGroupKeys` during `syncAllHistory` → 0 prefetch requests.
13. R5 overlap: a MockClient that delays every answer 300 ms; a group chat
    with 1 page → its key, receipts and page 1 requests are all sent before
    the first answer arrives (request log timestamps); rows and ticks
    identical to the sequential version.
14. R5 members: `syncAllHistory` makes **0** `conversation_members` requests
    after the conversations pass; ticks for a 3-member group still need both
    other members' receipts for `read`.
15. R5 deleted/starred: 5 chats → **1** `deleted_messages_for_me` and **1**
    `starred_messages` request in the whole sync, after the last chat; a
    deleted-for-me row and a starred row in chat 4 are flagged at `complete`.
16. R1 + R5: a 429 on page 1 → the chat is left and lands in a retry round.

Existing, must stay green: `test/offline/history_sync_test.dart`,
`test/offline/group_key_restore_test.dart`,
`test/offline/group_key_local_first_test.dart`,
`test/offline/idempotent_ingest_test.dart`,
`test/offline/key_memory_cache_test.dart`,
`test/offline/encryption_sync_offline_test.dart`,
`test/auth/restore_overlay_test.dart`, the join-rotate and removal tests.
Full `flutter test` green against the baseline taken at build start;
`flutter analyze` 0 errors; `grep_gates_test.dart` (gate 13) green.

## Device check list (you do every sign-in)

Test account pair from two-device testing, never your real chats. Release
build, `--split-per-abi` arm64. Log:
`adb logcat | grep -E "\[Sync\]|\[Conv\] sync|group keys|\[Group\] rotated"`.

1. M52 on **mobile data**, clear app data, sign in, restore. "Full history
   sync starting" to chat 1 **under 5 s**; one `[Conv] sync` line with
   `requests=2`; **no** `[Group] rotated` line.
2. Redmi on **mobile data** (hotspot), same steps: restore to Home **under
   60 s** (stopwatch from Restore; the clean rerun before this build was
   76.6 s). One `group keys` line per group, each under 1 s. Small chats'
   `[Sync] chat` lines about 1.5–2 s. If the total is still over 60 s, note
   the `[Sync] chat` lines: that is the input for D10 (several chats at once).
3. Same run: open three chats with a starred message and one with a message
   deleted for you: star and deletion are there.
4. Same run: after Home, wait 30 s: no new `group keys` lines.
5. Redmi again, clear data, restore; at chat 5 or so turn the M52's hotspot
   off: the screen shows the offline line and Finish later, and stays. Turn
   the hotspot on: it carries on and goes Home. Open the chats that were left:
   full history there before opening, nothing doubled.
6. Same as 5, but tap Finish later while offline: Home at once; turn the
   hotspot on, wait a minute, open a chat that was left: its history is
   there.
7. M52: send a message in two groups from each phone: the other phone reads
   it. In one test group, remove the other phone's account and add it back:
   new messages read on both (a real join still rotates: one
   `[Group] rotated` line on the admin's phone).
8. Restore with the M52 account switching to another app and back on the
   recovery-key screen (copy the key from where you keep it): step 1's
   numbers still hold.

## Out of scope

History-sync S2 (batch decrypt), S3 (Home early); S5 (parallel chats) unless
D10 says yes; the
rotation request count and election items above; any live server read or
change; the restore screen's design beyond the offline line and button.
