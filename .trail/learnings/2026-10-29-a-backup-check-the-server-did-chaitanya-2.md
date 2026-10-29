---
title: "A backup check the server did not answer must never lead to a new key, except for an account created moments ago"
author: Chaitanya
date: 2026-10-29
branch: claude/peaceful-nightingale-f2f875
cost: { minutes: 22, tokens: 224395 }
id: l-81a4f5d8
scope: repo
status: active
replaces: l-4235ec43
src: agent
touches:
  - docs/design/pages/auth-k3-work-log.md
  - ".handoffs/2026-10-29T1830-auto-pause-33c7d6.md"
  - lib/infrastructure/repositories/auth_repository_impl.dart
  - test/offline/encryption_sync_offline_test.dart
  - lib/features/auth/providers/encryption_sync_provider.dart
  - lib/services/encryption_service.dart
---

## Decided
- Sign-in key setup makes a key only when the server confirms there is no backup. On a blip it makes nothing, so it can never upload a new public key over a backed-up one.
- Exception: right after register or Google sign-up, an unanswered check means "no backup" (the account was just created). A backup the server DOES report still wins.
- With no key on the device, the route re-checks 5 times on the splash. Then it goes to Restore if a backup exists, PIN setup if none, and Restore if the server never answers. PIN setup with no key creates one only when the server confirms no backup.
- Start Fresh uploads the public key before saving it, so an offline attempt leaves nothing behind.

## Tried and ruled out
- Switching only sign-in key setup: a keyless new account on a blip gets stuck on PIN setup.
- Treating every unknown as Restore: a just-registered account on a blip landed on Restore (device run 2).

## Watch out
- The three-way check says "unknown" for ANY error, a 403 included.
- Device runs must use an APK built from the worktree under test, on a fresh install (run 1 used main's build).

In the code:
- lib/infrastructure/repositories/auth_repository_impl.dart `_initEncryptionKeys(newAccount)`, passed from register / registerWithGoogle via `_saveSession`
- lib/features/auth/providers/encryption_sync_provider.dart no-local branch, `backupCheckRetryDelay`
- lib/services/encryption_service.dart `backupOrCreateKey`, `generateAndBackupNewKey`, `restorePrivateKey`
- test/offline/encryption_sync_offline_test.dart K3 tests
