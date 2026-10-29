---
title: "A backup check the server did not answer must never lead to a new key, except for an account created moments ago; the route re-checks when the network returns"
author: Chaitanya
date: 2026-10-29
branch: claude/peaceful-nightingale-f2f875
cost: { minutes: 9, tokens: 46830 }
id: l-cfb3013b
scope: repo
status: active
replaces: l-81a4f5d8
src: agent
touches:
  - test/offline/encryption_sync_offline_test.dart
  - lib/features/auth/providers/encryption_sync_provider.dart
  - lib/infrastructure/repositories/auth_repository_impl.dart
  - lib/services/encryption_service.dart
---

## Decided
- Sign-in key setup makes a key only when the server confirms no backup. On a blip it makes nothing, so it never uploads a new public key over a backed-up one.
- Right after register or Google sign-up, an unanswered check means "no backup" (the account was just created). A backup the server DOES report still wins.
- No key on the device: the route re-checks 5 times on the splash. Then: backup → Restore, none → PIN setup, never answered → Restore.
- Key on the device, server unreachable: Home (an offline cold start must not ask a set-up user to set up). When the network comes back, the route checks again and re-routes ONLY if setup is now due (a new account registered offline).
- Start Fresh uploads the public key before saving it, so an offline attempt leaves nothing behind.

## Tried and ruled out
- Switching only sign-in key setup: a keyless new account on a blip gets stuck on PIN setup.
- Treating every unknown as Restore: a just-registered account on a blip landed on Restore (device run 2).
- Re-running the route on every reconnect: a loading route sends the user to the splash, which bounces a set-up user out of an open chat.

## Watch out
- The three-way check says "unknown" for ANY error, a 403 included.
- Device runs must use an APK built from the worktree under test, on a fresh install (run 1 used main's build).

In the code:
- lib/infrastructure/repositories/auth_repository_impl.dart `_initEncryptionKeys(newAccount)`, from register / registerWithGoogle via `_saveSession`
- lib/features/auth/providers/encryption_sync_provider.dart no-local branch, `setupDue`, `_recheckOnReconnect`, `backupCheckRetryDelay`
- lib/services/encryption_service.dart `backupOrCreateKey`, `generateAndBackupNewKey`, `restorePrivateKey`
- test/offline/encryption_sync_offline_test.dart K3 tests
