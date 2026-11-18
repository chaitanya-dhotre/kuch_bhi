# Key-change warning (audit F3) — work log

Spec: `key-change-warning.md` (PASS 2026-11-17, all defaults). Built 2026-11-17 by Claude in the
spec session, on `main` (uncommitted; other sessions' uncommitted edits share
`message_repository_impl.dart`, `auth_repository_impl.dart`).

## What was built (by checklist id)

| Id | Where |
|---|---|
| A1, F1 | `lib/data/local/database/contact_key_store.dart` (`contact_keys`, raw SQL), schema 14 → 15 in `app_database.dart` (`from < 15`: create + `seedFromUsers`) |
| A2, A3 | `UsersDao.upsertUser` / `upsertUsers` → `ContactKeyStore.observe` (the one funnel) |
| A4, D6 | `_notifyKeyChanges` / `_emitKeyChangeLine` in the repo; lines are `sys_kc_<userId>_<uuid>` |
| A5, A6 | `acceptContactKey` (store accept → decrypt re-run per shared chat → `retryPendingMessages` → catch-up wrap per group where I am admin, inside `_rotations`) |
| A7 | derived-key wipe removed from `_getConvKey` |
| B1, B2 | `_getConvKey` reads the pin; pending → `KeyChangedException` (a `MissingKeyException`, so sends hold) |
| B3 | `DecryptPass._resolveKeys` (DM) and `_dmKeyCandidates`: pin + history only |
| B4 | `canSendIn(keyChanged:)`, `KeyChangeCard` in the composer slot (cross-fade, D8) |
| B5 | the drain decrypts a sealed row with every accepted key, then re-seals with the current one |
| C1 | `_wrapKeyFor` (rotation) and `create_group_screen.dart`: my local key for me, the pin for others, pending = skipped |
| C2 | `_walkGroupKeys` groups by wrapper id and opens only with `acceptedWrapperKeys` (provider-wired to `keysForWrapper`) |
| C3 | chat-screen banner (R12a) for "I am admin, a member is pending" and "the admin's key is pending and blocks me"; restriction line copy |
| D1–D5, D7 | `security_code.dart`, `security_code_screen.dart`, chat ⋮ row, View profile row |
| E1 | sign-in sets `own_key_mismatch` instead of deleting; `EncryptionSyncStatus.ownKeyChanged` → `/own-key-changed` (`own_key_changed_screen.dart`) |
| G1 | Start fresh dialog sentence |

## Deviations from the spec (each smaller or required by the codebase)

1. **`contact_keys` is a raw-SQL table** with a hand-written store, not a generated drift table:
   drift_dev cannot run on this toolchain (requests / media-send work logs). Not in `allTables`, so
   sign-out clears it explicitly.
2. **Line text is rebuilt, not stored.** Local system lines keep their body only in the session
   cache, which is wiped on backgrounding. A key-change line carries the contact id in its local
   id; `DecryptPass.runFor` rebuilds "{name}'s security code changed. Tap to compare." from the
   stored name. No new plaintext at rest.
3. **E1 runs where the old delete ran (sign-in key init) only.** A cold start never compared the
   keys before either; adding a startup server read was not in the spec.
4. Test seam `debugRotateGroupKey` added for the C1 test.

## Gates

- New tests: `test/security/key_change_warning_test.dart` (16), `test/security/key_change_ui_test.dart`
  (9), View profile row test (+1).
- Schema pins bumped 14 → 15: `album_send_test`, `media_blob_meta_test`, `sealed_preview_test`,
  `placeholder_ui_test`.
- Existing tests updated: `group_key_restore_test` G5 (`fields` now carries the wrapper id);
  `view_profile_screen_test` host gets a `ProviderScope`. The E1 actions live in
  `lib/features/security/own_key_actions.dart` because the Page 7 grep gate bans
  secure-storage imports in `lib/features/auth`.
- Full suite **1455/1455** (baseline 1419 before; one known timing flake,
  `server_created_watermark_test` C1a, failed once under load and passes alone and on rerun).
- `flutter analyze`: 0 errors.
- `trail check`: 3 keyword hits, none real (two on new pin code that is neither a conversation
  re-check nor a dead-version list, one on another session's code).

## Device run 2026-11-18 (M52 = Chait galx, admin of "Test"; Redmi = Avium)

- Check 6 PASS: the first Redmi reinstall restored with the recovery key; the M52 showed nothing.
- Check 1 PASS: upgrade over both installs, no lines, chats read.
- Check 2 PASS: after a real Start fresh, the Redmi's message reached the M52 as "peer security
  code changed, waiting for accept"; the DM showed the line, the change card instead of the
  composer, and the message locked. The M52 learns of a change only on a send or a receive from
  that friend (by design, B1); a pull-to-refresh does not re-read keys.
- Check 3 PASS: both phones showed the same 60 digits. QR scan not tried (needs a person to aim).
- Check 4 PASS: the R20 confirm showed (Avium was marked verified on the M52).
- Group, admin side: line + banner "They can't read new messages here until you check it" PASS.
- Check 5 FAIL → fixed: Accept wrote no catch-up row (Avium already had an old-key row at the
  current version). A6 now rotates instead (`acceptContactKey` → `_rotateGroupKey`); new test
  "admin Accept rotates the shared group". Rebuilt and installed on both phones; re-run pending.
- Round 3 (second real Start fresh, rotation build): the M52 SENT first → the message held as
  pending ("peer security code changed, waiting for accept"), card shown. Accept from the "Test"
  banner rotated every shared admin group (3 at first, 5 in all); the Redmi then read
  "F3 group after accept" and could send. The held DM went out after Accept (delivered). No R20
  this time (Avium not verified), as expected. **Check 5 PASS.**
- Accept waited for all rotations (~15 s, sequential, 2–4 s each) before the screen closed.
  Fixed: rotations run in the background (`_rotateAfterAccept`, test seam `acceptRotations`).
  Full suite 1459/1459; final build installed on both phones.
- Round 4 (user go-ahead): Avium's old key put back on the live server from
  `data.db.20261117-wave2-pre` (public_key, private_key_encrypted, private_key_salt only; live
  saved first to `/home/ubuntu/pb_backups/data.db.20261118-avium-key-revert-pre`). Redmi signed
  out and back in: **check 7 PASS**: "Server key differs from this phone — asking" →
  /own-key-changed → Restore → the original recovery key restored the old key; old messages and
  group keys open again. The M52 then saw Avium change back; Accept closed at once and rotated
  12 shared groups in the background; the Redmi reads "Test" again.
- Note: a message under a key that is in the contact's HISTORY (a change back to an earlier
  accepted key) opens while pending, because DM candidates include history keys. Only a key the
  phone had already accepted can open it, so it is not a server-swap hole.
- **Check 8 (dark) PASS** on the M52 (card, lines, code screen, QR on white). Found: digits
  wrapped 7 + 5 on the M52's width; fixed to 3 rows of 4 (fewer per row only when 4 don't fit).
  200 % text not run on a phone (widget test covers the card at 200 % on 360 dp).
- A11y nit seen: the line's row read "From You. … Tap to compare.. Time …" (the bubble row's own
  label wrapped ours). Fixed with `excludeSemantics` on the line's button node (not re-checked on a
  phone).

## Not covered by tests (device check §8)

Catch-up wrap end to end, the line appearing in every shared chat, scan with a real camera, the
own-key screen's Keep against the live server.
