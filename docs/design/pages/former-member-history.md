# Former group members keep their history after a reinstall (spec, rev 1)

Status: **spec PASS 2026-11-16 (user), all defaults (D-1..D-8). Phase 2 LIVE 2026-11-17, device PASS 2026-11-17 (rules use the back-relation form, see the work log).** Phase 2 (dry run, live step,
app build) goes to a fresh session. No build, no server change, no live read yet. The board is
`former-member-history.html`.

Reported in the device test on 2026-11-16:
- In one group, M52's admin removed one member and another member left, so M52 was the only
  member left.
- The removed member's phone cleared app data and signed in again. **The group was gone**:
  no chat row and no history.

---

## 1. Why (code read 2026-11-16, `main` at `be0e2f1`)

All lines are in `lib/infrastructure/repositories/message_repository_impl.dart` unless named.

| Step | Removed by an admin | Left on their own |
|---|---|---|
| Server member row | **deleted** by the admin's phone (`removeMemberFromGroup` :4043-4051) | **deleted** by the leaver's phone (`leaveGroup` :4323-4341) |
| Pending invites | deleted (:4053-4068) | not touched |
| System line | "X was removed by Y", sent **after** the delete (:4076-4084) | "X left the group", sent **before** the delete (:4331-4340) |
| Own `group_keys` rows | **kept** (:4087-4090, since `8d5d2f7`) | **kept** (nothing deletes them) |
| Key rotation | by the admin, for the members left (:4102) | by the leaver's phone, which can no longer list members: `_rotateGroupKeyNow` reads an empty list and returns (:4120-4125). See §7, finding 1 |
| The phone that was not wiped | the next sync sees the row missing; after 2 confirmed misses (R1/R2) it sets the local row to `left` and adds "You were removed from this group" (:6711-6758) | sets its own local row to `left` (:4350-4354) |

After a wipe:

1. A fresh sign-in builds the chat list only from **current** member rows.
   `_syncConversationsPass` lists `conversation_members` with `user_id="$myId"` (:6499-6505).
   The deleted row is not there, so the group is never written to the phone.
2. History sync (`syncAllHistory` :3407-3445) walks only the chats the phone already knows. The
   former group isn't one of them.
3. Even if it were, the server would refuse the rows:
   - `messages` and `message_media` list/view need a current member row (bible :804-805,
     :834-835).
   - `conversations` list/view need one too, except for the chat's creator (bible :747-748).
4. The only copy of the history was the phone's local Drift database. Clearing data deleted it.

**Same cause for both paths.** Both delete the server row, and nothing on the server remembers
that the person was ever in the group. The only differences:
- the leaver's "left" line is inside their history window; the "removed by" line is sent just
  after it;
- removal rotates the key; leave probably does not (finding 1).

**What does survive.** The person's wrapped `group_keys` rows. The `group_keys` list rule is
`@request.auth.id = user_id.id || admin of the chat` (bible :985). That needs no membership. The
key walk lists exactly those rows (`encryption_service.dart:741-770`, filter
`conversation_id && user_id`). So a wiped former member can still fetch every key version they
were given, once their device key is restored with the recovery key. **They can't fetch the
messages**, and their phone no longer knows the group exists.

---

## 2. Options

| | What | Server change | App change | Former member sees after a wipe |
|---|---|---|---|---|
| **A** | Keep as is, and say so in the app | none | copy only | nothing (as today) |
| **B** | **A `former_members` record, written only by a server hook when a group member row is deleted. It grants read-only history up to the server time of that delete** | new collection, one hook, extra read branches on 3 collections | small: the sync pass lists the record and adds the group as `left` | the group, read-only, history up to their leave/removal |
| B2 | Same record as B, read through a hook route (`GET /api/kb/former/{conv}/messages`) instead of extra rule branches | new collection, hook, one route | B plus a second history-page path | same as B. **Used only if the dry run shows B's cutoff doesn't work on 0.37.5** (§4, check F3) |
| C | Use the person's own `group_keys` rows as proof of former membership (no new collection, no time limit) | extra read branches only | as B | the whole group, past and future, as ciphertext; after a leave, readable (finding 1) |
| — | A `left_at` column on `conversation_members` instead of deleting the row | every rule that reads members (~20) gains `&& left_at = ""` | removal, leave, rotation and sync all change | as B |

### Why B, and not C or the column

