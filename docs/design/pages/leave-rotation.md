# A member who leaves no longer holds the group's key (spec, rev 1)

Status: **spec PASS 2026-11-17 (user), all defaults (L-1..L-7). Built + device PASS 2026-11-17 (P4 = N+1 confirmed the bug; 1412/1412).** No server change, no
live server read. Phase 2 (proof on the current build, then the build) goes to a fresh session.

Found while writing `former-member-history.md` (§8 finding 1).

---

## 1. Why (code read 2026-11-16, `main` at `be0e2f1`)

All lines are in `lib/infrastructure/repositories/message_repository_impl.dart` unless named.

### What a leave does

`leaveGroup` (:4301-4362):

1. If I am the only admin, promote the earliest-joined member (:4308-4318).
2. Send "X left the group" while I am still a member (:4331-4340).
3. **Delete my own `conversation_members` row** (:4341).
4. Drop my current-key slot, set my local row to `left` (:4346-4354).
5. Call `_rotateGroupKey` (:4361).

### Why step 5 never rotates

- `_rotateGroupKeyNow` first lists the chat's members (:4120-4122). The members list rule
  (bible §7.5, :772) lets me see a row only if it is mine or I am in that chat. After step 3
  I am neither, so the list is empty and the method returns at :4125. It logs nothing.
- Even before the delete, it could not work for most leavers. The `group_keys` create rule
  (bible §7, :987) needs the writer to be an **admin** of the chat. A plain member can never
  write a key row.

### Why nobody else rotates either

Admin phones rotate in three places, and a leave hits none of them:

| Trigger | Where | Fires on a leave? |
|---|---|---|
| Admin removes someone | `removeMemberFromGroup` :4102 | No, the leaver removed themself |
| Member row **created** (SSE, or a new row found by a sync) | `_subMembers` :590-601, sync :6625-6632 → `_maybeScheduleRotate` | No, a leave is a delete. The SSE handler returns at :594 for any action but `create` |
| A member lacks the current key (resume, full path only) | `_reconcileGroupKeyGaps` :4656-4705 | No. It looks for members **missing** the key. The leaver is no longer a member and **holds** the key |

The admin's sync does notice the leaver is gone: it deletes the local member row (:6659-6668).
Nothing else happens there.

### What it means

The leaver keeps version N, which the group goes on using: their own `group_keys` row stays
readable to them (list rule `user_id = me`), and the phone keeps the versioned slot. Every
message sent after the leave is encrypted with N until some later rotation (a join, a
removal). Today only the server's `messages` rules keep those rows from the leaver. That
breaks the end-to-end promise the removal path keeps: after a removal, a leak of the server
data would not expose new messages to the removed member. After a leave, it would.

How it fits next to former-member-history: that spec gives former members reads only up to
`history_until` (the time of the delete). Messages sent with N after the leave sit past that
cutoff, so it does not widen this hole. This fix is still what makes that spec safe without
trusting the cutoff alone.

Also covered by the same fix, for free: a removal whose rotation failed (for example a member
with no public key throws at :4150 after the row was already deleted) leaves the same kind
of key holder behind.

---

## 2. Proof on a device (before any code change)

Run on the **current** build. Test accounts only. **M52** adb `RFCRA047WSJ` = admin.
**Redmi** adb `c7e9f10e` = the member who leaves. Debug or profile build, logs on.

Nothing in today's app logs the current key version except a rotation:
`[Group] rotated v<N> members=<M> ms=…` (:4202-4205). So the proof is arithmetic: note N from
a rotation before the leave, then force one rotation after it. If the leave had rotated, the
next line would say N+2, and if it did not, N+1.

Before each run, on both phones:

```bash
adb -s RFCRA047WSJ logcat -c
```

```bash
adb -s c7e9f10e logcat -c
```

Watch the M52:

```bash
adb -s RFCRA047WSJ logcat | grep -E "\[Group\]|\[Conv\] sync"
```

Watch the Redmi (second terminal):

```bash
adb -s c7e9f10e logcat | grep -E "\[Group\]|\[Conv\] sync"
```

