# Groups: history comes back after a re-add (spec, rev 1)

Status: **spec PASS 2026-11-14, all defaults (D1 A, D2 hidden no marker, D3 H2 here, D4 not needed).** User decision
2026-11-13: a member who is removed (or leaves) and is later added back
should see the group history from their earlier membership again ("Yes,
show it"). Found in the device check of the group-key restore build
(`group-key-restore.md`, item 6); not caused by that build. No live server
change and no server read are needed for this build.

## Why it is hidden (code read, 2026-11-13)

The chat screen hides every group row created before **my current member
row's** join time:

| Step | What happens | Where |
|---|---|---|
| Gate | A row older than `memberJoinedAt` is hidden, whatever its state. After that time, non-media rows show only when `decryptState` is `ready` or `device_sealed`; media rows always show. | `isGroupRowVisible`, `lib/core/utils/group_visibility.dart:24-41` |
| Join time | My local `conversation_members` row's `joinedAt`, cached per group. | `_groupCutoff`, `message_repository_impl.dart:1135-1148`, used by `_rowsToMessages` `:1150-1172` (the only caller) |
| Removal | The server row is **deleted** (`removeMemberFromGroup` `:3880-3890`; `leaveGroup` `:4155-4159` the same). The removed phone flips its local row to `left` and keeps the old join time (`:6455-6481`), so history stays visible while out. | |
| Re-add | Add from group info sends an invite; accepting **creates a new server row**, `joined_at` = autodate = now (`acceptGroupInvite` `:3706-3742`). The next sync upserts it under its new id and `removeStaleMemberRows` deletes the old local row (`:6397`, `:6126`). | |
| Result | Join time = re-add time, so every row from the first membership is "before you joined" and hidden. The rows are still on the phone and on the server. | |

Introduced in `dbdc2c0` (2026-10-04, invite rework). That spec already
logged it as out of scope ("Rejoin history loss",
`docs/superpowers/specs/2026-10-03-group-invites-rework-design.md:111-115`).

### What the keys already allow

- **First-membership keys survive removal.** Since `8d5d2f7` (2026-10-13)
  removal and leave keep the member's `group_keys` rows
  (`message_repository_impl.dart:3926-3929`), and rotation only adds a new
  version for current members (`_rotateGroupKeyNow` `:3948-4038`). The key
  walk lists every row wrapped for me (`encryption_service.dart:647-653`), so
  after a re-add a phone, including a fresh install, gets the first-stint
  versions back and opens those messages. The server has no history cutoff
  (`messages` list rule = current member; a server cutoff is not expressible
  on this PocketBase build, invite rework D1), so history sync already
  downloads them.
- **Nothing ever wraps a gap version for a re-joiner.** Rotate-on-join and
  the admin key-gap reconcile (`_reconcileGroupKeyGaps` `:4466-4519`,
  `key_gap.dart`) both call `_rotateGroupKey`: a **new** key, wrapped for the
  members of that moment. Versions created while the member was out are
  never wrapped for them. Messages sent while out land `key_missing` and
  never open.
- **A brand-new joiner holds no version from before their join.** Their
  first key is the rotation that follows their join; every earlier row is
  under an older version. So the keys, not the join time, are the real
  barrier, which is what the invite rework said too ("the crypto IS the
  barrier"). The join-time gate adds one thing: it hides pre-join **media**
  rows, which are otherwise exempt from the decrypt check.

So the earlier join time is **not needed**: "before my current join, show
only what my keys open" gives exactly the first membership, on this phone
and on a fresh install, and still nothing to a new joiner.

## Behaviour (what the user sees)

| # | Case | After this build |
|---|---|---|
| R-B1 | Removed, then added back (this phone) | Messages, photos and system lines from the first membership show again, in order. |
| R-B2 | Same, on a fresh install of the re-added account | Same as R-B1 once restore finishes; first-stint photos not on the phone download and open (H2). |
| R-B3 | Messages sent while the member was out | Not shown, no broken bubbles (texts, system lines, photos, voice all hidden). The "X was removed by Y" line shows, it was sent under the old key. |
| R-B4 | Left on their own, then re-invited | Same as R-B1 to R-B3. |
| R-B5 | New member, never in the group before | Unchanged: nothing from before their join, media included. |
| R-B6 | Removed before 2026-10-13 | First-stint keys were deleted then, so that history stays hidden (cannot be fixed without those keys). |
| R-B7 | Any member, group photo sent before the latest key change, not yet on the phone | Downloads and opens (H2; today it fails with a decrypt error). |

## Changes

### H1: before my current join, the keys decide (`group_visibility.dart`)

In `isGroupRowVisible`, a row created before `memberJoinedAt` is visible
only when `decryptState` is `ready` or `kDeviceSealedState`, **media
included** (the media exemption stays for rows after the join). Rows after
the join: unchanged. Update the doc comment to say why: a re-joiner's first
stint opens with keys they were given; a new joiner holds none from before.

Nothing else moves: `_groupCutoff`, the fail-closed "no member row → no
rows" (`:1157-1160`), member sync and the server stay as they are. No new
column, setting or request.

### H2: group media tries every key this account holds (D3)

Today the media download decrypts with the **newest** group key only
(`media_blob_store.dart:377-379`, `resolveKey` →
`_getConvKey` `message_repository_impl.dart:149` → `getOrFetchGroupKey`
`encryption_service.dart:370-381`, `requireCurrent: true`, first key). A
photo sent under an older version fails with `decrypt` on any phone that
has not cached it: every member after any key change, and every first-stint
photo for a re-joiner on a fresh install.

1. `MediaBlobStore.resolveKey` returns the candidate list:
   `(convId) async => _getConvKeyCandidates(convId, await _myId())`
   (`:6217-6235`, newest first; a DM returns its one key).
2. The decrypt step tries each key in order and stops at the first that
   opens; a wrong key costs one failed AES-GCM tag. Only when none opens:
   `_fail(..., 'decrypt')` as today.
3. Upload (send) is untouched: it still encrypts with the newest key.

## Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| D1 | Where the earlier-history boundary comes from | **A: nothing stored; before the current join, a row shows only if this account's keys open it (H1)** · B: also a time floor = the earliest of my `group_keys` rows' `created` (needs `created` in the walk, a stored value per group, invalidation; same result while the keys hold) · C: a server `first_joined_at` carried across removal (live schema + hook change, the invite rework's idea) |
| D2 | Messages sent while the member was out | **Hidden, no marker** (said after the member was removed; no key is ever wrapped for them) · a one-line divider "Messages from while you were out of the group aren't shown" · an admin re-wraps the gap versions for the re-joiner (reveals what was said after removal; not recommended) |
| D3 | First-stint photos not already on the phone (H2) | **Fix here: H2** (small, and the fresh-install device check needs it) · own spec later (re-joiners on a fresh install see photo bubbles that fail to open) |
| D4 | Confirm on the live server that a removed member's `group_keys` rows survive (no server hook deletes them)? | **Not needed**: device check item 5 proves it end to end · yes, a read-only check before the build (needs your yes for the live read) |

## Found while specifying (not built here)

- Removals and leaves before `8d5d2f7` (2026-10-13) deleted the member's
  key rows, so those first stints stay hidden even after this build (R-B6).
- Removal detection drops the newest key version from the removed phone
  (`clearCurrentGroupKey`, `encryption_service.dart:804-819`, called at
  `message_repository_impl.dart:6473`); after a re-add the key walk gets it
  back from the server. Device check item 3 covers it.

## Must not undo

- New joiners see nothing from before their join, media and system lines
  included (R-B5).
- Never render ciphertext: rows that do not open stay hidden on both sides
  of the join time.
- A group with no local member row shows nothing (`:1157-1160`).
- Own sent rows (`ready` default, `device_sealed`) stay visible.
- Send path still encrypts with the newest key and refuses a stale one
  (`requireCurrent`).
- Removal still rotates the key and keeps the removed member's key rows.

## Test gates

New:

1. `test/group_visibility_test.dart` (rewrite the "pre-join rows are hidden"
   case): before the join, `ready` text, `ready` system, `ready` image and
   `device_sealed` text → **visible**; `key_missing`, `pending`, `failed`
   text, system and image → **hidden**. After the join: unchanged, including
   `key_missing` image → visible.
2. Repo stream, re-add (char harness, `test/offline/char_harness.dart`,
   seed my member row with `joinedAt` = T2): rows at T0 `ready` text +
   `ready` image, T1 `key_missing` text + `key_missing` image + `key_missing`
   system, T3 `ready` text → `watchMessages` yields **T0 text, T0 image, T3**,
   in order.
3. Repo stream, new joiner (must not undo): rows before `joinedAt`, all
   `key_missing` or `pending` (text, image, voice, system) → none yielded;
   rows after the join behave as today.
4. H2 (`test/offline/media_blob_store_test.dart`): a blob encrypted with
   the older of two candidate keys → opens and lands ready; encrypted with
   neither → `decrypt` failure as today; encrypted with the newest → opens
   with one decrypt attempt.

Existing, must stay green: `test/offline/removal_reconcile_char_test.dart`,
`test/offline/group_key_local_first_test.dart`,
`test/offline/idempotent_ingest_test.dart`,
`test/offline/always_commit_test.dart`,
`test/offline/send_fetch_char_test.dart`, the media blob and media send
tests. Full `flutter test` green against the baseline taken at build start;
`flutter analyze` 0 errors.

## Device check list (you do every sign-in)

Test accounts only. M52 (adb `RFCRA047WSJ`) is the admin, Redmi (adb
`c7e9f10e`) the member who is removed. Make a **new** test group for this,
so its history is after 2026-10-13.

1. M52 creates group "Rejoin test" with the Redmi. Both phones send 2 texts;
   M52 sends 1 photo, Redmi 1 voice note. Both read everything.
2. M52 removes the Redmi. Redmi: old messages still visible, "removed" line
   shows, composer locked.
3. While the Redmi is out, M52 sends 2 texts and 1 photo. Then M52 adds the
   Redmi back and the Redmi accepts. Redmi: every message, the photo and the
   voice note from step 1 show again, in order, and open; "Redmi was removed
   by M52" shows; **none** of the step 3 messages show and there is no
   broken or locked bubble in their place.
4. Both phones send a new message; the other reads it.
5. Redmi: clear app data, sign in, restore. Open "Rejoin test": same as
   step 3; the step 1 photo downloads and opens (H2).
6. New-joiner guard: M52 creates group "Guard test" alone (or with another
   test account), sends 3 texts and 1 photo, then adds the Redmi. Redmi
   accepts: **nothing** from before the join shows, no photo bubble.
7. Redmi leaves "Rejoin test" on its own; M52 re-invites; Redmi accepts:
   same as step 3.
8. Any older test group with a photo from before the last member change,
   on the freshly restored Redmi: the photo opens (R-B7).

## Out of scope

Gap-period messages for re-joiners (D2 default), a server
`first_joined_at` column, any live server read or change, history lost to
pre-2026-10-13 removals, other screens' history rules (search, starred,
media gallery) which do not use the join time today.