- **C has no time limit.** PocketBase can only compare a back-referenced field with `?=` safely.
  A bare `<=` against a joined collection applied to every joined row and erased real history
  (pb-hook pitfall 5; invite rework D1, 76 → 0 rows).
  - So C would show a former member every later message's sender, time and type, live over
    realtime, forever.
  - After a **leave**, the rest of the group probably keeps using the key the leaver holds
    (finding 1). Under C the leaver could read new messages in clear.
  - Today the server rule is the only thing stopping that. Any former-member access must keep a
    server time limit.
- **The column** puts former members inside the one collection every security rule trusts:
  `messages` create, `group_keys` create, invites, presence unhide, `fcm_notify`, the client's
  rotation member list, and the removal-lock point query.
  - Forgetting `left_at = ""` in any one of them reopens F1: a former member posts, gets the next
    key, or appears as a member.
  - That is the failure `membership-rules.md` just closed. Rejected.
- **B keeps the record somewhere no write rule can reach.** Clients can't create, change or
  delete it. Only the hook writes it, and only after a member delete the delete rule already
  allowed. It appears in **read** rules only, and only behind a time limit.

### B in detail

#### Server

**S1. New collection `former_members`** (in the migration):

| Field | Type | Notes |
|---|---|---|
| `conversation_id` | relation → conversations | required, cascade delete (a deleted group takes its former rows with it) |
| `user_id` | relation → users | required, cascade delete |
| `joined_at` | date | copied from the deleted row (`joined_at`, else `created`) |
| `history_until` | date | server time of the delete |
| `reason` | select `left` / `removed`, optional | blank for back-filled rows (D-5) |

- Unique index on (`conversation_id`, `user_id`): one row per person per group.
- Rules: list and view `user_id = @request.auth.id`. Create, update and delete `null`
  (superusers only; D-6).

**S2. Hook `pb_hooks/former_member_record.pb.js`**. One flat `onRecordDeleteRequest` on
`conversation_members` (pb-hook pitfalls 1 and 2):

1. Read `conversation_id`, `user_id`, `joined_at`/`created` from `e.record`. Set
   `reason = (e.auth && e.auth.id === user_id) ? "left" : "removed"`.
2. `e.next()` (the delete runs; if it throws, nothing is written).
3. In a `try/catch` that only logs: if the conversation's `type` is `group`, upsert the one
   `former_members` row with `$app`, setting `history_until` to now (server clock).
   - A second removal of the same person (after a re-add) moves `history_until` forward
     (D-8).
   - `joined_at` keeps the earliest value.
4. Return without calling a helper's return value.

Things the hook never sees, by design:
- A cascade delete (group or account deleted) doesn't go through the request hook, so it never
  writes a row.
- DMs are skipped by the `type` check.

**S3. Read branches.** `FM(t)` below stands for "I am a former member of this row's chat and
the row is from before I left":
`@collection.former_members.conversation_id ?= conversation_id && @collection.former_members.user_id ?= @request.auth.id && @collection.former_members.history_until ?>= t`

| # | Rule | New value |
|---|---|---|
| R1 | `messages` list and view | `((member branch as today) \|\| FM(created)) && (expires_at = "" \|\| expires_at > @now)` |
| R2 | `message_media` list and view | `((member branch as today) \|\| FM(message_id.created)) && (message_id.expires_at = "" \|\| message_id.expires_at > @now)` |
| R3 | `conversations` list and view | today's rule `\|\| (@collection.former_members.conversation_id ?= id && @collection.former_members.user_id ?= @request.auth.id)` (name, icon, type; D-3) |

Not changed: every create, update and delete rule; `conversation_members`; `group_keys`;
`group_invites`; `reactions`; `polls`; `message_receipts`; the `users` unhide hook;
`fcm_notify`; `disappearing_stamp`.

**The one unknown.** Whether all three `@collection.former_members` conditions are checked
against **the same row** with `?>=` on 0.37.5:
- Today's member rules prove it for `?=`: N1–N9 tests T1–T16 passed.
- `?>=` has never been tried here. Only the bare `<=` was, and it failed.

The dry run settles this with F3 before anything else. If F3 fails, switch to B2, which does the
cutoff in SQL inside a route, and re-run the table.

#### App

- **C1. Sync pass** (`_syncConversationsPass`, after the member loop):
  - List `former_members` with `user_id="$myId"` and `expand: conversation_id`.
  - Act only on a chat that is **not** in this pass's active set and has **no local member row
    at all** (first sight, as on a fresh install). For each one:
    - upsert the conversation from the expand;
    - upsert my member row: id = the former record id, role `left`, `joinedAt` = `joined_at`;
    - if `reason` is `removed`, add the local line "You were removed from this group" stamped
      at `history_until` (D-4).
  - A chat with a local row (any role) is left alone. So the R1/R2 removal-lock guard, the
    2-miss rule and the "removed" line on an un-wiped phone don't change.
  - A chat that is active again (re-added) wins: the active pass upserts the new member row,
    and `removeStaleMemberRows` drops the former-id row as it does today.
