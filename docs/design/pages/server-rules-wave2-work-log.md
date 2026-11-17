# Server rules wave 2: work log (phase 2)

Spec: `server-rules-wave2.md` (PASS 2026-11-17, all defaults X-1..X-8).

## Files (uncommitted)

- `docs/server/migrations/1794810000_updated_rules_wave2.js`: N10–N18 up; down restores the old strings.
- `docs/server/tests/wave2_probe.py`: tries each N11 shape on its own copy (rule patches through a superuser token), checks the Q7/Q8 cases and times them, then puts the migration's rule back.
- `docs/server/tests/wave2_request_table.py`: Q1–Q19, throwaway users only.
- `docs/server/tests/wave2_dry_run.sh`: three `.backup` copies of live (before 8098, after 8099, probe 8097), the X-7 counts, both tables, the rollback check.
- Reuses `tok.pb.js`, `mk.pb.js`, `fm.pb.js` (test copies only).

## N11 as built (differs from the spec text in form, not in meaning)

- **Branch 1, "no member rows yet":** the spec's first choice, `@collection.conversation_members:existing.conversation_id != conversation_id`. It works on 0.37.5: a bare `!=` is checked against all rows.
  - The spec's fallback 2, `<back-relation>:length = 0`, is **refused** by 0.37.5 ("unknown field"). Fallback 3 (a hook) was not needed.
  - `conversation_id.conversation_members_via_conversation_id.id = ""` also works. It was not picked, because the spec's first choice passed.
- **Branches 2 and 3 use back-relations** instead of `@collection` pairs:
  - admin: `conversation_id.conversation_members_via_conversation_id.user_id ?= me && ….role ?= "admin"`
  - friend: `user_id.friendships_via_user_a.user_b ?= me || user_id.friendships_via_user_b.user_a ?= me`
  - invite: `conversation_id.group_invites_via_conversation_id.invited_user_id ?= me && ….status ?= "pending"`
  - Why: the spec's `@collection` form already took **34–51 ms** for "add a friend" on today's tiny tables (89 member rows, 7 friendships), against 2–3 ms for the back-relation form. An `||` of `@collection` joins grows with table size (the former-members F18 learning).
  - Same meaning: the probe gave identical results for both forms on all 7 checks.

## 2026-11-17 dry run (copies of live; nothing live changed)

Live sizes: 5 users, 43 chats, 89 member rows, 7 friendships, 8 friend requests, 12 invites, 1,092 messages, 27 reactions.

First attempt: the migration used `:length = 0`, was refused, and the after server never started. That's why the script now stops when `_migrations` lacks the file. Second attempt: the probe's rule patches wrote auto-migration files on its copy, so `migrate down 1` reverted the wrong file. The probe now gets its own copy. The third run below is the record.

### Probe (N11 shapes)

| Shape | first own row | add friend | add stranger / as admin | removed creator re-adds admin / member | invitee joins | non-creator own admin row | add-friend time |
|---|---|---|---|---|---|---|---|
| today | 200 | 200 | **200** / 400 | **200** / 400 (dup index) | 200, 200 | 400 | 2 ms |
| spec `@collection`, E `!=` | 200 | 200 | 400 / 400 | 400 / 400 | 200, 200 | 400 | 34 ms |
| **back-relation, E `!=` (built)** | 200 | 200 | 400 / 400 | 400 / 400 | 200, 200 | 400 | **3 ms** |
| either form, E `:length = 0` | rule refused | | | | | | |
| spec `@collection`, E `id = ""` | 200 | 200 | 400 / 400 | 400 / 400 | 200, 200 | 400 | 51 ms |
| back-relation, E `id = ""` | 200 | 200 | 400 / 400 | 400 / 400 | 200, 200 | 400 | 3 ms |

### Request table

