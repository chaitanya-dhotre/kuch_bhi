# Removed member's composer locks within seconds (spec, rev 1)

Status: **spec PASS 2026-11-14, all defaults; R1 + R2 built, device PASS
2026-11-14 (round 2), suite 1296/1296.** No live server reads were made.

## What happened

Device check 2026-11-14: the M52 (admin) removed the Redmi from a group. The
Redmi's chat stayed open with a working composer. It locked only after the
app was closed and reopened, and even then about 1 minute later.

## Why (code read)

All in `lib/infrastructure/repositories/message_repository_impl.dart`.

### How a removal is detected

1. The admin's `removeMemberFromGroup` (L3947) deletes the removed user's
   `conversation_members` row(s), deletes their invites, sends the
   "X was removed by Y" system message, then rotates the group key.
2. The removed phone only learns about it in `_syncConversationsPass`
   (L6405). That pass lists my membership rows. A local group row that is not
   `left` and is missing from the list is a **miss** (L6596–L6641):
   - the miss count `_removalMissCounts[conv]` goes up by 1;
   - a point query (`conversation_id && user_id = me`) runs. Row found = a
     stale list, count reset. Query error = no verdict;
   - row gone and count < `_removalConfirmMisses` (2) = "holding verdict",
     nothing else happens;
   - row gone and count = 2 = flip my row to `left`, wipe the group key, add
     "You were removed from this group". The composer reads my role through
     `groupMembersProvider`, a Drift stream, so it locks at once
     (`canSendIn`, `chat_screen.dart` L47).
3. So a removal needs **two separate passes**. Nothing schedules the second
   one. A pass runs only when something calls `_syncConversations`:

| Trigger | Where | Reaches the removed phone after removal? |
|---|---|---|
| `conversation_members` SSE event (any action) | `_subMembers` L587 | **Probably once:** the delete of their own row (see below) |
| `conversations` SSE event | `_subConversations` L577 | No: removal does not touch the conversation record, and the rule needs membership |
| `messages` SSE (the "was removed" message) | `_subMessages` L494 | No: it is created after the row is deleted, and does not call a sync anyway |
| `group_keys` rotation | not subscribed | No |
| Resume (`resyncOnResume` L4439) | app back from background | Only when the user leaves and comes back |
| Home opens (`watchConversations` L803) | each new home watch | Cold start |
| Poll fallback (`_startPollFallback` L763, every 5 s) | only while SSE is down | Rarely |

### Cause, P1 (app open): one pass, one miss, then silence

The removed phone gets at most one event (its own row's delete), runs one
pass, logs `[Conv] membership miss 1/2 … holding verdict`, and stops. No
second event ever comes for a chat they are no longer in, so the composer
stays open until a resume or restart.

### Cause, P2 (after reopen, ~1 min)

`_removalMissCounts` lives in memory, so the restart reset it to 0. The cold
start's first pass is miss 1 again. The verdict waits for the next pass from
any trigger: another group's member event, the reconnect's poll tick, or a
resume. That gap was about a minute.

### Does the delete event reach the removed phone?

Not checked against the live server (the `conversation_members` list/view
rule is not in the repo). PocketBase 0.23+ checks a delete event's access
**before** the row is deleted and sends it after the delete commits, so a
user who could see the row a moment earlier should get the event. This is
from memory of PocketBase's realtime code, not read here. P1's symptom (an
open composer, no lock at all while the app stays open) fits both "one event,
one held miss" and "no event", and the fix below is the same for both
**except** while the app stays open the whole time with no event: then only
D3 helps. Device check step 2 tells which one is true from logcat, with no
server access.

## Options

| | What | Lock time, app open | Lock time, after reopen | Cost |
|---|---|---|---|---|
| **A** | **After a pass that held a confirmed miss, run one follow-up pass after 5 s** | ~6–8 s if the delete event arrives | ~6–8 s after Home opens | ~15 lines in one file; extra requests only after a miss, which is rare |
| B | On an SSE delete for my own row, re-check that chat at once | ~1–2 s | not fixed (no event on cold start) | Needs A anyway for P2 |
| C | Server pushes "your membership changed" to the removed user (hook on member delete → FCM data message) | ~1–3 s, even with no SSE | same as A | Live hook change + client handler; only worth it if step 2 shows no SSE event |
| D | Lower `_removalConfirmMisses` to 1 | 1 pass | 1 pass | Drops the 2-pass guard. Rejected by the task |

**Default: A.** It keeps both checks of the guard (two passes in a row, each
with a point query that finds the row gone), adds no server work, and fixes
P1 and P2 together. B only shaves seconds and still needs A. C is the
fallback if device step 2 shows no event reaches the Redmi.

### Is 5 s safe against the old false removal?

The guard came from `eb4d01c` (2026-10-12 repro: a group condemned seconds
after creation, when a single list snapshot was the only check). Today:

- the point query clears every "row exists but the list was stale" case;
- group creation writes the server rows **before** the local rows
  (`create_group_screen.dart` L126–L162), so the phone never has a local row
  whose server row is not written yet;
- the 30-row page cap is gone (R2 uses `getFullList`).

So for a false `left`, the server would have to answer "no such row" to two
point queries 5 s apart while the user really is a member. That stays as
guarded as today's "two passes", which today can also be seconds apart (a
burst of member events).

