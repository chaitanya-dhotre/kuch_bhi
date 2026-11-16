# Membership and presence rules work log

Spec: `membership-rules.md` (rev 2, PASS 2026-11-16, all defaults).
Files: `docs/server/migrations/1794790000_updated_membership_presence.js`,
`docs/server/hooks/user_fields_unhide.pb.js`, and `docs/server/tests/`
(`membership_dry_run.sh`, `membership_request_table.py`, `tok.pb.js`, and
`mk.pb.js`). `mk.pb.js` makes throwaway users. The test hooks are for copies
only, never the live hooks folder.

## 2026-11-16 dry run (two copies of the live database, nothing live changed)

The user said yes to the dry run. Setup:
- "Before" = a copy plus the live `key_backup_hide.pb.js`.
- "After" = a copy with the migration applied plus the new hook, without
  `key_backup_hide.pb.js`.
- Every user and chat in the tables was a throwaway the script made on the
  copy. No real account or chat was used.

### Found on the first run: hidden fields can't be written by their owner

PocketBase 0.37.5 removes hidden fields from a non-superuser's create and
update body before the rule check and before any hook runs
(`apis/record_crud.go` `recordDataFromRequest`, then
`requestInfo.Body = data`). The PATCH still returns 200, but the value is
unchanged. So with H1 alone:
- presence (`current_chat`, `typing_in`) stops updating;
- `fcm_token` stops updating, and push breaks on a token change;
- the key backup can't be written.

V3 and V5 failed on the first run because of this: the presence values were
empty, so there was nothing to show the chat-mate.

The fix was added to the same hook file:
- a flat `onRecordUpdateRequest` on `users`;
- it runs only for the owner's own update;
- it re-reads the raw request body with `e.bindBody` into a `DynamicModel`
  whose defaults are a "not sent" marker, then sets each of the five fields
  that the request sent;
- if the body can't be read, it changes nothing.

Writing `requestInfo().body` back does not work, because that body has
already been stripped. Checks V6, V6b, V6d and V6e below cover this. No app
writes these fields on create (sign-up goes through the google_auth hook
with `$app`), so create needs no handler.

### Request tables (final run)

