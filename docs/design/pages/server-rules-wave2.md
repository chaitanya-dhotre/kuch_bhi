# Server rules, wave 2: who may add you to a chat, friends, reactions, media, unused collections (spec, rev 1)

Status: **spec PASS 2026-11-17 (user), all defaults (X-1..X-8). Dry run PASS, LIVE and device PASS
2026-11-17** (backup `data.db.20261117-wave2-pre`; see
`server-rules-wave2-work-log.md`). As built, N11 branches 2 and 3 use back-relations (same
meaning, about 10× faster). Branch 1 keeps `E` as written. `:length` on a back-relation is
refused by 0.37.5.

Source: security audit `docs/audits/2026-11-16-security-cloudflare-skill.md`:
- **F4** (medium): anyone can open a chat with anyone and add any user to it. Blocks are not
  enforced on the server.
- **F7** (low): friendships can be created one-sided.
- **F8** (low): friend requests can be created as `accepted`, and the recipient can rewrite
  `from_user`/`to_user`.
- **F9** (low): reactions can be written into any chat.
- **F10** (low): a `message_media` row can name a different chat than its message.
- **F11** (low): any group member can post a "system" notice.
- The same kind of create gap on `polls` and `scheduled_messages`, which the app doesn't use.
- **D-3** of `membership-rules.md`: a removed creator can re-add their own row.

Rule text is from `KUCH_BHI_PROJECT_BIBLE.md` §7 (read live 2026-11-15). The members and invites
rules there already include the 2026-11-16 change (`membership-rules.md` M1–M3). Code read on
`main` at `be0e2f1`.

This is a server-only change: rule strings in one migration. **No app build is needed** if the
checks below pass. Every call the app makes still matches a branch (see "What the app needs").

---

## 1. What is wrong

Message text and media stay end-to-end encrypted. None of this exposes what people wrote. It
lets a stranger put themselves into someone's chat list, friend list or reactions, and it keeps
a door open for a removed creator.

| # | Collection, rule (bible line) | Today a signed-in user can | Risk |
|---|---|---|---|
| W1 | `conversations` create (:749): `@request.auth.id != ""` | create a chat with any `created_by`, including someone else's id | low |
| W2 | `conversation_members` create, creator branch (:774): `@request.auth.id = conversation_id.created_by` | as the creator of **any** chat, add **any** user id with **any** role. Create a group, add a stranger: it shows up on their phone with no consent. Create a DM with someone who never accepted you | **medium** |
| W3 | same branch | a creator who was removed (or left) adds their own row back, even as `admin`. The admin's phone then sees a member without the key and wraps it for them (`_reconcileGroupKeyGaps`, `message_repository_impl.dart:4656-4701`). That is D-3 | **medium** |
| W4 | `conversation_members` create, admin branch (:774) | as an admin, add any user (not just a friend) with any role | low |
| W5 | `friendships` create (:721): `@request.auth.id = user_a` | put themselves in anyone's friend list. With W2 fixed, a friendship is what lets someone add you to a chat, so this becomes the key to W2 | **medium** once W2 is fixed |
| W6 | `friend_requests` create (:700) | create a request already `accepted`. With W8 that becomes a forged friendship | low |
| W7 | `friend_requests` update (:701): `@request.auth.id = to_user && status = "pending"` | as the recipient, rewrite `from_user` and `to_user`, or set `status` to anything | low |
| W8 | `reactions` create, update (:886-887): `@request.auth.id = user_id` | add a reaction in a chat they're not in, if they know a message id. Or name a message from another chat | low |
| W9 | `message_media` create (:836): `message_id.sender_id = @request.auth.id` | pin a media row on their own message into another chat's gallery (`conversation_id` is not checked). Users can't delete media rows | low |
| W10 | `messages` create (:806) | post `type = "system"`. It shows as a centred app notice with no sender (`message_bubble.dart:235-244`), e.g. a fake "Admin removed Bob" | low |
| W11 | `polls` create (:913), `scheduled_messages` create, update (:959-960) | create rows in any chat. The app uses neither collection | low |

