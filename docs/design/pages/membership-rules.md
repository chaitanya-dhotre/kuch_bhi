# Membership and presence rules: stop strangers joining groups or seeing who chats where (spec, rev 2)

Status: **spec PASS 2026-11-16 (user), all defaults (D-1..D-8). LIVE 2026-11-16, device PASS 2026-11-16** (+H3, see the work log).
Dry run, live step and device check are recorded in `membership-rules-work-log.md`.

Source: security audit `docs/audits/2026-11-16-security-cloudflare-skill.md`:
- **F1** (high): strangers can join groups.
- **F2** (medium): presence chat ids are readable by everyone.
- **L1** (needs live check): the key-backup filter oracle. It closes as a side effect of part 2.

The rule text is from `KUCH_BHI_PROJECT_BIBLE.md` §7, read live on 2026-11-15. Rev 2 folds F2
into this spec at the user's request, building on the parent session's notes.

This is a server-only change: three rule strings, five field flags, and one hook that replaces
`key_backup_hide.pb.js`. No app build is needed if the checks below pass (see "What the app
needs").

---

## Part 1: membership (F1)

### What is wrong

| # | Rule (bible line) | Today a signed-in user can | Risk |
|---|---|---|---|
| R1 | `conversation_members` update, second branch (bible:764): `(user_id = @request.auth.id && @request.body.role:isset = false)` | change the chat of their **own** member row to any chat. The row keeps its role, so an admin row stays admin | **high** |
| R2 | `group_invites` update, admin branch (bible:1050): admin of the invite's chat, no field locked | re-point an invite from a chat they administer to any other chat | **high** |
| R3 | `conversation_members` create, invite branch (bible:763): `role` not checked | accept an invite as `admin` instead of `member` | medium |

How R1 plays out. It needs only a sign-up, because sign-up is open:

1. Create a chat. You are its `created_by`.
2. Add your own member row with `role: "admin"`, using the creator branch of the create rule.
3. PATCH that row so `conversation_id` is the victim group's id.

You are now an admin member of that group. R2 combined with R3 gets the same result through an
invite you send to yourself.

The real admin's phone then hands over the group key:
- `_reconcileGroupKeyGaps` (`message_repository_impl.dart:4656-4701`) runs on every resync. It
  sees a member without the current key and rotates.
- `_rotateGroupKeyNow` (`:4120-4123`) wraps the new key for every member row the server lists.
- From then on the intruder reads every new group message.

The victim's chat id comes from part 2's leak.

### What the app needs (code read 2026-11-16)

| Call | Where | Rule branch used |
|---|---|---|
| Create a group: own admin row and the others' member rows | `group_create_service.dart:47, 57` | members create, creator branch |
| Start a DM: two member rows | `friend_repository_impl.dart:425, 430` | members create, creator branch |
| Accept an invite: own row with `role: 'member'`, then invite → `accepted` | `message_repository_impl.dart:3877-3885, 3904` | members create, invite branch; invites update, invitee branch |
| Decline an invite: invite → `declined` | `:3959` | invites update, invitee branch |
| Invite a friend: new invite, or the existing one → `pending` | `:3787, 3792` | invites create; invites update, admin branch (status only) |
| Promote or demote: `role` on someone's row | `:4226, 4265` | members update, admin branch |
| Remove, leave: delete member row, delete invites | `:4050, 4064, 4341, 4003` | delete rules, not touched |

Nothing in `lib/` updates its own member row:
- `muted_until` and `last_read_message_id` are never written to the server.
- `joined_at` is only read.

So R1's branch has no caller.

### New rules

`A` below stands for "I am an admin of this row's chat":
`@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= "admin"`.

`L` below stands for "the ids are not changed":
`@request.body.conversation_id:isset = false && @request.body.invited_user_id:isset = false && @request.body.invited_by:isset = false`.

| # | Rule | New value |
|---|---|---|
| M1 | `conversation_members` update | `A && @request.body.user_id:isset = false && @request.body.conversation_id:isset = false` (second branch removed; D-1) |
| M2 | `conversation_members` create | same as today, but the invite branch ends with `&& @request.body.role = "member"` |
| M3 | `group_invites` update | `(invited_user_id = @request.auth.id && L && (@request.body.status = "accepted" \|\| @request.body.status = "declined")) \|\| (A && L)` (the status lock is D-2) |

Full M2 text:

```
@request.auth.id != "" && (@request.auth.id = conversation_id.created_by || (@collection.conversation_members.conversation_id ?= conversation_id && @collection.conversation_members.user_id ?= @request.auth.id && @collection.conversation_members.role ?= "admin") || (@request.auth.id = user_id && @collection.group_invites.conversation_id ?= conversation_id && @collection.group_invites.invited_user_id ?= @request.auth.id && @collection.group_invites.status ?= "pending" && @request.body.role = "member"))
```

---

## Part 2: user fields only the owner (or a chat-mate) may see (F2, and L1)

### What is wrong

`users` list and view are `@request.auth.id != ""` (bible:664-665). Any signed-in user can list
every user's record.

| # | Field | Today a signed-in user can | Risk |
|---|---|---|---|
| P1 | `current_chat`, `typing_in` (written at `presence_service.dart:93, 123`) | see which chat everyone has open or is typing in. Two users showing the same id are talking right now. That is the who-talks-to-whom leak N1–N9 closed elsewhere, and the chat id is the input to part 1 | medium |
| P2 | `fcm_token` | read every user's push token | low |
| P3 | `private_key_encrypted`, `private_key_salt` | not read them: `key_backup_hide.pb.js` strips them from responses. But a filter is not a response. `filter=id="<victim>" && private_key_encrypted~"<prefix>"` answers yes or no, enough to rebuild a blob character by character. A v1 (6-digit PIN) blob then cracks offline | high if any v1 blob remains |

The same oracle defeats any response-only hide of P1. `filter=current_chat="<id>"` lists who is in
a chat even if the value is blanked in the output. So blanking in an enrich hook is not enough. The
fields must be **hidden** at the schema level. PocketBase drops hidden fields from responses
**and** refuses them in non-superuser filters. An enrich hook then puts each one back only for
those who may see it.

### What the app needs (code read 2026-11-16)

| Field | Who reads it | Where |
|---|---|---|
| `current_chat`, `typing_in` | a chat-mate, compared with **that** chat's id (`typing == convId`, `chat == convId`), via `getOne` and a realtime subscribe on the other user | `presence_service.dart:167, 175, 194-201` |
| `fcm_token` | nobody in the app (written only: `auth_repository_impl.dart:423, 470`; `fcm_service.dart:123, 165`); the `fcm_notify` hook reads it server-side with `$app` | — |
| `private_key_encrypted`, `private_key_salt` | the owner, always on their **own** record via `getOne(myId)` | `encryption_service.dart:999-1001, 1095-1097, 1215-1228` |
| `is_online`, `last_seen`, `friend_code`, `public_key`, names, avatar | others | friend search filters on `friend_code` (`friend_repository_impl.dart:43`); keys and presence UI |

No app code filters on any of the five fields.

### New flags and hook

| # | Change |
|---|---|
| H1 | Mark `current_chat`, `typing_in`, `fcm_token`, `private_key_encrypted` and `private_key_salt` as **hidden** on `users` (in the same migration as M1–M3) |
| H2 | A new flat hook `pb_hooks/user_fields_unhide.pb.js` (`onRecordEnrich` on `users`) **replaces** `key_backup_hide.pb.js` (D-7) |

The hook's logic, written flat with a direct `return e.next()` (pb-hook pitfall 1):
1. No auth on the request → nothing to unhide, `e.next()`.
2. The requester is the record's owner → `e.record.unhide("current_chat", "typing_in", "fcm_token", "private_key_encrypted", "private_key_salt")`.
3. Otherwise, for each of `current_chat` and `typing_in` whose value is not empty: if a
   `conversation_members` row exists with `conversation_id` = that value and `user_id` = the
   requester, unhide that field.
   - Use `$app.findFirstRecordByFilter` with `{:c}`/`{:u}` params, in a try/catch: not found means
     keep it hidden.
   - At most two lookups per record, and only for records with a live presence value.
4. Superusers already see hidden fields, so the hook does nothing for them.

**H3 (added in the dry run, 2026-11-16).** PocketBase removes hidden fields from a
non-superuser's update body, so the owner's own writes would silently do nothing (presence,
`fcm_token`, key backup). The same hook file also has a flat `onRecordUpdateRequest` on `users`.
For the owner's own update only, it re-reads the raw body with `e.bindBody` and sets those of the
five fields the request sent. See the work log.

Enrich also runs when realtime messages are serialised, so the chat-mate's subscribe at
`presence_service.dart:175` keeps getting the fields **for a chat they share** and nothing else.
The dry run must prove this (V5).

---

## Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| D-1 | Members update, second branch (own row, role locked) | **Remove it**: no caller in the app · keep it but lock `conversation_id` and `user_id` |
| D-2 | What an invitee may set `status` to | **`accepted` or `declined` only**. Today a declined invitee can flip back to `pending` and join later · leave as is |
| D-3 | A removed (or departed) creator can re-add their own row through the creator branch of members create | **Accept for now and log a follow-up.** A rule cannot say "no members yet": back-references only support `?=` (pb-hook pitfall 5), and date cutoffs are not server-expressible · try a back-relation count in the dry run and add it only if it provably works on 0.37.5 |
| D-4 | Client check: an admin's phone wraps a new key only for members it saw join | **No client change in this spec**; the server fix closes the hole · a separate build spec |
| D-5 | Member rows that may already have been moved | **Report only** (counts below); removing any row is a separate yes |
| D-6 | Which `users` fields stay visible to every signed-in user | **Keep `is_online`, `last_seen`, `friend_code`, `public_key`, names, avatar, `about` visible.** Friend-code search filters on `friend_code`, and keys and presence need the rest · also hide `last_seen`/`is_online` to non-friends (needs a friendship lookup per record and an app check of who shows presence; not now) |
| D-7 | One hook or two on `users` enrich | **One file, `user_fields_unhide.pb.js`, replacing `key_backup_hide.pb.js`.** With schema-hidden fields the old strip has nothing left to do, and two enrich hooks on one collection make the order matter · keep both |
| D-8 | Old v1 (6-digit PIN) blobs still on the server | **Count them in the dry run (report only).** H1 stops the oracle, but a copy taken before today is still crackable. Asking those users to move to a recovery key is a separate step |

Out of this spec (other audit findings): F4 (creator adds anyone, blocks not enforced), F7–F10
(friendships, friend requests, reactions, media rows).

---

## How it is applied (phase 2)

Same pattern as `server-rules.md`. **Every server step needs the user's go-ahead first.**

1. Write two files locally:
   - `docs/server/migrations/1794790000_updated_membership_presence.js`, in the `apply(app, set)`
     form of `1794700100_updated_rules_scope.js`.
     - Up step: sets M1–M3 and the five `hidden: true` flags. The flags are set on
       `c.fields.getByName(name).hidden`, then `app.save(c)`.
     - Down step: restores the strings at bible:763, :764 and :1050 exactly, and sets the five
       flags back to `false`.
   - `docs/server/hooks/user_fields_unhide.pb.js`.
2. **Dry run on a copy (no live change).**
   - `.backup` the live `data.db` and copy `pb_migrations` to `/tmp/pbtest`.
   - Set up the copy's hooks dir: the new hook, the throwaway token route
     (`docs/server/tests/tok.pb.js`), and **not** `key_backup_hide.pb.js`.
   - Apply the migration, start the same binary on `127.0.0.1:8099`.
   - Run the request tables below before and after, then the read-only counts.
3. Report the tables and counts to the user. **Go-ahead needed before the live step.**
4. Live:
   - Back up `data.db` to `/home/ubuntu/pb_backups/data.db.<date>-membership-pre`, and `pb_hooks`
     to `pb_hooks.<date>-membership-pre`.
   - `scp` the migration and the hook, then `sudo mv` them in. No heredoc (pb-hook pitfall 2).
   - Remove `key_backup_hide.pb.js` in the **same** restart, so the fields are never visible
     between steps. The hook and the migration go in together; restart once.
   - Check `_migrations` and the journal, then re-run U1, U6, U8, V1, V2 and V5 with throwaway
     rows in a test chat. Delete those rows afterwards and list them in the work log.
5. Device check (below) on the current build.
6. Rollback: `migrate down`, put `key_backup_hide.pb.js` back, remove the new hook, restart. Or
   restore both backups.
7. Update bible §7: members and invites rules, and mark the five `users` fields hidden with the
   hook named. Then one commit with this spec, the migration, the hook, the work log and the
   bible.

### Read-only counts (D-5, D-8, on the copy)

```sql
select 'member row older than its chat', count(*) from conversation_members m
  join conversations c on c.id = m.conversation_id where m.created < c.created;
select 'group member, not creator, no invite, joined > 10 min after the chat', count(*)
  from conversation_members m join conversations c on c.id = m.conversation_id
  where c.type = 'group' and m.user_id != c.created_by
    and not exists (select 1 from group_invites i where i.conversation_id = m.conversation_id and i.invited_user_id = m.user_id)
    and julianday(m.created) - julianday(c.created) > 10.0/1440;
select 'admins who joined by invite', count(*) from conversation_members m
  join group_invites i on i.conversation_id = m.conversation_id and i.invited_user_id = m.user_id
  where m.role = 'admin';
select 'users still on a v1 backup blob', count(*) from users
  where private_key_encrypted != '' and private_key_encrypted not like 'v2:%';
```

The first three counts are leads, not proof: an admin may have promoted a member. List the rows
for the user; never delete them in this step.

## Request tables (dry run; "live" marks the re-check)

### Part 1

Setup:
- `A` is admin of group `G`, `B` is a member of `G`.
- `C` is in neither, and is admin of their own chat `X`.
- `D` and `E` have pending invites to `G`.

| # | Request | Before | After |
|---|---|---|---|
| U1 (live) | `C` PATCHes their `X` member row: `conversation_id = G` | 200 | 400/404 |
| U2 | `C` PATCHes their `X` member row: `user_id = B` | 200 | 400/404 |
| U3 | `B` PATCHes their own `G` row: `role = admin` | 400/404 | 400/404 |
| U4 | `B` PATCHes their own `G` row: `muted_until` | 200 | 400/404 (D-1) |
| U5 | `A` promotes `B`, then demotes `B` | 200; 200 | 200; 200 |
| U6 (live) | `C` invites themselves to `X`, then PATCHes that invite to `conversation_id = G` | 200; 200 | 200; 400/404 |
| U7 | `A` flips `D`'s existing invite to `pending` (re-invite) | 200 | 200 |
| U8 (live) | `D` self-joins `G` with `role = admin` | 200 | 400 |
| U9 | `D` self-joins `G` with `role = member`, then sets the invite to `accepted` | 200; 200 | 200; 200 |
| U10 | `E` declines, then PATCHes the invite back to `pending` | 200; 200 | 200; 400/404 (D-2) |
| U11 | `A` creates a new group with `B` and `D` | works | works |
| U12 | `A` starts a new DM with `B` | works | works |
| U13 | `A` removes `B` from `G`; `D` leaves `G` | works | works |
| U14 | After U1 is refused, `A`'s app resyncs: no `group_keys` row is written for `C` | — | as stated |

### Part 2

Setup: `A` and `B` share `G`. `C` shares nothing with `A`. `A` has `current_chat = G` set.

| # | Request | Before | After |
|---|---|---|---|
| V1 (live) | `C` lists `users` | `A`'s `current_chat`, `typing_in`, `fcm_token` present | all three absent |
| V2 (live) | `C` lists `users` with `filter=current_chat="<G>"`; then `filter=id="<A>" && private_key_encrypted~"v"` | `A` returned; `A` returned | 400, or 0 rows, for both |
| V3 | `B` gets `A` by id | all present | `current_chat = G`, `typing_in` present; `fcm_token` and backup fields absent |
| V4 | `A` gets `A` | all present | all present (the owner unhides) |
| V5 (live) | `B` subscribes to `users/<A>`; `A` sets `typing_in = G`, then `typing_in = <a chat B is not in>` | both events carry the value | first carries `G`; second leaves `typing_in` hidden |
| V6 | `A` PATCHes their own `fcm_token`, `current_chat`, backup fields | 200 | 200 (writes to hidden fields still pass the update rule) |
| V7 | `C` lists `users` with `filter=friend_code="<A's code>"` | `A` returned | `A` returned (D-6) |
| V8 | Sign in as `A` (password) and through `/api/hooks/google-auth` on the copy if it can be exercised; check the auth response | backup fields present for `A` | still present for `A` |
| V9 | Timing: `C` lists 200 `users` with a presence value set on half | — | under 300 ms, and not more than 3× before |

If V2 returns 200 with rows after the change, **stop**: hidden fields are filterable on 0.37.5,
and the design needs a separate owner-only collection instead.

## Device check list (current build, M52 and Redmi, test accounts)

1. Create a group with two members. Everyone sees it and can send both ways.
2. Invite a third person. Decline, invite again, accept. Their messages decrypt after the
   rotation.
3. Promote the new member to admin, then demote them.
4. Remove a member. Their composer locks (removal-lock R1/R2 still works) and the group re-keys.
5. Leave a group from a member's phone.
6. Start a new DM with a friend and send both ways.
7. In a DM, the other phone shows **typing…** and **in chat** live. Leaving the chat clears it.
8. Settings → recovery key → check the key: it still finds the backup. A fresh sign-in on the
   other phone restores history with the recovery key.
9. Messages still raise push notifications on both phones (the hook reads `fcm_token` with
   `$app`).
10. Sign out and sign back in. Restore shows every group with the right members and roles.

## Must not undo

- The N1–N9 rules (`server-rules.md`), including members **list**. Its first branch keeps the
  removal re-check working for a removed member.
- The removal flow: delete the member row, then the pending invites
  (`message_repository_impl.dart:4040-4066`).
- Re-invite is an **admin update that sets only `status`** (`:3787`). M3's admin branch must still
  allow it (U7).
- The invite-accept order: member row first, then the invite → `accepted` (`:3877-3904`).
- `fcm_notify` and `disappearing_stamp` read users and members with `$app`. Hidden fields and rules
  don't apply to them.
- The key-backup guarantees from `key-backup.md` H2: the owner sees their own blob, nobody else
  does (now enforced by H1 plus V2–V4).
- Flat hooks, no heredocs through ssh, files written locally and copied (pb-hook pitfalls).

## Out of scope

D-3 (removed creator re-entry), D-4 (client-side wrap check), the D-6 alternative (presence to
friends only), moving v1 users to a recovery key (D-8), audit F4 and F7–F10, cleaning any existing
rows (D-5), and any app change.
