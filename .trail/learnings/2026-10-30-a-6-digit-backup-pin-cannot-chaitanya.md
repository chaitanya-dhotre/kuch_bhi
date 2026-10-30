---
title: "A 6-digit backup PIN cannot be saved by a slower key derivation or by rate limits, because anyone signed in can download the encrypted key and guess offline"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 1, tokens: 0 }
id: l-584bb4d0
scope: repo
status: active
replaces: l-db707807
src: agent
touches:
  - lib/services/encryption_service.dart
  - lib/features/auth/screens/backup_pin_screen.dart
---

## Decided
(Proposed in the key-backup spec, awaiting the user's PASS.) The backup secret must get longer (passphrase or a generated recovery key), the derivation moves to Argon2id from the crypto package the app already ships, and the backup fields must be hidden from everyone but their owner. WhatsApp and Signal can use short PINs only because tamper-resistant hardware (HSMs / SGX enclaves) counts wrong guesses and never hands out the encrypted key; PocketBase can't do that, so the secret itself has to carry the strength.

## Tried and ruled out
- Raising PBKDF2 to OWASP's 600k rounds: 21.3 s on the Redmi S2 (release build). Not usable.
- Leaning on PocketBase rate limiting: one list request returns every user's blob and guessing then happens offline, so no server limit applies.
- Native libsodium for Argon2: not needed. Pure-Dart Argon2id 64 MiB / t3 / p4 takes 1.83 s on the Redmi S2 and 0.45 s on the Galaxy M52 (release build, background isolate), half of PBKDF2-100k on the same phones (3.55 s / 0.71 s).

## Watch out
- Live check 2026-10-30: users list and view rules were both "signed in" and the backup fields were not hidden, so any account could harvest all backups. Anyone who copied a blob keeps a PIN-crackable copy even after a re-wrap; only a new key pair fixes that.
- Change PIN "verifies" the old PIN by running a full restore, which writes the backup's key over the device key and wipes key caches.
- Restore returns false for both "no backup" and "wrong PIN"; the UI can't tell them apart.

In the code: lib/services/encryption_service.dart backupPrivateKey / restorePrivateKey / _isoPbkdf2; lib/features/auth/screens/backup_pin_screen.dart; live rules via sqlite3 -readonly on /opt/pocketbase/pb_data/data.db (_collections, _params.settings rateLimits). Spec: docs/design/pages/key-backup.{md,html} S10 (hide hook), S11 (timings).
