# Former-member history: work log (phase 2)

Spec: `former-member-history.md` (PASS 2026-11-16, all defaults D-1..D-8).

## Files (uncommitted)

- `docs/server/migrations/1794800000_former_members.js`: S1 collection (unique index on conversation_id + user_id, list/view own rows, create/update/delete `null`), then R1–R3. Down restores the old list/view strings and drops the collection.
- `docs/server/hooks/former_member_record.pb.js`: S2, flat `onRecordDeleteRequest` on `conversation_members`. It runs `e.next()` first, then upserts in a log-only `try`, for groups only. It keeps the earliest `joined_at` and sets `history_until` to the server's now.
- `lib/infrastructure/repositories/message_repository_impl.dart`: C1 is `_syncFormerGroups`, called after the member loop. The conversation upsert moved into `_upsertConversationRecord`, shared by both paths. `_emitLocalSystemMessage` gained an optional `at`.
- `test/offline/former_groups_test.dart`: 5 tests (removed, left, local row kept, re-add wins, missing collection).
- Dry-run helpers (test copies only): `docs/server/tests/fm.pb.js` (superuser token, bulk messages), `former_request_table.py`, `former_dry_run.sh`.

## Tests

- Baseline before any change: 1400/1400.
- After C1: **1405/1405** (+5 new).
- `flutter analyze`: no errors. The new lines add only `expand`/`created` deprecation infos, the same as the code around them.

## 2026-11-16 dry run (two `.backup` copies of live `data.db` on the VM, ports 8098 before / 8099 after; nothing live changed)

- Migration applied cleanly; no errors in either log.
- Throwaway accounts only for the F table. T1–T16 use real rows, but only on the copy, as in earlier runs.

| # | Before | After | Pass |
|---|---|---|---|
| F3 (first) | m3 not shown | **m3 not shown** (C's G row and B's K row both end after m3) | yes: same-row `?>=` works on 0.37.5, **B stands, no B2** |
| F1 | 0 rows | m1, m2 | yes |
| F2 | 0 | m1, m2, m3, "C left"; not m4 | yes |
| F4 | 0; 404 | 0; 404 | yes |
| F5 | 404 | 404 | yes |
| F6 | 0; 404 | m1's media row; 200 | yes |
| F7 | neither | G and K (total 2) | yes |
| F8 | 0; own v1 | 0; own v1 only | yes |
| F9 | 404 (no collection) | B: G removed, K removed; C: left; D: 0 and 0 | yes |
| F10 | 400 | 400 | yes |
| F11 | 400; 404 | 400; 404 | yes |
| F12 | 404 | 403 on all four | yes |
| F13 | B no event, A control yes | B no event, A control yes | yes |
| F14 | — | re-join sees all; removed again: still 1 row, history_until later, joined_at kept. After the 2nd removal B lists m3–m5 too: the gap rows, by D-8 (no key, stay hidden on the phone) | yes (as designed) |
| F15 | — | K's former row 1 → 0 after cascade | yes |
| F16 | — | DM delete writes no row | yes |
| F17 | A, C | A, C | yes |
| **F18** | member A 150 ms | member A 476 ms (3.2×), former B 855 ms: **NO** (bar: under 300 ms, at most 1.5×). Fixed in dry run 2 below |
| F19 | — | T1–T16 identical; U/V identical except V5's random chat id | yes |

- Other timing in T-table: conversations as A 21 → 73 ms; messages page as A 3 → 5 ms.
- Rollback: `migrate down` on the after copy brings the three collections' list/view rules back byte-identical to live, and the collection is gone.

### D-5 counts (read-only, copy of live)

- Former pairs (own key rows, no member row): **12**
- Of those, back-fillable (a newer version wrapped for someone else): **11**
- Former pairs in DMs: 0
- No rows written.

## F18 fix: rule shape (user picked "try a cheaper rule", 2026-11-17)

Timed on one copy with `former_rule_timing.py`, via `former_timing_run.sh`. Member A pages 2,000 rows. Former X pages the same 2,000 rows, and X is also a former member of 30 more chats. Each figure is the median of 9 page-throughs, and F3 was checked for every shape.

| Shape (messages list/view) | Member | Former | F3 |
|---|---|---|---|
| old rule (member only) | 183–185 ms | — | — |
| v0 `@collection` member `\|\|` `@collection` FM (dry run 1) | **5,096 ms** | 5,021 ms | holds |
| v1 the same with an alias `:fm` | 5,098 | 5,012 | holds |
| v3 FM branch first | 4,851 | 4,579 | holds |
| v2 `@collection` member `\|\|` back-relation FM | 565–577 | 1,096–1,111 | holds |
| v4 back-relation member alone (no FM) | 113 | — | — |
| **v5 back-relation member `\|\|` back-relation FM** | **115** | **118** | holds |