**Blocks.** `blocked_users` rules only scope the blocker's own rows (:932-936). Nothing else reads
them. But the app has **no block feature today**: `blockUser`, `unblockUser` and
`getBlockedUserIds` (`friend_repository_impl.dart:245-284`) have no caller in `lib/`. See decision
X-2.

---

## 2. What the app needs (code read 2026-11-17)

| Call | Where | Rule branch it uses |
|---|---|---|
| Send a friend request: `status: 'pending'` | `friend_repository_impl.dart:59-66` | friend_requests create |
| Accept: request → `accepted`, **then** friendship with `user_a = me` (the recipient), `user_b = from_user`, **then** the DM | `:79-130` | friend_requests update; friendships create; conversations create; members create |
| Decline: request → `declined` | `:135-138` | friend_requests update |
| Duplicate check before the friendship create | `:104` | friendships list (not changed) |
| DM create: chat with `created_by = me`, my row `role: 'admin'`, then the other's row `role: 'member'` | `:421-434` | conversations create; members create (creator, then admin) |
| The only DM create path is the accept above | `_findOrCreateDirectConversation` has one caller (`:126`) | — |
| Group create: chat with `created_by = me` (multipart when an icon is set), my row `role: 'admin'`, then each picked **friend** as `role: 'member'` | `create_group_screen.dart:103-145`; `group_create_service.dart:22-65` | conversations create; members create (creator, then admin) |
| Add a member after creation: always an invite | `message_repository_impl.dart:3787, 3792` | invites (not changed) |
| Accept an invite: own row `role: 'member'` | `:3877-3885` | members create, invite branch (not changed) |
| React: create with the client's own id, `message_id`, the message's `conversation_id`, `user_id = me` | `:3256-3262` | reactions create |
| Un-react: delete own row | `:3289` | reactions delete (not changed) |
| Reaction update | none in `lib/` | — |
| Media upload (voice, image, video, document): `conversation_id` is always the message's own chat | `media_upload_service.dart:151, 348, 479, 533` | message_media create |
| System notices posted to the server: "created the group" (creator), "joined" (the joiner, a plain member), "left" (the leaver, before its row is deleted), "removed", "promoted", "demoted" (an admin) | `create_group_screen.dart:299-307`; `message_repository_impl.dart:3940, 4077, 4235, 4274, 4333` → `_emitSystemMessage` `:5902-5955` | messages create |
| `polls`, `scheduled_messages` | no call in `lib/` | — |
| `blocked_users` | repository methods only, no caller | — |

Two things this table settles:
- **Every direct add is a friend.** The group picker lists friends only (`allFriends`), and a DM is
  made right after the friendship. Every other add is an invite, which is consent.
- **Every member legitimately posts system notices**, plain members included ("joined", "left").
  A rule can't tell a real notice from a forged one (decision X-4).

A refused reaction is dropped without a message (`_refused` at `:3263-3274`). So if the new
reaction rule is wrong, reactions vanish silently. The device check must look at the **other**
phone.

---

## 3. New rules

Shorthand:
- `M(x)`: I am a member of chat `x`:
  `@collection.conversation_members.conversation_id ?= x && @collection.conversation_members.user_id ?= @request.auth.id`
- `A`: I am an admin of this row's chat: `M(conversation_id) && @collection.conversation_members.role ?= "admin"`
- `F(u)`: I am friends with `u`, either way round. Two aliases so each branch binds its own row:
  `((@collection.friendships:fa.user_a ?= @request.auth.id && @collection.friendships:fa.user_b ?= u) || (@collection.friendships:fb.user_a ?= u && @collection.friendships:fb.user_b ?= @request.auth.id))`
- `E`: the chat has no member rows yet (see "The one unknown" below):
  `@collection.conversation_members:existing.conversation_id != conversation_id`