| # | Step | Expect (bug present) |
|---|---|---|
| P1 | M52: new group "Leave test", invite the Redmi. Redmi: accept | M52: `[Group] rotated vN members=2` within ~5 s. **Write down N.** |
| P2 | Redmi: send one message (proves it holds vN). Then Group info → Leave | Redmi: no `[Group] rotated` line, no error. M52: a `[Conv] sync …` line within a few seconds, **no** `[Group] rotated` line |
| P3 | M52: press Home, wait **70 s**, open the app (full resume runs the key-gap check) | M52: still **no** `[Group] rotated` and no `[Group] key gap` line |
| P4 | M52: invite the Redmi again. Redmi: accept | M52: `[Group] rotated v<N+1> members=2`. **N+1 = the leave never rotated. N+2 = it did** (then stop: this spec is wrong, tell me) |

Optional, only if P4 is unclear: you look at `group_keys` for that chat in the PocketBase
dashboard yourself (sort by `-key_version`). I make no server read (L-6).

---

## 3. Options

| | What | Leaver must cooperate? | Works if the admin was offline? | Cost |
|---|---|---|---|---|
| **A** | **The elected owner's phone rotates when a current-key holder is no longer a member** (stateless check, see §4) | No | Yes, at the admin's next sync | ~60 lines + a helper, client only |
| B | The leaver rotates **before** deleting its row, leaving itself out | Yes | n/a | Only admins may write key rows (create rule), so plain members can't. A changed or crashed app skips it. The key-gap check would see the leaver (still a member) without the new key and rotate them back in. **Rejected** |
| C | Server hook on member delete | No | Yes | The server has no group key and can't make one (end to end). It could only *signal* (a flag, or an FCM push to admins), and a push can't run the rotation without the app open. The stateless check in A needs no flag. **Rejected for now**; reconsider only if device logs show long windows |

### Why A fits what is already there

- **Elected owner.** One device rotates per chat: the admin with the smallest user id
  (`_isRotationOwner` :639). A elects from the **fresh server member list** it just read,
  not from the local DAO, because the local list may still name the leaver as an admin.
  If the leaver was the smallest admin id, the DAO would elect the leaver and nobody would
  rotate.
- **One rotation at a time per chat.** The check runs inside `_rotations.run(convId, …)`
  and calls `_rotateGroupKeyNow` **directly**. Calling `_rotateGroupKey` from inside would
  queue behind itself in `SerialPerKey` and stall for its 2-minute cap. Running the check
  in the slot also means it never reads key rows while this phone is halfway through writing
  a rotation, which would look like a key gap.
- **Admin's own removal.** `removeMemberFromGroup` deletes the local row itself (:4095)
  before its sync runs, so the sync never sees that member "gone" and schedules nothing. If
  another phone's check fires anyway, it finds no stale holder after the removal rotation and
  does nothing. If it reads mid-write on the other phone, the worst case is one extra
  version, which the existing collision retry (:4159-4193) already handles.