## Changes (A)

### R1: follow-up pass after a held miss

In `_syncConversationsPass`:

1. When the branch at L6635 holds a verdict (point query said gone, misses <
   2), note it (`var held = false;` → `held = true`).
2. After the reconcile loop: `if (held) _scheduleRemovalRecheck();`.
3. `_scheduleRemovalRecheck()`: one `Timer? _removalRecheck`. If one is
   already pending, do nothing. Otherwise `Timer(removalRecheckDelay, …)` that
   clears the field, reads `_myId()`, and calls `_syncConversations(myId)` if
   not empty. No `prefetchGroupKeys` (not needed for a re-check).
4. `@visibleForTesting Duration removalRecheckDelay = const Duration(seconds: 5);`
   so tests can shorten it without fake_async (not used in this repo's tests).
5. Cancel and null the timer where `_removalMissCounts.clear()` runs (identity
   change, L231; this also runs on logout, so no second cancel there). The
   pass already bails on a changed session epoch.

Built 2026-11-14: tests 1–3 of the gates below are the three `R1:` tests;
4 and 5 are covered by test 2 (a found row sets no timer) and the
`isActive` guard. Test 6 needed no change.

No loop: the follow-up pass either condemns (count reset, no row left to
miss), finds the row (count reset), or the point query errors (no `held`, no
new timer; the next normal trigger retries as today).

One log line, so the device check can read it:
`[Conv] removal re-check in 5s` when the timer is set.

### R2: the re-check asks only about the held chat (device round 1)

Device round 1, 2026-11-14 (Redmi logcat): R1 worked, and the SSE delete
**does** reach the removed member (D3 answered: no server push needed). But
each full pass took 5–15 s on the Redmi (`ms=7959`, `ms=7103`), so step 1
locked about 20 s after the removal (8 s first pass + 5 s + 7 s re-check).
User asked to make it faster.

- The miss step is one method, `_removalMiss(convId, myId)`: count, point
  query, hold or condemn. The full pass and the re-check both call it.
- The timer now runs `_removalRecheckPass`: for each held chat, skip it if
  my local row is gone or `left` (left from this phone meanwhile), else run
  `_removalMiss` again. No membership list, no per-chat rewrites.
- It runs in the conversation-pass slot (`_convPasses(recheckOnly: true)`),
  so it never overlaps a full pass; callers that arrive meanwhile get one
  full pass after it. If a full pass is already running when the timer
  fires, the timer folds into it as before.
- New log line on the verdict: `[Conv] removal confirmed for <id>`.

Expected: about 8 s + 5 s + under 1 s ≈ 13–14 s in step 1. Under 10 s would
also need the first pass to check removals before its per-chat rewrites; not
built (bigger change on every sync).

### Not changed

- `_removalConfirmMisses = 2`, the point query, "query error = no verdict".
- The verdict's work (role `left`, key wipe, local bubble).
- Triggers for normal syncs.

## Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| D1 | How to get the second pass? | **A: one follow-up pass 5 s after a held miss** · B on top of A (re-check at once on my own row's SSE delete) · C: server push |
| D2 | Follow-up delay? | **5 s** · 2 s (faster, closer to the old race window) · 10 s |
| D3 | If device step 2 shows **no** `[Conv] sync` on the Redmi when the row is deleted (no SSE event reaches a removed member) | **Stop after the build's device check and write C (server push) as its own spec; A still fixes reopen and resume** · build C in this session (needs a live hook change and your yes) |
| D4 | Read the live `conversation_members` rules first to settle the SSE question? | **No: device step 2's logcat answers it with no server access** · yes, one read-only `sqlite3 -readonly` read of `_collections` (needs your yes) |

## Test gates

Extend `test/offline/removal_reconcile_char_test.dart` (same `SyncFeed`
fake, `removalRecheckDelay` set to 20 ms):

1. One `debugSyncConversations()` with the row gone (list and probe empty),
   then wait 100 ms with **no** further call → my row is `left`, the
   "You were removed" bubble exists (the follow-up ran on its own).
2. Row gone on the first pass, back in the probe before the follow-up → no
   verdict, and no second timer (wait 100 ms more, probe count stays put).
3. Probe throws → no verdict and no follow-up (probe count stops at 1).
4. A pass with no miss sets no timer.
5. Two held passes in a row (two calls before the timer fires) → one timer,
   one follow-up.
6. The 3 existing tests stay green (they call the sync twice by hand; the
   short timer may fire between them, which must not change their result:
   check, and give them a long `removalRecheckDelay` if it does).

Gates: `flutter analyze` clean for the touched files; full suite green
(baseline = the count on `main` at build time).

## Device check (you do every step)

Phones: **M52** adb `RFCRA047WSJ` = admin. **Redmi** adb `c7e9f10e` = the
member who gets removed. Debug or profile build with logs on both. A test
group with both phones in it (and ideally a third member so the group lives
on).

Before: on the Redmi run

```bash
adb -s c7e9f10e logcat -c
```

```bash
adb -s c7e9f10e logcat | grep -E "\[Conv\]|\[Group\]"
```

1. **App open, chat open.** Redmi: open the group chat, leave it on screen.
   M52: Group info → remove the Redmi. **Pass:** the Redmi's composer locks
   and "You were removed from this group" appears within **15 s** (round 1
   was ~20 s; R2 targets ~13 s), with no touch on the Redmi.
2. **Which trigger fired (the SSE question).** In the Redmi's log from step 1,
   within ~2 s of the removal: `[Conv] sync …` then
   `[Conv] membership miss 1/2 … holding verdict` and
   `[Conv] removal re-check in 5s`, then about 5 s later
   `[Conv] removal confirmed for <id>` with no `[Conv] sync` line in between
   (R2: the re-check is not a full pass). Note whether the first `[Conv] sync`
   came with no action on the Redmi. If there is **no** `[Conv] sync` until
   you touch the Redmi, the delete event does not reach a removed member: see
   D3.
3. **Removed while in the background.** Re-add the Redmi (M52 invite, Redmi
   accept), wait for it to send one message. Redmi: press Home. M52: remove
   it. Redmi: wait 30 s, open the app. **Pass:** locked within **15 s** of
   coming back (resume pass ~5 s + 5 s + re-check).
4. **Removed while the app is closed.** Re-add again. Redmi: swipe the app
   away. M52: remove it. Redmi: open the app, go to the group. **Pass:**
   locked within **25 s** of Home showing (was ~1 min; the cold-start pass
   alone took ~15 s on the Redmi in round 1).
5. **No false removal on a new group.** M52: create a new group with the
   Redmi in it. Both phones: open it, each send a message within 30 s.
   **Pass:** neither phone shows "You were removed", both composers stay
   open, and the Redmi log has no `holding verdict` line for that group (or,
   if one appears, the re-check finds the row and no verdict follows).
6. **Still a member, normal use.** In a group the Redmi stays in: lock and
   unlock the phone, switch apps, toggle mobile data off and on for 10 s.
   **Pass:** no "You were removed" anywhere, composer stays open.
7. **Admin side unchanged.** On the M52, the member list drops the Redmi and
   "Redmi was removed by …" shows, as before.

## Must not undo

- The 2-pass guard and the point query before any verdict (backlog §7).
- "Probe error = never condemn".
- Leave from this device still sets `left` first and skips the reconcile.
- Session-scoped state is cleared on identity change (timer included now).

## Out of scope

- C (server push for removals) unless D3 is chosen.
- Resetting the miss count across restarts (A makes it unneeded).
- What the removed member can still read (history access is the
  group-rejoin-history spec).