| # | Rule | New value | Closes |
|---|---|---|---|
| N10 | `conversations` create | `@request.auth.id != "" && @request.body.created_by = @request.auth.id` | W1 |
| N11 | `conversation_members` create | three branches, full text below | W2, W3, W4 |
| N12 | `friendships` create | `@request.auth.id = user_a && @collection.friend_requests.from_user ?= user_b && @collection.friend_requests.to_user ?= @request.auth.id && @collection.friend_requests.status ?= "accepted"` | W5 |
| N13 | `friend_requests` create | `@request.auth.id = from_user && @request.auth.id != to_user && @request.body.status = "pending"` | W6 |
| N14 | `friend_requests` update | `@request.auth.id = to_user && status = "pending" && @request.body.from_user:isset = false && @request.body.to_user:isset = false && (@request.body.status = "accepted" \|\| @request.body.status = "declined")` | W7 |
| N15 | `reactions` create | `@request.auth.id = user_id && M(conversation_id) && @collection.messages.id ?= message_id && @collection.messages.conversation_id ?= conversation_id` | W8 |
| N16 | `reactions` update | `null` (superusers only; no caller, X-5) | W8 |
| N17 | `message_media` create | `message_id.sender_id = @request.auth.id && conversation_id = message_id.conversation_id` | W9 |
| N18 | `polls` create, update, delete; `scheduled_messages` create, update, delete | `null` (X-6) | W11 |

Not changed: every list and view rule; `messages` create (X-4); the members invite branch;
`group_invites`; `group_keys`; `blocked_users`; deletes other than N18.

Full N11 text (branch 1 is the creator's **own first** row; branch 2 is an admin adding a
**friend** as a member; branch 3 is today's invite branch, unchanged):

```
@request.auth.id != "" && ((@request.auth.id = conversation_id.created_by && @request.auth.id = user_id && @request.body.role = "admin" && @collection.conversation_members:existing.conversation_id != conversation_id) || (@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= "admin" && @request.body.role = "member" && ((@collection.friendships:fa.user_a ?= @request.auth.id && @collection.friendships:fa.user_b ?= user_id) || (@collection.friendships:fb.user_a ?= user_id && @collection.friendships:fb.user_b ?= @request.auth.id))) || (@request.auth.id = user_id && @collection.group_invites.conversation_id ?= conversation_id && @collection.group_invites.invited_user_id ?= @request.auth.id && @collection.group_invites.status ?= "pending" && @request.body.role = "member"))
```

How each create path walks N11:
- **Group create:** my admin row matches branch 1 (no rows yet). Then I am an admin, so each
  friend's member row matches branch 2.
- **DM create:** the same. My admin row matches branch 1, the other's member row matches branch 2.
  The friendship was made a moment earlier in the accept.
- **Removed creator:** the group still has members, so `E` fails. They aren't an admin, so
  branch 2 fails. With no pending invite, branch 3 fails. **D-3 is closed.**
- **Stranger:** creating their own chat works, but adding you fails branch 2 (not friends).

### The one unknown: can a rule say "no rows yet"?

pb-hook pitfall 5 says back-references only work with `?=`, and that a bare operator is checked
against **all** joined rows. That broke a date cutoff (2026-10-03), because "all rows" was the
wrong meaning there. For `E` it is the right meaning. "Every member row has another chat"
means "no member row is in this chat". On an empty chat that is true, and once one row exists
it is false.

This has never been tried here. The dry run settles it with **Q7 and Q8 first**, before anything
else. The order of fallbacks (X-3):
1. `E` as written, with its own alias `:existing`, so it doesn't share a join with branch 2's
   `?=` conditions.
2. If 1 fails: a back-relation count,
   `conversation_id.conversation_members_via_conversation_id:length = 0`, if 0.37.5 accepts
   `:length` on a back-relation.
3. If both fail: keep branch 1 without `E`, and add a **flat** `onRecordCreateRequest` hook on
   `conversation_members`. It refuses only the branch-1 shape: `user_id` = the requester = the
   chat's `created_by`, `role = "admin"`, and
   `$app.countRecords("conversation_members", $dbx.hashExp({conversation_id: <chat>}))` above 0.
   A re-invited creator joins as `member` through branch 3 and is not touched. It ends with a
   direct `return e.next()` (pitfall 1).

---

## 4. Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| X-1 | Who may be **added directly** to a chat (group create, DM) | **Friends of the person adding, as today in the app.** Everyone else only through an invite they accept · every group add goes through an invite (an app change to group create: people join only after accepting) |
| X-2 | Blocks on the server | **Not now.** The app has no block feature (the repository methods have no caller). A rule can't say "no block row exists": back-references only take `?=`, and "for all rows" can't combine two fields. When a block feature is built, blocking should also **delete the friendship** (the delete rule already lets either side do that). Then N11 branch 2 stops new chats and adds without any extra rule · a flat hook that reads `blocked_users` on members and friend-request creates, now |
| X-3 | Close D-3 (a removed creator re-adds themselves) | **Yes: `E` in branch 1, with the fallbacks above. If even the hook can't be made to work, stop and report** · accept it and leave D-3 open |
| X-4 | Forged system notices (F11) | **No server change here.** Every member posts real notices ("joined", "left"), so the server can't tell them apart. Log a small app spec instead: a system notice shows who posted it (e.g. a short "· posted by Bob" line), or a notice that names someone else is shown only when its poster is an admin · admins only for `type = "system"` on the server (plain members' "joined" and "left" would then be refused and stay local-only, so others never see them) |
| X-5 | `reactions` update | **`null`**: nothing updates a reaction; changing an emoji is a delete and a create · keep it, and lock `message_id`, `conversation_id`, `user_id` |
| X-6 | `polls` and `scheduled_messages` | **Writes `null`; keep both collections and their read rules.** Deleting a collection can't be undone. Whether a scheduled-send hook is deployed is still audit L5; with no client writes it has nothing to send · delete both collections (only after L5 is answered) · add a membership clause instead |
| X-7 | Rows that already break the new rules | **Report only** (counts below). Removing any row is a separate yes |
| X-8 | How a friendship is made | **The N12 rule: only the recipient of an accepted request, as the app does today** · a hook makes the friendship when a request turns `accepted`, and the app stops creating it (an app change) |

