# Production Readiness Changes — 2026-10-13

## Summary

Today’s work focused on a production failure in encrypted group history.
After a group-key rotation, a member whose app was stopped or whose local
cache was cleared could see only messages sent after the rotation. Older
messages appeared missing or reported that the group key was unavailable.

## Root Cause

The failure had multiple layers:

1. Group rotation deleted older `group_keys` records.
2. Secure storage kept only one unversioned key per conversation.
3. Cold message fetch decrypted a complete page with only the newest key.
4. Messages encrypted with older keys became `pending`.
5. Group visibility hid `pending` text rows before lazy decryption could retry.
6. Ingest did not consistently store the key fingerprint in `key_id`.

Result: historical ciphertext could no longer be decrypted after a cold start,
even when the member was entitled to the historical messages.

## Code Changes

### `lib/services/encryption_service.dart`

- Added version-aware group-key candidate retrieval.
- Fetches retained key rows for the current member, newest first.
- Decrypts and deduplicates all usable key versions.
- Stores versioned cache entries using:
  - `group_key_<conversationId>_<version>`
- Preserves the legacy active-key slot:
  - `group_key_<conversationId>`
- Uses a valid local cached key without issuing a network request when the
  caller has no resolved user ID, supporting offline/test paths.

### `lib/core/decrypt/decrypt_pass.dart`

- Group lazy decryption now receives all available key candidates.
- Each ciphertext is attempted against each retained key.
- Successful decryption records the fingerprint of the matching key.
- Rotation-related misses remain retryable instead of becoming terminal
  failures when multiple key candidates exist.

### `lib/infrastructure/repositories/message_repository_impl.dart`

- Group rotation no longer deletes older key versions.
- Removed-member historical key rows are retained so the member can still
  decrypt messages sent while they were entitled to group access.
- New key versions are still distributed only to current members, preventing
  removed members from decrypting future messages.
- Cold message fetch now loads all retained group-key candidates.
- Each fetched message is decrypted against the candidate keys until a match
  is found.
- Matching `key_id` fingerprints are persisted during ingest.
- The undecrypted-row repair pass now tries all retained group keys.
- Missing keys still commit ciphertext as `key_missing` instead of dropping
  the message.

### `pubspec.yaml`

- Removed asset declarations for directories that do not exist:
  - `assets/images/`
  - `assets/animations/`
- Kept the valid `assets/icons/` declaration.

Reason: Flutter builds emitted invalid asset-directory errors even though the
application did not use those directories.

## Toolchain and Device Validation

- Used the project directory:
  - `~/kuch_bhi`
- Used the available Flutter SDK:
  - `/home/chaitanyadhotre/flutter`
- Used the user package cache:
  - `/home/chaitanyadhotre/.pub-cache`
- Re-ran dependency resolution successfully.
- Installed the required SQLite development library in the test container so
  Drift tests could load SQLite.
- Built the Android debug APK successfully.
- Installed the APK on Android emulator `emulator-5554`.
- Package:
  - `com.chai.kuch_bhi`
- App reached the login screen on the emulator.

## Verification

Focused tests passed:

```text
flutter test \
  test/offline/decrypt_pass_test.dart \
  test/offline/send_fetch_char_test.dart \
  test/offline/always_commit_test.dart \
  test/key_gap_test.dart
```

Additional isolated tests passed:

```text
flutter test \
  test/offline/send_fetch_char_test.dart \
  test/offline/read_paths_char_test.dart
```

Build/install verification:

```text
flutter build apk --debug
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
```

`flutter analyze` reported no compile errors. Existing warnings and infos
remain in unrelated areas.

## Live Test Result Before the Final Fix

The first live scenario reproduced the failure:

1. Device A created a group with Device B.
2. Messages were exchanged.
3. Device C was added, causing rotation.
4. Device B was stopped and its cache was cleared.
5. Device C sent new messages.
6. Device B reopened the group.

Observed result: Device B saw only post-rotation messages.

This reproduction exposed the cold-fetch bug described above. The final fix
was applied after this result and installed on the emulator. The same live
scenario must be repeated on the real devices to confirm the production path.

## Remaining Risks

1. Keys deleted by older production code cannot be recovered from the current
   database. Existing broken groups may require a migration or key recovery
   strategy.
2. PocketBase must retain historical `group_keys` rows and allow the current
   member to read its own historical rows.
3. Members without a public key are still silently skipped during key
   distribution. This remains a production-hardening task.
4. Startup shows substantial frame skips on the emulator.
5. `FcmDebugHelper` creates a second `AppDatabase`, causing a Drift warning.
6. Gradle, AGP, and Kotlin versions produce future-compatibility warnings.

## Required Retest

Repeat on Device B:

1. Stop the app.
2. Clear app data/cache.
3. Reopen the app and enter the existing group.
4. Verify messages from before Device C joined are visible.
5. Verify messages sent after Device C joined are visible.
6. Check that no old message shows `group key missing`.

If the failure remains, inspect live PocketBase rows for the group:

```text
group_keys:
  conversation_id
  user_id
  key_version
  encrypted_by_user_id
```

Device B must have both the pre-rotation and post-rotation key versions.