- An `||` of two `@collection` joins grows with the size of `former_members`. With X in 31 former chats it reached 5 s, compared with 476 ms in dry run 1.
- The back-relation form `conversation_id.<coll>_via_conversation_id.<field>` joins only the rows of this row's own chat.
- The member branch `conversation_id.conversation_members_via_conversation_id.user_id ?= @request.auth.id` means the same as the old `@collection` pair: some member row of this row's chat is mine. T1–T16 and U/V came out identical.
- R3 on `conversations` uses `former_members_via_conversation_id.user_id ?= @request.auth.id`.
- The migration now uses v5. The down step still restores the exact old strings.

## 2026-11-17 dry run 2 (v5 migration; same script, fresh copies of live)

- F1–F17: same results as dry run 1, all pass (F3: m3 not shown).
- **F18: member 151 → 112 ms (faster than before), former 115 ms. Pass.**
- F19: T1–T16 identical; U/V identical except V5's random chat id. Conversations as A: 21 → 34 ms.
- Rollback: rules after `migrate down` are byte-identical to live, and the collection is gone. No errors in the logs.

## Found (not changed here)

- The `message_media` create rule checks only `message_id.sender_id`, not that the row's `conversation_id` matches its message's chat. The read rules use the row's own `conversation_id`. So a sender could file a media row under another chat, and that chat's members (now also its former members) could list it. This existed before this change. It belongs with the server-rules wave 2 spec.

## Next

The live step waits on the user's go-ahead. Back-fill (D-5: 11 rows) needs a separate yes.

## 2026-11-17 live step (user: "Yes, go live")

- Backups: `/home/ubuntu/pb_backups/data.db.20261117-former-pre` (sqlite `.backup`) and `/home/ubuntu/pb_backups/pb_hooks.20261117-former-pre/` (9 files).
- Copied with `scp`, then `sudo install -o pocketbase` into `pb_migrations/1794800000_former_members.js` and `pb_hooks/former_member_record.pb.js`. No heredoc.
- One `systemctl restart pocketbase`: active. `_migrations` shows the new file, the `former_members` collection exists, and the messages rule is in the v5 form. No errors in the journal.
- Live re-check (`docs/server/tests/former_live_check.py` on 127.0.0.1:8090, 3 throwaway sign-ups, 1 throwaway group):
  - F3: m3 not shown; B views m3 → 404
  - F1: B lists G → m1, m2
  - F2: C (left) lists G → m1, m2, m3
  - F9: B's row says `removed`, C's row says `left`; A can't list B's rows (0)
  - F10: B creates a message → 400
  - F13: B gets no event for m4; A (control) does
- Throwaways deleted: users A `47ts7p36kato5o8`, B `5x85543jnwb23d1`, C `v47wotafkyc4nkh`, chat `lty05wnsnt8jw0z` (all 204). Afterwards: 0 `dryrun_` users, 0 `dryrun` chats, 0 `former_members` rows.
- Rollback: `migrate down` (tested on the copy) and remove the hook, or restore both backups.
- Bible §7 updated: 7.4/7.6/7.7 headers point to the new 7.17 `former_members` section, and their rule strings are updated.
- D-5 back-fill: not done (11 back-fillable pairs). It needs a separate yes.

## 2026-11-17 D-5 back-fill (user: "Back-fill all 11")

- Migration `docs/server/migrations/1794800100_former_members_backfill.js`.
  - It finds pairs with own `group_keys` rows, no member row, no existing former row, and a newer version for someone else.
  - `history_until` = the `created` time of the first newer version. `joined_at` = the earliest own key row. `reason` is blank.
  - Down deletes only rows with a blank reason.
- Copy first: back-filled 11, all groups, 1–22 messages each in their windows. Down removed only those 11; the 2 hook-written rows stayed.
- Live:
  - Backup `/home/ubuntu/pb_backups/data.db.20261117-former-backfill-pre`.
  - `scp` + `sudo install`, then one restart. The journal shows `[former_members] back-filled 11`.
  - Live rows now: 11 with a blank reason, 1 `left`, 1 `removed`. The last two were written by the hook at 05:24 and 05:30 on 2026-11-17, from real use after the live step.
- Back-filled rows show no "You were removed" line on the phone (blank reason, by D-4/D-5).

## 2026-11-17 device PASS (user: all §7 items)
