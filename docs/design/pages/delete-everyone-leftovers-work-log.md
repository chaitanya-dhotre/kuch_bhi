# Delete for everyone leftovers: server part work log

Spec: `delete-everyone-leftovers.md` §5, decision D-11 option (a). Client part: commit `168844b`.

## 2026-11-18: plan and dry run (copies only, nothing live changed)

### What was built (repo copies under `docs/server/`)

| File | What it does |
|---|---|
| `hooks/delete_everyone_purge.pb.js` | Flat `onRecordAfterUpdateSuccess` on `messages`. When the saved row has `is_deleted_for_everyone` true: deletes its `message_media` rows with `$app.delete` (PocketBase removes the files), blanks its `encrypted_body`, `iv` and `reply_preview`, and blanks `reply_preview` on any reply whose `reply_to_id` is this message. |
| `migrations/1794820000_updated_media_hide_deleted.js` | `message_media` list, view and create rules gain `&& message_id.is_deleted_for_everyone = false`. Same forms as before. Down restores the exact strings read live on 2026-11-18. The create clause was added after dry run 1 (user choice, "Add upload guard first"). |
| `migrations/1794820100_cleanup_deleted_for_everyone.js` | One-off cleanup of rows already deleted: their media rows (`app.delete`, files go), body, iv and preview, and the previews of replies that quote them. Guarded: it touches only flagged rows and their replies, and it throws (the migration fails and changes nothing) if more than 200 rows are flagged. It has no down step, because only the dated backup can restore deleted files. |
| `tests/deleted_dry_run.sh`, `tests/deleted_request_table.py` | The dry run (below). Reuses `tests/tok.pb.js` and `tests/mk.pb.js`. |

### Decision: how to blank the Required body fields

`encrypted_body` and `iv` are Required (min 0, max 0, required true on the live schema). The three options:

- **Direct SQL (chosen).** `disappearing_messages.pb.js` already uses it for expired rows. It skips validation and fires no second update. So it causes no second realtime broadcast, phones do not re-ingest the row, and the hook cannot call itself again.
- `$app.saveNoValidate`: works, but it broadcasts a second update with an empty body and runs the update hooks again.
- Making the fields optional: a schema change that also lets clients create messages with empty bodies. More change, no gain.

Cost of the choice (D7 and D9 below): once a row is blanked, any later save of it fails validation with `400 validation_required`. The cases are a repeated delete or a pin on a deleted message. Expired rows already work this way. The client handles it: `deleteMessage` catches and logs, `_markCancelledOnServer` treats a non-404, non-transient error as done, and `_finishCancelledText` drops the op. None of them retries forever.

The hook matches on "flag is true", not on "flag just turned true". Every save that ends with the flag set is a deletion, and the work it does is idempotent. It also needs no `original()`.

### Dry run method

This is the same recipe as N1–N9 and wave 2. On the VM, two `.backup` copies were made of the live `data.db`, each with a copy of `pb_migrations`. Each copy ran under the live binary `/opt/pocketbase/pocketbase` (0.37.5) on a spare port:

- **before** (8098): live rules and the live hooks `disappearing_stamp`, `former_member_record` and `user_fields_unhide`. The cron and push hooks were left out.
- **after** (8099): the same, plus both migrations (`migrate up`) and the new hook.

