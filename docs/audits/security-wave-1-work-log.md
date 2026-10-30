# Security wave 1 — work log

Source: `docs/audits/2026-10-30-security.md` (static audit by Mimo, nothing
executed). Claude end to end (E2E-adjacent). Baseline 650/650 on `86d72fc`.
Status: **user device PASS 2026-10-30; committed. Live PB cleanup still pending the user's OK.**

## Findings confirmed in code before fixing

| § | Finding | Confirmed at |
|---|---|---|
| 8.1 | `toggleStar` uploads the decrypted body as `starred_messages.message_preview`; starred screen reads it back | `message_repository_impl.dart:2283`, `:2641` (HEAD) |
| 3.1 | full FCM token + user id logged at every start, ungated | `main.dart:66` → `fcm_debug_helper.dart:19` |
| 3.2 | full FCM token logged on every refresh | `fcm_service.dart:111` |
| 4.2 | no `allowBackup` / backup rules anywhere in `android/` | `AndroidManifest.xml` |
| 2.1 | `google-services (2..4).json` show as `??`, not ignored | `git status` |

## What changed

1. **§8.1 starred plaintext.** `toggleStar` sends ids only (`user_id`,
   `message_id`, `conversation_id`, `sender_id`). `getStarredMessages`
   ignores `message_preview`: type, body, `decryptState` and
   `ciphertextLength` come from the local row; body from `bodyCache`; the
   message's real `localId` is returned so the card can resolve the body on
   device. Not local → null body → keyed placeholder. The starred card renders
   text through `MessageBodyText` (same renderer and placeholder as the pinned
   banner); the old `'🔒 Encrypted'` fallback is gone.
   - **Small addition:** on a PocketBase error (offline) the list now falls
     back to the local `is_starred` rows, newest first, instead of showing
     "No starred messages". Needed for the offline device check.
2. **§3.1/3.2 FCM logs.** `FcmDebugHelper` deleted (its only job was the
   log line; it also opened a second `AppDatabase` on every launch). The
   refresh log prints `[FCM] Token refreshed.` without the token.
3. **§4.2 backup.** `android:allowBackup="false"` plus
   `android:dataExtractionRules="@xml/data_extraction_rules"` excluding
   root/file/database/sharedpref/external and the four `device_*` domains for both `cloud-backup` and
   `device-transfer`. On targetSdk ≥ 31, `allowBackup="false"` alone does
   NOT stop device-to-device transfer; the rules file is what does. No
   `fullBackupContent`: with `allowBackup="false"` Android ≤ 11 backs up
   nothing, so the file would be dead config.
4. **§2.1 gitignore.** `/android/app/google-services (*).json`. The tracked
   `google-services.json` is not matched. Nothing deleted.

## Decision: §4.1 (JWT copy in Drift) deferred

With backup and D2D transfer off, the plaintext JWT in the Drift settings
table is no longer copied off the device by Android. What's left is local
access (rooted device / forensic image), which also reaches the secure-storage
copy's process. Removing the Drift fallback touches the FCM background
isolates' auth path and needs its own device test, so it waits for its own
spec. Not fixed in this wave.

## Tests (+7, all RED on HEAD, GREEN after)

`test/offline/starred_no_plaintext_test.dart` (real repo, MockClient):
1. toggleStar's PB create has no `message_preview` key and no plaintext.
2. getStarredMessages: local body from bodyCache with the local id; not-local
   → null body; the server's preview never surfaces.
3. getStarredMessages offline → the local starred rows.

`test/grep_gates_test.dart`, inside `main()`:
4. §8.1: no `'message_preview'` literal in the repo; starred screen uses
   `MessageBodyText(`, no `🔒 Encrypted`.
5. §3: helper file gone; no `FcmDebugHelper`; no token interpolated into a
   `debugPrint` in `main.dart` / `fcm_service.dart`.
6. §4.2: manifest flags + every domain excluded in both rule sections.
7. §2.1: `git check-ignore` matches `(2)` and `(9)`, not the real file.

## Gates

- `flutter test`: **657/657** (650 + 7); no existing test edited.
- `flutter analyze`: 0 errors (83 info/warning, all pre-existing).
- `git diff --check`: clean.
- `trail check`: 0 conflicts (20 "worth a look" notes, all on earlier pages' docs).
- `flutter build apk --debug`: builds; merged manifest has `allowBackup="false"` + `dataExtractionRules`, the rules XML is packaged.
- Frozen-code function-level diff vs HEAD: `message_repository_impl.dart` →
  only `toggleStar`, `getStarredMessages`; `fcm_service.dart` → `init` (the
  one log line); `encryption_service.dart`, `lib/core/decrypt/`,
  `lib/infrastructure/media/`, `auth_repository_impl.dart` byte-identical.

## Live PocketBase cleanup (NOT done; needs the user's OK)

Existing `starred_messages` rows still hold plaintext previews. Do it only
after BOTH phones run this build, because an old build uploads a preview on
every star. See the session report for the exact command.

## Follow-ups (not in this wave)

- Stars made offline never reach PB (toggleStar's PB call isn't in the
  outbox and isn't retried). Unstar on another device isn't synced down
  (`_syncStarredMessages*` only sets true).
- Other user-id logs, out of scope (two are in frozen key code):
  `auth_repository_impl.dart:613`, `encryption_service.dart:870`,
  `message_repository_impl.dart` full-sync start.
- Starred screen error branch shows `Text('Error: $e')` (pre-existing;
  unreachable today since the repo catches everything).
- `KUCH_BHI_PROJECT_BIBLE.md:1044` still documents `message_preview` as
  the design.
- Drop the `message_preview` field from the live schema (migration) once the
  cleanup is done.

## Review (independent, fresh context): PASS-with-notes, no BLOCK

The reviewer confirmed: no other code path sends or reads the preview; the jump
flow now gets the real `localId` (`_findFlatIndex`, `_flashMessage`), which is
an improvement; an unknown id in `MessageBodyText` resolves to the placeholder
without throwing or looping; the offline fallback can't throw to the screen;
the rules XML is valid; each of the 3 repo tests is RED on HEAD.

Fixed after review:
- SHOULD: the gitignore gate's tracked-file check proved nothing (git
  skips tracked files) → now `--no-index`.
- NIT: voice duration and document name were lost after a cold start
  (`bodyCache` only) → the card now reads `messageBodyProvider(msg.localId)`,
  which decrypts on device. Gate extended.
- NIT: the offline fallback awaited `_myId()` (can poll 10s), but
  `_rowToMessage` never reads it → `''`.
- NIT: added the `device_*` domains to both rule sections. Gate extended,
  went RED first.

Left as they are:
- SHOULD: the XML file is untracked → it goes in the same commit as the
  manifest (a manifest without it fails aapt).
- SHOULD: old plaintext still on live PB → user-approved cleanup, see above.
- NIT: a message that isn't local shows the neutral placeholder
  indefinitely. The brief asked for the keyed placeholder, and tapping the
  card jumps to the message and fetches it.
- NIT: the offline fallback lists deleted-for-me rows. The online path does
  the same; that belongs to the bug audit.
- NIT: `auth_repository_impl.dart` still logs the user id. The file stays
  byte-identical this wave; listed in follow-ups.