---

## 5. How it is applied (phase 2)

Same pattern as `server-rules.md` and `membership-rules.md`. **Every server step needs the user's
go-ahead first.**

1. Write `docs/server/migrations/1794810000_updated_rules_wave2.js` locally, in the
   `apply(app, set)` form of `1794700100_updated_rules_scope.js`.
   - Up: sets N10–N18.
   - Down: restores the old strings exactly (bible :749, :774, :721, :700, :701, :886, :887,
     :836, :913–915, :959–961).
   - It sorts after `1794800000_former_members.js`. That one changes read rules only, and this one
     changes create and update rules only, so they touch no rule in common. Either can be applied
     or rolled back alone.
   - If X-3 needs fallback 3, also write `docs/server/hooks/member_create_guard.pb.js`.
2. **Dry run on a copy (no live change).**
   - `.backup` the live `data.db`, copy `pb_migrations` and `pb_hooks` to `/tmp/pbtest`, and add the
     throwaway token route (`docs/server/tests/tok.pb.js`).
   - **Run Q7 and Q8 first** against the migration. If `E` fails, try fallback 2, then 3, before
     going on.
   - Run the whole request table before and after (a new `docs/server/tests/wave2_request_table.py`
     in the style of `membership_request_table.py`). Then run the read-only counts and time Q17.
3. Report the table and counts to the user. **Go-ahead needed before the live step.**
4. Live:
   - Back up `data.db` to `/home/ubuntu/pb_backups/data.db.<date>-wave2-pre` (and `pb_hooks` if a
     hook is added).
   - `scp` the files, then `sudo mv` them in. No heredoc (pitfall 2). Restart once.
   - Check `_migrations`, then re-run the rows marked "live" with throwaway users and a test chat.
     Delete those rows afterwards and list them in the work log.