- **C2. Nothing else.**
  - History sync already walks every local chat, `left` ones included (:3424).
  - The key walk already lists own rows without membership.
  - The composer already locks for `left` (`chat_screen.dart:56`).
  - Group info already shows "You're no longer in this group." and no admin controls
    (`group_settings_screen.dart:397-409`).
  - The join-time gate and the group-rejoin-history H1 rule (before my join, a row shows only
    if my keys open it) already apply to the `joined_at` written by C1.
- **C3. Build checks** (no change expected):
  - Sender names in the read-only chat resolve without other members' local rows. `users` are
    readable by any signed-in user.
  - A former group's history lands as read, with no unread badge after the restore.

### A in detail (if picked instead of B)

- Leave confirm dialog, under the current text: "Your messages from this group stay on this
  phone only. If you reinstall or clear the app's data, they're gone."
- "You were removed from this group" and the `left` group info banner gain the same second
  sentence.
- No server or sync change.

---

## 3. Each option against keys, composer, removal-lock and F1

| | Old key versions (`group_keys`) | Composer | Removal-lock R1/R2 | F1 (`membership-rules.md` M1–M3) |
|---|---|---|---|---|
| A | survive on the server (§1); unused after a wipe | n/a (no group shown) | unchanged | unchanged |
| **B** | survive and are fetched by the existing key walk. Versions after the leave/removal were never wrapped for them, and the server stops at `history_until` anyway | locked: the local row is `left` (`canSendIn`) | unchanged: C1 touches only chats with no local row, and `_removalMiss` skips `left` rows (:6685) | **not reopened.** `former_members` takes no client writes. Members create, members update, invites, `messages` create and `group_keys` create never read it. `conversations` update still needs a member row. Checks F10–F13 prove each one |
| B2 | as B | as B | as B | as B (the route is read-only and does its own `former_members` lookup) |
| C | as B, but the keys become the access grant | as B | as B | no new write path, but post-leave messages become readable (finding 1). **Rejected** |

**D-3 of `membership-rules.md`** (a removed creator can re-add their own row through the creator
branch) stays out of scope. B doesn't widen it: such a creator is a member again, and the
member branch already shows them everything.

---

## 4. Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| D-1 | Approach | **B (former-member record + read branches with a server time limit)** · A (keep, say so in the app) · B2 (B through a route; also the automatic fallback if F3 fails) · C (rejected: no time limit) |
| D-2 | Where history stops | **The server time of the member-row delete.** The leaver's "left" line is inside; the "removed by" line is just after, so D-4 adds a local one · the delete time plus a grace (e.g. 2 min) to include "removed by" (also includes anything else sent in that window under the old key) |
| D-3 | What a former member can read | **Messages and their media, plus the group's current name and icon.** Old bubbles show without reactions; a poll shows its question but no live tally · also reactions and polls, each with its own `created` time limit (2 more rule pairs; votes cast after leaving would still show in a poll's totals) |
| D-4 | The "You were removed" line after a wipe | **Local line from `reason`, stamped at `history_until`** · none |
| D-5 | People who left or were removed before this ships (including the reported group) | **Back-fill from `group_keys`, counts first, rows only after a separate yes.** A row for each (person, group) that has own key rows but no member row, and a newer key version wrapped for someone else. `history_until` = when that newer version was created (the rotation that shut them out); `joined_at` = their earliest key row; `reason` blank. Pairs with no newer version (e.g. a leave never followed by a rotation) are **skipped**: no safe end time · no back-fill (only removals after the live step come back) |
| D-6 | Can a former member remove the record (a "Delete group" for a left group) | **Not now.** Delete rule `null`; a later "Delete group" adds `user_id = @request.auth.id` and the button. Until then a wiped former member always gets the group back · add both now |
| D-7 | Group info for a former group | **As today for `left`: banner, no member list, no admin controls** (they can't read members) · also show a frozen member list (would need a snapshot in the record) |
| D-8 | Re-added, then removed again | **One row per person per group; `history_until` moves forward.** The gap between stints downloads as ciphertext they hold no key for, and stays hidden (group-rejoin-history D2) · keep one row per stint (more rows, exact gaps, a harder rule) |

---

## 5. How it is applied (phase 2, fresh session)

Same pattern as `membership-rules.md`. **Every server step needs the user's go-ahead first.**

1. Write locally:
   - `docs/server/migrations/<ts>_former_members.js` (`apply(app, set)` form). Up: create the
     collection with its index and rules, then set R1–R3. Down: restore the exact rule strings
     at bible :747-748, :804-805, :834-835, then drop the collection.
   - `docs/server/hooks/former_member_record.pb.js`.
   - The client C1 change and its tests.
2. **Dry run on a copy (no live change):**
   - `.backup` the live `data.db`; copy `pb_migrations` and `pb_hooks` to `/tmp/pbtest`; add
     the throwaway token route (`docs/server/tests/tok.pb.js`).
   - Apply the migration, start the same binary on `127.0.0.1:8099`.
   - Run §6's table, F3 first, then the D-5 counts (read-only), then the earlier tables (N1–N9
     T1–T16, membership U1–U14 and V1–V9) to show nothing else moved.
   - Throwaway accounts and groups only; never a real chat.