| # | Check | Before | After |
|---|---|---|---|
| U1 | C moves own X row into G | 200 | 404 |
| U2 | C sets own X row `user_id` = B | 200 | 404 |
| U3 | B makes self admin | 404 | 404 |
| U4 | B sets own `muted_until` | 200 | 404 (D-1) |
| U5 | A promotes B; demotes | 200; 200 | 200; 200 |
| U6 | C invites self to X; re-points it to G | 200; 200 | 200; 404 |
| U7 | A re-invites D (status only) | 200 | 200 |
| U8 | D self-joins G as admin | 200 | 400 |
| U9 | D joins G as member; invite → accepted | 200; 200 | 200; 200 |
| U10 | E declines; flips back to pending | 200; 200 | 200; 404 (D-2) |
| U11 | A new group, adds B and D; B reads it | 200s | 200s |
| U12 | A new DM with B | 200, 200, 200 | 200, 200, 200 |
| U13 | A removes B; D leaves | 204; 204 | 204; 204 |
| U14 | G's member list after U1 (what a resync wraps keys for) | A, C | A only |
| V1 | C lists users: fields on A; rows carrying a hidden field | 3 fields; 11 of 11 | none; 1 of 11 (C's own row) |
| V2 | C filters `current_chat=G`; `id=A && private_key_encrypted~"v"` | 200, 1 row; 200, 1 row | 400; 400 |
| V3 | B (shares G) gets A | presence + fcm | `current_chat`, `typing_in` only, value = G |
| V4 | A gets A; values equal what V6 wrote | all 5; yes | all 5; yes |
| V4b | C gets A | presence + fcm | none |
| V5 | B realtime on A: typing in G, then typing in a chat B is not in | both values, fcm too | first `G`; second hidden; no fcm |
| V6 | A writes own five fields | 200 | 200 (values stored, see V4) |
| V6b | A clears `typing_in` | `''` | `''` |
| V6c | B writes A's presence | 404 | 404 |
| V6d | A updates only `is_online`: fcm and backup untouched | yes | yes |
| V6e | A multipart update (`about` + `fcm_token`) | — | 200, both stored |
| V7 | C finds A by friend code | 1 row | 1 row (D-6) |
| V8 | A password sign-in: auth response | all 5 | all 5 |
| V8b | A auth-refresh | all 5 | all 5 |
| V9 | C lists 200 users, presence on half (median of 7) | 152 ms | 224 ms (1.5×; limits 300 ms / 3×) |

Not exercised: the `/api/hooks/google-auth` sign-in, which needs a real
Google token. That hook builds its response the same way as the
password and refresh responses (V8, V8b). Device check 8 covers it.

### Rollback (on the after copy)

`migrate down 1` puts back all three rule strings byte for byte, and no
`users` field is hidden afterwards. A local check also compared the down
strings with bible lines 763, 764 and 1050.

### Read-only counts (live, untouched; D-5, D-8)

| Count | Value |
|---|---|
| Member row older than its chat | 0 |
| Group member, not creator, no invite, joined more than 10 min after the chat | 2 |
| Admins who joined by invite | 0 |
| Users still on a v1 backup blob | 1 |

The 2 leads are both `hehehehehe`:
- `Test Group 44`, created by `minato`, joined 17 min after the chat, role
  admin. It was 2026-06-30, before invites existed or after an invite was
  deleted.
- `4chan`, created by `ichigo`, joined 15 min after the chat, role member.

Both look like normal adds by the creator. Nothing was deleted (D-5).

No errors in either copy's log.

## 2026-11-16 live (user go-ahead "Yes, with throwaways")

- The live re-check script (`docs/server/tests/membership_live_check.py`)
  was first run once against a copy.
- Backups:
  - `/home/ubuntu/pb_backups/data.db.20261116-membership-pre`
  - `/home/ubuntu/pb_backups/pb_hooks.20261116-membership-pre`
- One stop/start of PocketBase, with these changes in between:
  - migration added to `pb_migrations`;
  - `user_fields_unhide.pb.js` added to `pb_hooks`;
  - `key_backup_hide.pb.js` moved to
    `/home/ubuntu/pb_backups/key_backup_hide.pb.js.20261116-removed`.
  - Files were copied with scp, then `sudo install`. No heredoc.
- After the restart:
  - `_migrations` shows `1794790000_updated_membership_presence.js`
    (17:33:30 UTC);
  - the hidden `users` fields are the five plus `password` and `tokenKey`;
  - health returns 200, and the journal has no errors.

Live re-checks: three throwaway accounts signed up on the live server, with
throwaway chats. No real account or chat was used.

| # | Check | Live |
|---|---|---|
| V6 / V4 | A writes own presence and fcm; reads them back | 200; values match |
| V1 | C lists users: fields on A; rows carrying a hidden field | none; 1 of 8 (C's own) |
| V2 | C filters `current_chat=G`; `id=A && private_key_encrypted~"v"` | 400; 400 |
| V5 | B realtime on A: typing in G, then in a chat B is not in | `G`; hidden (no fcm in either) |
| U1 | C moves own X row into G | 404 |
| U6 | C invites self to X; re-points it to G | 200; 404 |
| U8 | C (invited to G) self-joins as admin | 400 |
| U14 | G's members | A, B only |

Throwaway rows, all deleted (all deletes 204):
- users `wh8brbjpv1kni4h`, `awbnhmajwurcgbq`, `bcoj300p9cfx3nj`;
- chats `1lacxz597ratf5i`, `h7lcgartrgy5b10`, `qbpxnnfqd2bh68d`, with their
  member rows and invites.

A read-only check afterwards found 0 users, chats, member rows, invites or
group keys left that point at them. `/tmp/mt` and the copies were removed.

Rollback, either of:
- as the `pocketbase` user in `/opt/pocketbase`, run
  `yes | ./pocketbase migrate down 1`, put `key_backup_hide.pb.js` back,
  remove `user_fields_unhide.pb.js`, restart;
- or restore both backups.

Bible §7 updated: members create/update, invites update, and the five
hidden `users` fields with the hook named.

Device check: user PASS 2026-11-16 (10 steps, M52 + Redmi, current build).