The 8 media folders of flagged messages were copied into the after copy's storage, so the cleanup's file removal can be seen on disk. The request table makes its own throwaway users A and B (friends, B a member of A's group) through test-only routes. Everything was deleted at the end (`rm -rf /tmp/pbtest /tmp/del`). The live DB and storage were only read.

### Output (2026-11-18 07:42 UTC)

```
##### counts BEFORE (copy of live)
flagged messages|35
flagged with body or iv|35
flagged with a preview|0
media rows of flagged|8
previews non-empty|21
previews quoting flagged|2
unflagged with a body|1090
messages total|1138
media total|90
flagged media folders on disk: 8
##### migrate up (after copy)
[cleanup] flagged 35 blanked 35 media deleted 8 quotes blanked 2
Applied 1794820000_updated_media_hide_deleted.js
Applied 1794820100_cleanup_deleted_for_everyone.js
##### our migrations applied: 2
##### counts AFTER
flagged messages|35
flagged with body or iv|0
flagged with a preview|0
media rows of flagged|0
previews non-empty|19
previews quoting flagged|0
unflagged with a body|1090
messages total|1138
media total|82
flagged media folders on disk: 0
##### message_media rules after
1|w) && message_id.is_deleted_for_everyone = false
##### the real member with most media: chats' flagged media rows on the before copy
8
##### D table BEFORE (live rules, no hook)
setup  B joins group 200; B lists mImg media 1; mImg file 200 thumb 200
D1     A deletes the photo mImg for everyone: 200
D2     A deletes the text mTxt for everyone: 200
D3     B lists mImg media: 1; views it: 200
D4     mImg file by URL: 200; thumb: 200
D5     B reads mImg body='eA==' iv='aXY=' flag=True; mTxt body='eA=='; reply preview='cHJldg==' body='eA=='
D6     live mLive: B lists 1, views 200, file 200, thumb 200, body='eA=='
D7     A retries the delete on mImg: 200
D8     B pins live mLive: 200; body after='eA=='
D9     B pins deleted mImg: 200
D10    A uploads media to deleted mImg afterwards: 200; B lists 2, views 200; file by URL 200
D11    B lists the group media, median of 7: 2 ms
real   real member lists all media: totalItems=87 (2 ms)
##### D table AFTER (new rules + hook)
setup  B joins group 200; B lists mImg media 1; mImg file 200 thumb 200
D1     A deletes the photo mImg for everyone: 200
D2     A deletes the text mTxt for everyone: 200
D3     B lists mImg media: 0; views it: 404
D4     mImg file by URL: 404; thumb: 404
D5     B reads mImg body='' iv='' flag=True; mTxt body=''; reply preview='' body='eA=='
D6     live mLive: B lists 1, views 200, file 200, thumb 200, body='eA=='
D7     A retries the delete on mImg: 400 {"encrypted_body": {"code": "validation_required", ...}, "iv": {...}}
D8     B pins live mLive: 200; body after='eA=='
D9     B pins deleted mImg: 400 {"encrypted_body": {"code": "validation_required", ...}, "iv": {...}}
D10    A uploads media to deleted mImg afterwards: 200; B lists 0, views 404; file by URL 200
D11    B lists the group media, median of 7: 2 ms
real   real member lists all media: totalItems=79 (2 ms)
##### rollback on the after copy (down 2: cleanup no-op, then rules)
Reverted 1794820100_cleanup_deleted_for_everyone.js
Reverted 1794820000_updated_media_hide_deleted.js
message_media rules after down == original
our migrations left in _migrations|0
##### errors in logs
(none)
```

### What it shows

- **Cleanup:** it removed exactly what the L6 read found: 35 bodies, 8 media rows with all 8 folders gone from disk, and the 2 quoting previews. The other 19 previews, all 1090 live bodies and every row count are unchanged. Media went from 90 to 82, which is the 8 removed rows.
- **Member can no longer list or view deleted media:** D3 went from 1 to 0 rows and from 200 to 404 on view. For the real member with the most media, the list went from 87 to 79, which is exactly the 8 flagged rows in their chats.
- **Files gone by URL:** D4, the file and its thumbnail went from 200 to 404.
- **Deleted bodies and quotes are blank:** D5. The reply keeps its own body.
- **Live media and messages unaffected:** D6, D8 and the "unflagged with a body" count.
- **The client's delete-for-everyone update still succeeds:** D1 and D2 return 200 with the client's exact body `{is_deleted_for_everyone: true}`.
- **Repeat saves of a blanked row get 400:** D7 and D9, by design (see the decision above).
- **Speed:** the new clause joins `message_id`, which the expiry clause already joins. The list takes 2 ms on both copies.
- **Rollback:** after `migrate down 2`, the rules are byte-identical to the original and no migration rows are left.

### Dry run 1 found: media uploaded after the delete (D10)

The create rule did not check the flag. So an upload that landed after the message was flagged still got saved, and its file was public by URL (D10 above: 200, file 200). One way this happens is a cancelled media send whose multipart POST is already in flight. The list and view rules hid the row, but the hook had already run, so the file stayed on disk until media expiry.

The user chose to add the upload guard before going live. `1794820000` now also appends the clause to the `message_media` createRule.

Client check (code read 2026-11-18) of a refused upload: the media pipeline's `catch` in `message_repository_impl.dart` returns early when `ticket.cancelled`, so a cancelled send ignores the 400. A send that is not cancelled can only hit the guard if its message was already deleted for everyone (for example from the sender's other phone). That send is marked `failed` locally. The retry path's `_mediaRecordFor` now gets a 404 for such a message and re-uploads, which gets a 400 and ends as `failed` again. It does not loop.

