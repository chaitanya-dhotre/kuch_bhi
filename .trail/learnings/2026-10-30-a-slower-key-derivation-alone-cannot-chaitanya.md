---
title: "A slower key derivation alone cannot save a 6-digit backup PIN, and pure-Dart Argon2id is fast enough on the phone that no new package is needed"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 14, tokens: 254049 }
id: l-db707807
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/key-backup.md
  - docs/design/pages/key-backup.html
  - lib/services/encryption_service.dart
  - lib/features/auth/screens/backup_pin_screen.dart
---

## Decided
- (Proposed in the key-backup spec, awaiting the user's PASS.) The backup secret must get longer (a passphrase of 10+ characters). Argon2id only makes each guess costly: a 6-digit PIN goes from ~10-20 s on one GPU (PBKDF2 at 100k) to roughly minutes, which is still broken.
- Argon2id comes from the `cryptography` package the app already ships (`DartArgon2id`, pure Dart, spawns its own isolates for parallelism > 1). No native library is needed.

## Tried and ruled out
- Raising PBKDF2 to OWASP's 600k rounds: 2.27 s on the dev box, so about 30-60 s on a Redmi S2. Too slow to be the fix.

## Watch out
- Change PIN "verifies" the old PIN by running a full restore. That writes the backup's key over the device key, re-publishes the public key and wipes every cached conversation and group key. Never use restore as a check.
- Restore returns the same `false` for "no backup" and "wrong PIN".
- The project bible lists the users view rule as "any signed-in user", and the app fetches other users' records with no field filter. If that's still true on the live server, every user's backup blob is downloadable by any account. Not verified live as of 2026-10-30.
- Phone/desktop ratio for this pure-Dart crypto is about 13-27x (derived from the code's own "5-10 s" note for PBKDF2-100k). Memory-hard Argon2 may scale worse, so measure it on the device.

In the code:
- lib/services/encryption_service.dart `_isoPbkdf2`, `backupPrivateKey`, `restorePrivateKey`
- lib/features/auth/screens/backup_pin_screen.dart change branch of `_submit`
- Dev box (Ryzen 7 7840HS, AOT, cryptography 2.9.0): PBKDF2-100k 375 ms; Argon2id 64MiB t3 p4 178 ms, p1 445 ms; 32MiB t3 p4 79 ms; PBKDF2-600k 2273 ms
- Spec: docs/design/pages/key-backup.{md,html}