5. Device check (below) on the current build.
6. Rollback: `migrate down`, plus removing the hook if one was added. Or restore the backup.
7. Update bible §7 with the new strings. Then one commit with this spec, the migration, any hook,
   the test script, the work log and the bible.

### Read-only counts (X-7, on the copy)

```sql
select 'friendships with no accepted request either way', count(*) from friendships f
  where not exists (select 1 from friend_requests r where r.status = 'accepted'
    and ((r.from_user = f.user_b and r.to_user = f.user_a) or (r.from_user = f.user_a and r.to_user = f.user_b)));
select 'DM pairs who are not friends', count(*) from conversation_members m1
  join conversation_members m2 on m2.conversation_id = m1.conversation_id and m1.user_id < m2.user_id
  join conversations c on c.id = m1.conversation_id and c.type = 'direct'
  where not exists (select 1 from friendships f where (f.user_a = m1.user_id and f.user_b = m2.user_id)
                                                   or (f.user_a = m2.user_id and f.user_b = m1.user_id));
select 'chats whose creator is no longer a member', count(*) from conversations c
  where not exists (select 1 from conversation_members m where m.conversation_id = c.id and m.user_id = c.created_by);
select 'reactions by someone not a member now', count(*) from reactions r
  where not exists (select 1 from conversation_members m where m.conversation_id = r.conversation_id and m.user_id = r.user_id);
select 'reactions whose message is in another chat', count(*) from reactions r
  join messages g on g.id = r.message_id where g.conversation_id != r.conversation_id;
select 'media rows in another chat than their message', count(*) from message_media mm
  join messages g on g.id = mm.message_id where g.conversation_id != mm.conversation_id;
select 'polls rows', count(*) from polls;
select 'scheduled_messages rows', count(*) from scheduled_messages;
```

These are leads, not proof:
- People who left or were removed keep their old reactions, so the fourth count includes them.
- A creator who left shows in the third count.

List the rows for the user. Never delete them in this step.

---

## 6. Request table (dry run; "live" marks the re-check)

Setup:
- `A` and `B` are friends. `A` and `D` are friends. `C` is friends with nobody.
- Group `G`: `A` created it and is admin, `B` is a member and has sent a message `mG`.
- DM `AB` holds a message `mD`.
- `C` owns their own chat `X`.
- `E2` and `D2` are fresh users, each with a pending request to `A`.