| # | Before | After | Pass |
|---|---|---|---|
| Q1 | 200 | 400 | yes |
| Q2 | 200; 200 | 200; 200 | yes |
| Q3 | 200; 200 | 400; 400 | yes |
| Q4 | 200; 200; 200 | 200; 200; 400 | yes |
| Q5 (multipart icon) | works, icon set | works, icon set | yes |
| Q6 | works | works | yes |
| Q7 | 200; 204; 200; 200 | 200; 204; **400; 400** | yes (D-3 closed) |
| Q7b | 200; 200; 200 | 200; 200; 200 | yes |
| Q8 | 200 | 200 | yes |
| Q9 | 200; 200 | 400; 200 | yes |
| Q10 | 200; 200; 404; 404 | 404; 404; 404; 200 | yes |
| Q11 | 200; 200; 200 | 400; 400; 400 | yes |
| Q12 | 200 | 400 | yes |
| Q13 | 200, 204; 200; 200, 200 | 200, 204; 400; 200, 403 | yes |
| Q14 | 200; 200 | 400; 200 | yes |
| Q15 | 200; 200 | 403; 403 | yes |
| Q16 | 200; 400 | 200; 400 | yes (X-4: unchanged) |
| Q17 | 3 / 3 / 2 ms | 3 / 3 / 3 ms (own first row / add friend / reaction) | yes |
| Q18 | friendships 4, requests 6, reactions 13, members 25 | 1, 5, 10, 21 | yes: each drop is exactly the writes now refused |
| Q19 | 200; 200; 200 | 200; 200; 200 | yes |

- Rollback: `migrate down 1` on the after copy gives create/update/delete rules **byte-identical** to live for all 8 collections.
- No errors in any of the three logs.

### X-7 counts (read-only, copy of live)

- friendships with no accepted request either way: 0
- DM pairs who are not friends: 0
- chats whose creator is no longer a member: 0
- reactions by someone not a member now: **1** (most likely a former member's old reaction; report only)
- reactions whose message is in another chat: 0
- media rows in another chat than their message: 0
- polls rows: 0; scheduled_messages rows: 0

Nothing deleted.

### Not covered by the dry run

- The older tables (T1–T16, U/V, F) were not re-run. Their setup adds members who aren't friends, so they now fail at setup by design. This migration changes no read rule and none of the rules those tables check, apart from members create, and Q5–Q8, Q19 and the probe cover that rule.
- Timing on tiny tables only (89 member rows). The back-relation form is the one that stays flat as tables grow.

## 2026-11-17 live step (user: "Yes, go live")

- Backup: `/home/ubuntu/pb_backups/data.db.20261117-wave2-pre` (1.35 MB, `.backup` of the live DB).
- `scp`, then `sudo install -o pocketbase` into `pb_migrations/1794810000_updated_rules_wave2.js`. One restart. `_migrations` lists it, the service is active, and the journal shows no errors.
- Live re-check (`docs/server/tests/wave2_live_check.py` on 127.0.0.1:8090, 3 throwaway sign-ups), all as wanted:
  - Q1: 400
  - accept flow: 200s
  - Q5 (add a friend): 200
  - the DM: 200s
  - Q3 (stranger adds A): 400
  - Q9: 400
  - Q11: 400
  - Q12: B 200, C 400
  - Q14: naming AB 400, naming G 200
  - Q7 (removed creator re-adds as admin): 400
- **Cleanup miss.** The throwaway group and its creator returned 400 on delete.
  - Cause: `message_media.conversation_id` is a **required relation with no cascade**, so a chat that holds media can't be deleted. Its creator then can't be deleted either, because `conversations.created_by` is required.
  - This was true before this change. It also means a creator can't delete any chat that has media.
  - The script now deletes the sender first, which cascades their messages and media.
  - The two leftovers (an empty group and a `dryrun_` account) were removed with the user's go-ahead by a guarded one-off migration, `1794810100_cleanup_wave2_dryrun.js`, and a second restart.
  - After: 0 `dryrun_` users. Users 5, chats 43, the same as before the run.
- Rollback: `migrate down` (for `1794810000`), or restore the backup.

## 2026-11-17 device check

**Device PASS** (user, M52 + Redmi, current build): all 7 items of spec §7. Bible §7 updated with the live strings.
