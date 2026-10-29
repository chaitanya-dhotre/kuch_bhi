---
title: Decrypting reads the device key only; switching first-time key setup to the three-way backup check needs the router and PIN setup changed with it
author: Chaitanya
date: 2026-10-29
branch: claude/peaceful-roentgen-8e43f5
cost: { minutes: 1, tokens: 2606 }
id: l-1ade2688
scope: repo
status: active
src: agent
touches:
  - lib/services/encryption_service.dart
  - test/offline/encryption_sync_offline_test.dart
---

## Decided
- Key derivation (every DM decrypt, group-key wrap and unwrap) reads the stored key pair and throws "missing key" when there is none. Only first-time key init (through the public-key getter) and the PIN setup, start-fresh and restore flows write a key pair. This is why sign-in on a fresh install now reaches the Backup PIN restore.
- When only the private key is stored (a crash between restore's two writes), the reader rebuilds the public half from the private seed and writes nothing. A read-only reader without this leaves the user on Home with nothing decrypting and no prompt.

## Tried and ruled out
- Switching only first-time key init to the three-way backup check, so "unknown" skips generation. A brand-new account on a network blip then has no key: the router's no-local-key branch treats "unknown" as "no backup" and sends the user to PIN setup, and setup only backs up an existing key, so it errors until a resume or cold start re-runs key init. The three-way switch must change key init, the router's no-local-key branch and PIN setup with no key together.

## Watch out
- Every derivation caller handles "missing key" (the same exception covers a missing peer key), so they fail closed. Create group rolls back; rotation encrypts for every member before its first write. Removing someone from a group, or leaving, on a device with no key removes the member but skips the key rotation.
- `tryHasPocketBaseBackup` returns "unknown" on ANY error, a 403 included. Anything that blocks generation on "unknown" blocks it for good if the error is permanent.

In the code:
- lib/services/encryption_service.dart: `_readKeyPair` (read-only; rebuilds pub from seed), `getOrDeriveConversationKey` throws `MissingKeyException`
- test/offline/encryption_sync_offline_test.dart: the two K1 tests
- Three-way switch sites: auth_repository_impl.dart `_initEncryptionKeys`, encryption_sync_provider.dart no-local branch, backup_pin_screen.dart setup branch (`backupPrivateKey`)