- **Offline admin.** No SSE reaches it. Its next `_syncConversations` (cold start, any resume,
  light path too, or any other chat's event) still has the leaver's local row and finds it
  gone, so the trigger fires then. If the app dies inside the 3 s debounce, or the rotation
  throws, the resume net (T3) finds the stale holder from the server rows alone.
- **Removal-lock R1/R2.** Untouched. They run on the **removed** phone, in the own-row miss
  loop (:6682-6697). A's trigger is in the **other members** loop (:6659-6668), which only
  runs for chats where I am still a member. The leaver's and the removed member's phones
  never reach it for that chat. The pass only starts a timer, so it adds no time to a pass
  (one pass already takes 5-15 s on the Redmi).

---

## 4. A in detail

### K1: one per-chat check

New `Future<void> _checkGroupKeyHolders(String convId)`, always run as
`_rotations.run(convId, () => _checkGroupKeyHoldersNow(convId))`:

1. `myId = await _myId()`; empty → return.
2. Local gate, no request: the chat is a `group` and my local role is `admin`. Otherwise
   return. (Plain members' phones spend nothing.)
3. List `conversation_members` for the chat (server). Error → log and return (T3 retries).
4. If I am not an `admin` in that list → return. (Covers a just-demoted or removed phone.)
5. Owner = smallest `user_id` among the list's admins. Not me → return.
6. List `group_keys` for the chat (an admin may list all of them, bible §7).
7. `current` = the highest `key_version`. `missing` = `membersMissingCurrentKey(…)` (as
   today). `stale` = new `keyHoldersNotMembers(…)`: users with a row at `current` who are
   not in the member list.
8. Both empty → return, no log.
9. Log `[Group] key check missing=<n> stale=<n>` (counts only, no ids, R3) and call
   `_rotateGroupKeyNow(convId, myId)`.

`keyHoldersNotMembers` goes in `lib/core/utils/key_gap.dart` next to
`membersMissingCurrentKey`, pure and unit-tested.

### K2: schedule it

`_scheduleKeyHolderCheck(String convId)`: reuse the `_rotateDebounce[convId]` map with the
same 3 s timer, so a burst (or a join rotate already waiting) folds into one. The timer calls
`_checkGroupKeyHolders(convId)` and logs a failure as `[Group] key check failed: $e`.

If a join's `_maybeScheduleRotate` replaces the timer, its rotation reads the fresh member
list too, so it also leaves the leaver out. If K2 replaces a pending join timer, the check
sees the joiner as `missing` and rotates. One rotation either way.

### T2: the sync finds a member gone (main trigger)

In `_syncConversationsPass`, the loop that drops local members no longer on the server
(:6659-6668): after deleting such a row, call `_scheduleKeyHolderCheck(conv.id)` (timer only,
not awaited). Once per chat per pass is enough.

This covers the app being open (the delete SSE already calls `_syncConversationsBackground`
at :593, and that pass finds the row gone) and the offline admin (the next pass finds it).
No new SSE branch is needed.

### T3: the resume net

`_reconcileGroupKeyGaps` (:4656-4705) keeps its loop over my admin group chats, but each chat
just calls `_scheduleKeyHolderCheck(convId)` instead of its own reads and its own
`_isRotationOwner`. K1 reads the same two lists, so the gap repair behaves as before (now
elected from the server list) and also catches stale holders. Still full-path resume and
cold start only (L-2).

### K3: the leaver's own call

Delete `await _rotateGroupKey(conversationId, myId);` at :4361 and its comment (:4357-4360).
Replace it with one line: the group's rotation owner rotates when its sync sees this row
gone. It never did anything (§1), and keeping it hides the real rule (L-3).

### K4: identity change

Where `_removalRecheck` is cancelled on an identity change (:232-233), also cancel and clear
every `_rotateDebounce` timer. Today a pending join rotate survives a sign-out. Low risk
(the check re-reads `myId` and the server list), but one loop closes it.

### Not changed

- `_rotateGroupKeyNow` itself, the collision retry, the 2-minute serial cap.
- `_maybeScheduleRotate` and `_isRotationOwner` for joins.
- Removal (`removeMemberFromGroup` still rotates at once).
- Server rules and hooks.
- The leaver keeps its old `group_keys` rows (history and former-member-history need them).

---

## 5. Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| L-1 | Which fix? | **A: owner's phone rotates on a stale key holder** · B: leaver rotates first (admins only) · C: server hook signal |
| L-2 | Run the T3 net on the light (under 60 s) resume too? | **No: T2 already runs on the light path; T3 is only for crashes and failed rotations** · yes (two extra requests per admin group on every short resume) |
| L-3 | The leaver's dead `_rotateGroupKey` call | **Delete it, one-line comment instead** · keep it (harmless no-op) |
| L-4 | The owner is offline but another admin is online | **Wait for the owner, same as joins today** · any admin rotates if a stale holder is still there 60 s later (more requests, more version races) |
| L-5 | Prove the bug first? | **Yes: the build session runs §2 on the current build before changing code; N+2 at P4 stops the build** · skip the proof |
| L-6 | Read the live `group_keys` to prove it? | **No: §2's arithmetic is enough; you may look in the dashboard yourself** · one read-only `sqlite3 -readonly` query over SSH (needs your yes) |
| L-7 | K4 (cancel rotate timers on sign-out) | **Include it** · leave it out |

---

## 6. Test gates

Unit (`test/key_gap_test.dart`, add):

1. A user with a row at `current` who is not a member → in `stale`.
2. A non-member whose newest row is older than `current` (removed and rotated) → not stale.
3. A member at `current` → not stale.
4. `current` = 0 (no rows) → empty.

Repository (extend the `SyncFeed`/MockClient fake in
`test/offline/removal_reconcile_char_test.dart`, or a new `test/offline/leave_rotation_test.dart`
with the same fake; it must also serve `group_keys` and record `group_keys` POSTs; debounce
made test-short with a `@visibleForTesting Duration keyCheckDelay`):

5. Admin phone, local rows {me (admin), B}; server members {me}; keys: me and B at v3 →
   after one `debugSyncConversations()` and the delay: one rotation, rows POSTed at v4 for me
   only.
6. Same, but another admin with a smaller id is in the server list → no POST.
7. Same, but my local role is `member` → no request to `group_keys` at all.
8. Server member list errors → no POST, no throw.
9. Members {me, B}, keys both at v3 (nobody gone) → no POST.
10. A member removed by me through `removeMemberFromGroup` → exactly one rotation (the removal's),
    none from the sync afterwards.
11. Two syncs inside the delay → one check, one rotation.
12. `leaveGroup` makes no `group_keys` request (K3).
13. Existing suites stay green, in particular `group_rejoin_history_test.dart` (its :153
    comment relies on the leave's rotate returning at once; with K3 it is simply gone) and
    `removal_reconcile_char_test.dart`.

Gates: `flutter analyze` clean for touched files; full suite green (baseline = the count on
`main` at build time, 1400 at `f8e8435`).

---

## 7. Device check (after the build; you do every step)

Same phones and log commands as §2. A test group with M52 (admin), Redmi, and if you have
one, a third test account so the group lives on.

1. **App open, member leaves.** Both phones in the app. Note N from the last
   `[Group] rotated` on the M52. Redmi: Leave. **Pass:** within **15 s** the M52 shows
   `[Group] key check missing=0 stale=1` then `[Group] rotated v<N+1>`. The Redmi shows no
   `[Group]` rotate or key-check line.
2. **Group keeps working.** M52 sends a message right after step 1. **Pass:** it shows, no
   "waiting for key" bubble. (If there is a third member: they read it.)
3. **Admin offline.** Re-add the Redmi (invite + accept). Note N again. M52: swipe the app
   away. Redmi: Leave. Wait 30 s. M52: open the app. **Pass:** within **30 s** of Home
   showing, `key check … stale=1` and `rotated v<N+1>`.
4. **Admin in the background under 60 s (light resume).** Re-add the Redmi. M52: press Home.
   Redmi: Leave. M52: come back within 30 s. **Pass:** same two lines within 20 s.
5. **Sole admin leaves.** Make the Redmi the only admin of a group that has the M52 in it
   (M52 creates it, promotes the Redmi, demotes itself). Note N on the Redmi's last rotate.
   Redmi: Leave. **Pass:** the M52 becomes admin, then within 15 s logs
   `key check … stale=1` and `rotated v<N+1>`.
6. **Removal unchanged.** Re-add the Redmi. M52: remove it. **Pass:** exactly **one**
   `[Group] rotated` line on the M52 (no `key check` rotation after it), and the Redmi locks
   as in removal-lock (within 15 s).
7. **No rotation storms.** Ordinary use for 2 minutes in a group nobody leaves (send, react,
   background and resume twice). **Pass:** no `key check` or `rotated` lines.
8. **Join unchanged.** Invite + accept a member. **Pass:** one `rotated` line, the joiner reads
   new messages.

---

## 8. Must not undo

- Removal rotates at once from the admin's phone; the removed member's history rows stay.
- One rotation per chat at a time on a device (`SerialPerKey`), and the collision retry.
- The removal-lock 2-pass guard (R1/R2) and "probe error = never condemn".
- "X left the group" is sent before the member row is deleted.
- Leave still sets the local row to `left` first and skips the reconcile on the leaver's phone.
- No ids in new log lines.

## 9. Out of scope

- A server push to wake an offline owner (C), unless §7 step 3 shows long windows in practice.
- Any admin rotating in place of an offline owner (L-4 option 2).
- What former members may read (former-member-history).
- Joins rotating on the owner from the server list (they still use the DAO election).
