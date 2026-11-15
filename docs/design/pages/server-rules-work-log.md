# Server rules work log

## 2026-11-15 dry run (two copies of the live database, nothing live changed)

Files: `docs/server/migrations/1794700100_updated_rules_scope.js`,
`docs/server/tests/` (request table script, runner, throwaway token hook; the
hook is for test copies only, never the live hooks folder).
A = a group admin, B = a member who shares a DM with A, C = a user in neither
(C is in 18 other chats and has sent 207 messages). 37 chats on the server.

| # | Check | Before | After |
|---|---|---|---|
| T1 | C lists chats | all 37, sees the group | 19, does not see it |
| T2 | A lists chats; opens the group | 37; 200 | 17; 200 |
| T3 | C renames the group | 200 | 404 |
| T4 | B (member) sets the timer; sets `created_by` | 200; 200 | 200; 404 |
| T5 | C lists the group's members | 2 of 2 | 0 |
| T6 | A lists B's memberships | 29 (all) | 12 (the shared ones) |
| T7 | C lists the DM's receipts | 21 of 21 | 0 |
| T8 | B lists receipts on B's messages in the DM | 8 | 8 |
| T9 | C forges a read receipt as A | 200 | 400 |
| T10 | B makes an empty receipt for A; a pre-read one | 200; 200 | 200; 400 |
| T11 | A makes own receipt; sets read; re-points it | 200; 200; 200 | 200; 200; 404 |
| T11b | A fills in the placeholder B made; B sees it | 200; yes | 200; yes |
| T12 | C attaches media to B's message; B to own | 200; 200 | 400; 200 |
| T13 | C stars / deletes-for-me as A; A for self | 200; 200 | 400; 200 |
| T14 | New group: create, read, add self, add B, B reads, C reads | all 200 | all 200, C 404 |
| T15 | Invite C: reads while pending; after declining | 200; 200 | 200; 404 |
| T16 | Realtime after a rename and a receipt update | A, B and C all get both | A and B get both, C gets none |

Timing (median of 7, ms): members list 2 → 2; receipts list 10 → 7;
messages page 3 → 3; **chat list 4 → 18** (over the spec's "3× slower" line,
far under its 300 ms line).

A lists 17 chats but is a member of 16 (C: 19 vs 18): the extra one is a
chat they created or hold a pending invite to (decision S-2).

S-4 counts on live (read-only, nothing deleted): 1290 receipts; 145 whose
recipient is not a member of that chat now (people who left or were removed
would look the same, so this is not proof of forgery); 6 where the recipient
is the sender; 2 stars by non-members; 0 delete-for-me by non-members;
0 media rows on another chat's message; 0 polls.

Not run: the live step, the device check, a rollback (`migrate down`) test.

## 2026-11-15 live (user go-ahead "Yes, apply live")

- Rollback tested on a copy first: up changes 7 collections, `migrate down 1`
  restores the original rules exactly.
- Backup `/home/ubuntu/pb_backups/data.db.20261115-rules-pre`; migration
  moved into `/opt/pocketbase/pb_migrations`; one PocketBase restart.
- `_migrations` shows `1794700100_updated_rules_scope.js`; the live rule
  set hashes the same as the copy the 16 checks ran on (`8068f41a1160`).
- Through nginx: health 200, reset page 200, admin 404, signed-out lists
  return 0 rows. No errors in the service log; the first live requests
  after the restart returned 200.
- NOT done: the signed-in request table against live. It would need
  signing in as real accounts on the live server (the token hook is for
  copies only). The user's device check covers it.
- Rollback: `yes | /opt/pocketbase/pocketbase migrate down 1` as the
  `pocketbase` user in `/opt/pocketbase`, then restart; or restore the backup.
- Bible §7 rule lines rewritten from live after the change.

Device check: user PASS 2026-11-15 (8 steps, current app build).