3. Report the table and counts. **Go-ahead needed before the live step**, and a separate yes
   for any back-fill rows.
4. Live:
   - Back up `data.db` and `pb_hooks` (`.<date>-former-pre`).
   - `scp` the migration and hook, `sudo mv`, restart once.
   - Re-run F1, F3, F10 and F13 with throwaway rows, delete them, and list them in the work
     log.
5. App build + `flutter test` + device check (§7).
6. Rollback: `migrate down` and remove the hook, or restore both backups. The app tolerates a
   missing `former_members` collection: C1's list fails, gets logged, and the sync goes on.
7. Update bible §7 (new collection, R1–R3, the hook). One commit after device PASS, not
   pushed.

### Read-only counts (D-5, on the copy)

```sql
-- former pairs: own key rows, no member row
select count(*) from (select distinct k.conversation_id, k.user_id from group_keys k
  where not exists (select 1 from conversation_members m
    where m.conversation_id = k.conversation_id and m.user_id = k.user_id));
-- of those, with a newer version wrapped for someone else (= back-fillable)
select count(*) from (select k.conversation_id, k.user_id, max(k.key_version) v from group_keys k
  where not exists (select 1 from conversation_members m
    where m.conversation_id = k.conversation_id and m.user_id = k.user_id)
  group by 1, 2) f
  where exists (select 1 from group_keys n where n.conversation_id = f.conversation_id
    and n.key_version > f.v);
```

## 6. Request table (dry run; "live" marks the re-check)

Setup on the copy. Use throwaway accounts A, B, C, D, all signed in by token.

