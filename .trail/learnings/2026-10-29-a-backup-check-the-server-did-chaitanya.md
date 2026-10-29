---
title: "A backup check the server did not answer must never lead to a new key; key setup, the no-key route and PIN setup all treat it as unknown"
author: Chaitanya
date: 2026-10-29
branch: claude/peaceful-nightingale-f2f875
cost: { minutes: 14, tokens: 177298 }
id: l-4235ec43
scope: repo
status: active
src: agent
touches:
  - test/offline/encryption_sync_offline_test.dart
  - lib/infrastructure/repositories/auth_repository_impl.dart
  - lib/services/encryption_service.dart
  - lib/features/auth/providers/encryption_sync_provider.dart
  - test/offline/char_harness.dart
  - lib/features/auth/screens/backup_pin_screen.dart
  - docs/design/pages/auth-k3-work-log.md
---

## Decided
- First-time key setup makes a key only when the server CONFIRMS there is no backup. On a blip it makes nothing, so it can never upload a new public key over a backed-up one.
- With no key on the device, the route re-checks a few times while the splash shows. Confirmed backup → Restore; confirmed none → PIN setup; never answered → Restore. Restore writes nothing unless the user picks Start Fresh, which is also a keyless new account's way out.
- PIN setup with no key makes one only on a confirmed "no backup"; unknown shows "Can't reach the server".
- Start Fresh uploads the public key before saving it on the device, so an offline attempt leaves nothing behind.

## Tried and ruled out
- Switching only key setup to the three-way check: a new account on a blip gets no key, the route sends it to setup, and setup throws "No local private key".
- Routing "unknown" to PIN setup: an existing user then sets a new PIN over the real backup's account state. Unknown is not "no".

## Watch out
- The three-way check returns unknown on ANY error, a 403 included, so a permanent error keeps the user on the Restore fallback. That is safe (nothing is overwritten), not friendly.
- Restore used to report every failure as "Incorrect PIN". A failed record read now throws, so offline it shows an error instead.

In the code:
- lib/infrastructure/repositories/auth_repository_impl.dart `_initEncryptionKeys` (tryHasPocketBaseBackup, generate only on false)
- lib/features/auth/providers/encryption_sync_provider.dart no-local branch, `backupCheckRetryDelay` (5 tries)
- lib/services/encryption_service.dart `backupOrCreateKey`, `generateAndBackupNewKey` (upload first), `restorePrivateKey` (read outside the try); catch-all `hasPocketBaseBackup` deleted
- test/offline/encryption_sync_offline_test.dart: the K3 tests and P6.3