| # | Request | Before | After |
|---|---|---|---|
| Q1 (live) | `C` creates a conversation with `created_by = A` | 200 | 400 |
| Q2 | `C` creates group `X` (`created_by = C`), then their own admin row | 200; 200 | 200; 200 |
| Q3 (live) | `C` adds `A` to `X` as `member`; then as `admin` | 200; 200 | 400; 400 |
| Q4 | `C` creates a DM, own admin row, then `A`'s member row | 200; 200; 200 | 200; 200; 400 |
| Q5 | `A` creates a group with an icon (multipart), own admin row, then `B` and `D` as members | works | works |
| Q6 | `A` accepts `E2`'s request: request → `accepted`, friendship (`user_a = A`, `user_b = E2`), then the DM with both rows | works | works |
| Q7 (live) | `A` promotes `B`; `B` removes `A` from `G`; `A` adds their own row back as `admin`; then as `member` | 200; 200 | 400; 400 |
| Q7b | After Q7, `B` invites `A`; `A` self-joins as `member` (the re-add path of group-rejoin-history) | 200 | 200 |
| Q8 | `A` creates a new chat and adds their own admin row (no rows yet) | 200 | 200 |
| Q9 (live) | `C` sends `A` a request with `status = "accepted"`; then with `"pending"` | 200; 200 | 400; 200 |
| Q10 | `A` (recipient) PATCHes `C`'s pending request: `from_user = B`; `to_user = D`; `status = "pending"`; then `status = "declined"` | 200; 200; 200; 200 | 400/404; 400/404; 400/404; 200 |
| Q11 (live) | `C` creates a friendship `user_a = C`, `user_b = A`; `A` creates one with `D2` whose request to `A` is still pending; `A` creates one with `E2` after Q6's accept | 200; 200; 200 | 400; 400; 200 |
| Q12 (live) | `C` reacts on `mG` (`conversation_id = G`) | 200 | 400 |
| Q13 | `B` reacts on `mG`, then deletes it; reacts on `mG` with `conversation_id = AB`; PATCHes own reaction's emoji | 200, 200; 200; 200 | 200, 200; 400; 403/404 |
| Q14 (live) | `B` uploads a media row on `mG` with `conversation_id = AB`; then with `conversation_id = G` | 200; 200 | 400; 200 |
| Q15 | `C` creates a `polls` row in `G` with `created_by = C`; `C` creates a `scheduled_messages` row for `G` | 200; 200 | 403; 403 |
| Q16 | `B` posts `type = "system"` in `G` (X-4: unchanged); `C` posts one in `G` | 200; 400 | 200; 400 |
| Q17 | Timing: `A`'s member create (branch 2, friendship lookup) and own first row (branch 1, `E`) against today's rule | — | under 300 ms, and not more than 3× before |
| Q18 | Realtime: `A` subscribed to `friendships`, `friend_requests`, `reactions`, `conversation_members` gets the events of Q6 and Q13 | — | as stated |
| Q19 | An invite still works: `A` invites `C` to `G`; `C` self-joins as `member`; the invite → `accepted` | works | works (not friends, but consented) |

---

## 7. Device check list (current build, M52 and Redmi, test accounts)

1. Send a friend request from one phone; it shows on the other. Decline it. Send again; accept it.
   Both friend lists update, and the DM opens on both phones. Send both ways.
2. Create a group with two friends, with an icon. Everyone sees it and can send both ways. The
   "created the group" notice shows.
3. Invite someone who is not in the group; they accept; they see "joined".
4. Promote, demote, remove a member, leave a group. Each notice ("promoted", "removed", "left")
   shows on the **other** phone.
5. React on both phones in a DM and a group, then remove the reaction. The **other** phone shows
   each change (a refused reaction is dropped silently, so look there).
6. Send a photo, a voice note, a video and a document in a group. The Media gallery on the other
   phone lists each one under that group only.
7. Sign out, sign in, restore: friends, chats, members and reactions are all there.

---

## 8. Must not undo

- N1–N9 (`server-rules.md`), M1–M3 and H1–H3 (`membership-rules.md`). The members invite branch
  keeps `@request.body.role = "member"`.
- `former-member-history.md` R1–R3 (read rules on `messages`, `message_media`, `conversations`).
  This spec changes no read rule.
- The accept order: request → `accepted` **before** the friendship create (N12 reads the saved
  status), and the friendship **before** the DM (N11 branch 2 reads the friendship).
- Group create order: my admin row **before** the others' rows (branch 2 needs me to be admin).
- Group-create cleanup deletes the chat as its creator (`group_create_service.dart:83`). The delete
  rule is not touched.
- Reactions: delete own row, as today. One reaction per person stays client-side.
- `fcm_notify`, `disappearing_stamp`, `former_member_record`, `user_fields_unhide` use `$app` and
  are not subject to rules.
- Flat hooks, no heredocs through ssh, files written locally and copied (pb-hook pitfalls 1–2).
  No date cutoffs in a rule (pitfall 5).

## 9. Out of scope

- The X-4 app spec (who posted a system notice).
- A block feature (X-2).
- Deleting `polls`/`scheduled_messages` (X-6, after L5).
- Cleaning existing rows (X-7).
- Rate limits and per-user caps on chats, requests and invites (audit §5).
- Invites to non-friends: they need the invitee's yes, so they stay allowed.
- Every other audit finding (F3, F5, F6, F12–F22, L1–L10). `former-member-history.md` and
  `leave-rotation.md` own their own work.
- Any app change.