1. Group `G`: `A` is admin, `B` and `C` are members.
2. `B` posts `m1` with a photo, `C` posts `m2`.
3. Group `K`: `A` is admin, `B` is a member.
4. `A` removes `B` from `G` (deletes `B`'s row, as the app does).
5. `A` posts `m3` in `G`.
6. `A` removes `B` from `K`, **after** `m3`.
7. `C` posts "C left", then deletes their own `G` row.
8. `A` posts `m4` in `G`.
9. `D` is in neither group.

| # | Request | Before | After |
|---|---|---|---|
| F1 (live) | `B` lists `messages` in `G` | 0 rows | `m1`, `m2` only |
| F2 | `C` lists `messages` in `G` | 0 | `m1`, `m2`, `m3`, "C left"; not `m4` |
| F3 (live, **first**) | Same-row check: `B` lists `G` again. `C`'s `G` row and `B`'s `K` row both end **after** `m3` | — | still **not** `m3`. If `m3` shows, stop: switch to B2 |
| F4 | `D` lists `messages` in `G`; `D` views `m1` | 0; 404 | 0; 404 |
| F5 | `B` views `m3` by id | 404 | 404 |
| F6 | `B` lists `message_media` in `G`; views `m1`'s media | 0; 404 | `m1`'s row; 200 |
| F7 | `B` lists `conversations` | neither `G` nor `K` (unless creator) | `G` and `K` |
| F8 | `B` lists `conversation_members` in `G`; lists `group_keys` in `G` | 0; own rows | 0; own rows, none newer than the removal |
| F9 | `B` lists `former_members`; `D` lists `former_members` and filters `user_id="<B>"` | — | `B`: rows for `G` and `K` (`reason` = removed); `C`'s row says `left`; `D`: 0 and 0 |
| F10 (live) | `B` creates a message in `G` | 400 | 400 |
| F11 | `B` creates a member row in `G` (`role` member, no invite); `B` PATCHes `G`'s name | 400; 404 | 400; 404 |
| F12 | `B` creates, updates or deletes a `former_members` row (own, or one for `D` in `G`) | — | 400/403/404 for all |
| F13 (live) | `B` subscribes to `messages`; `A` posts `m5` in `G` | no event | no event |
| F14 | `A` re-invites `B`; `B` accepts; `B` lists `G` | — | every row (member branch). Remove again: still one `former_members` row, `history_until` later (D-8) |
| F15 | `A` deletes conversation `K` (creator) | — | `B`'s `K` former row is gone (cascade) |
| F16 | Delete a DM member row with superuser on the copy | — | no `former_members` row |
| F17 | `A`'s rotation after removing `B`: who gets the new `group_keys` rows | `A`, `C` | `A`, `C` (former rows never reach the member list) |
| F18 | Timing: `B` lists 2,000 `G` rows, and a current member lists the same | — | each under 300 ms, and the member's time no more than 1.5× before |
| F19 | Earlier tables T1–T16, U1–U14, V1–V9 | as recorded | unchanged |

## 7. Device check list (test accounts, M52 + Redmi, after the build)

M52 is the admin and the Redmi is the member. Make a **new** test group.

1. M52 creates "Former test" with the Redmi. Both phones send 2 texts; M52 sends a photo, the
   Redmi sends a voice note. Both read everything.
2. M52 removes the Redmi. Redmi: the composer locks within seconds (R1/R2), and "You were
   removed from this group" shows.
3. M52 sends 2 more texts and a photo.
4. Redmi: clear app data, sign in, restore with the recovery key. "Former test" is in the chat
   list.
   - Open it: step 1's messages, photo and voice note show and open, in order.
   - "You were removed from this group" is the last line. None of step 3 shows.
   - The composer is locked.
   - Group info shows "You're no longer in this group." with no members and no admin controls.
5. The Redmi has no unread badge for "Former test" after the restore.
6. Leave path: in a second group, the Redmi leaves on its own. Clear data, sign in: that group
   comes back up to "Redmi left the group"; nothing M52 sent after shows.
7. Re-add: M52 re-invites the Redmi to "Former test" and the Redmi accepts. The chat is a
   normal member chat again; the step 3 messages stay hidden (group-rejoin-history).
8. M52 and other members: send, remove, leave and re-key as before. New members still see
   nothing from before they joined.
9. D-5, if back-fill was approved: the group from the 2026-11-16 report shows up on the Redmi
   after a clear-data sign-in, up to the removal.

---

## 8. Found while specifying (not built here)

1. **A leave probably never rotates the group key** (code read only, not seen on a device).
   - `leaveGroup` deletes its own row, then calls `_rotateGroupKey` (:4361).
   - The leaver can no longer list the chat's members (members list rule, bible :772), so
     `_rotateGroupKeyNow` finds an empty list and returns (:4120-4125).
   - The remaining admins' phones rotate only on a member **create** (`_subMembers` :590-601)
     and on a key gap, meaning a member who lacks the current key (`_reconcileGroupKeyGaps`
     :4656-4705). A leaver holding the current key is neither.
   - So the leaver keeps the key the group still uses. Only the server's `messages` rule stops
     them downloading new messages.
   - A logcat check on the next leave (`[Group]` rotate lines on the admin's phone, and the
     newest `key_version` before and after) would confirm it.
   - The likely fix: the admin's phone rotates when it sees a member delete event or sync
     removal for someone who isn't itself.
   - This is a separate bug for its own spec. It is also why §2 rejects any option without a
     server time limit.
2. Group media older than the media retention window is already deleted on the server. A former
   member gets those as "expired", the same as current members.

## 9. Must not undo

- `membership-rules.md` M1–M3 and H1–H3, and N1–N9. No create or update rule gains a branch.
- The removal flow: delete the row, delete invites, the line, keep key rows, rotate
  (:4043-4102).
- The leave order: line first, then the delete (:4331-4341).
- R1/R2 and the 2-miss guard (`_removalMiss`).
- New joiners see nothing from before their join, media included (group-rejoin-history H1).
- Never render ciphertext.
- Flat hooks; files copied with `scp`, never written through an SSH heredoc.

## 10. Out of scope

- Finding 1 (leave rotation).
- `membership-rules.md` D-3 (removed creator re-entry).
- Reactions and polls for former members (D-3 alternative).
- A "Delete group" button (D-6).
- A frozen member list (D-7).
- DMs.
- Any live read or change before the go-ahead.