### Dry run 2 (2026-11-18 07:46 UTC, with the upload guard)

Same script, same copies. Every line matched dry run 1 except these:

```
##### message_media rules after
1|w) && message_id.is_deleted_for_everyone = false|message_id.sender_id = @request.auth.id && conversation_id = message_id.conversation_id && message_id.is_deleted_for_everyone = false
D10 (AFTER)  A uploads media to deleted mImg afterwards: 400; B lists 0, views 404; file by URL 404
##### rollback
message_media rules after down == original      (list, view, create, update, delete compared)
our migrations left in _migrations|0
##### errors in logs
(none)
```

Normal uploads still succeed on the after copy: the setup photo and `mLive` both returned 200 and were listed, viewed and fetched. The cleanup line was identical (35 / 35 / 8 / 2). Live createRule read before the run: `message_id.sender_id = @request.auth.id && conversation_id = message_id.conversation_id`, which matches `OLD_CREATE`.

### Other notes

- The API response to the delete PATCH and the realtime update to members are built from the in-memory record, so they still carry the old ciphertext. Every receiver already held it, so this leaks nothing new. The phones blank it on the flag (`168844b`).
- The `reply_preview` of a reply to a deleted message is blanked through `reply_to_id`. The L6 count of 2 matched, so `reply_to_id` holds the server id here.

## 2026-11-18: LIVE (user: "Yes, go live")

**Backups** in `/home/ubuntu/pb_backups/`:
- `data.db.20261118-delete-everyone-pre`: integrity ok, 1138 messages, 90 media.
- `pb_hooks.20261118-delete-everyone-pre/`.
- `media.20261118-delete-everyone-pre.tar.gz`: the 8 flagged media folders, 28 files, 8.4 MB.

**Install.** The files were copied with scp to `/tmp/dl`, then put in place with `sudo install -o pocketbase -g pocketbase` (no heredoc):
- the two migrations into `pb_migrations` (644)
- the hook into `pb_hooks` (664)

Then `systemctl restart pocketbase`. sha256 of what was installed:
- `1794820000`: `8c905e93…5344082`
- `1794820100`: `57873dbf…105fd561`
- hook: `21a22774…6021a187f`

**After the restart:**
- Service active, `/api/health` 200, both files in `_migrations`.
- Journal: `[cleanup] flagged 35 blanked 35 media deleted 8 quotes blanked 2`.
- Live counts: flagged with body or iv 0, media rows of flagged 0, previews quoting flagged 0, previews 19, unflagged with a body 1090, messages 1138, media 82.
- Flagged media folders on disk: 0.
- The list, view and create rules all end with the new clause.

**Live re-check** (`docs/server/tests/deleted_live_check.py` on 127.0.0.1:8090, 2 throwaway sign-ups, B as the sender). Every result was as wanted:

```
setup  B joins group 200; A lists mImg media 1; mImg file 200 thumb 200
D1     B deletes the photo mImg for everyone: 200
D2     B deletes the text mTxt for everyone: 200
D3     A lists mImg media: 0; views it: 404
D4     mImg file by URL: 404; thumb: 404
D5     A reads mImg body='' iv='' flag=True; mTxt body=''; reply preview='' body='eA=='
D6     live mLive: A lists 1, views 200, file 200, thumb 200, body='eA=='
D7     B retries the delete on mImg: 400 validation_required
D8     A pins live mLive: 200; body after='eA=='
D10    B uploads media to deleted mImg afterwards: 400; A lists 0
del user B 204; del chat 204; del user A 204
```

Before and after the check: users 5, chats 46, messages 1138, media 82, `dryrun_` users 0. Nothing was left behind. The journal shows no `purge failed`, errors or panics.

**Rollback:**
- Rules: `migrate down 1` for `1794820000` (the down was tested on the copy), then move `delete_everyone_purge.pb.js` out of `pb_hooks`.
- Data: restore `data.db.20261118-delete-everyone-pre` and untar the media backup into `pb_data/storage/pbc_2092852118/`.

**Left:**
- The two-phone device check from spec §6.
- Update bible §7 with the new `message_media` strings once the device check passes, as wave 2 did.
- Commit the repo copies (uncommitted for now).

## 2026-11-18: device check

**Device PASS** (user, two phones, spec §6 against the live server). Bible §7.6 and §7.7 now carry the live strings and the hook behaviour.
