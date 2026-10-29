---
title: Restore is skipped when message sync creates a key pair before the restore check runs
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 9, tokens: 112835 }
id: l-5cca8748
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/auth.md
---

## Decided
- Code that decrypts must only read the device key pair. Missing key = "key missing", never a new key. Only first-time setup (initial key generation, Backup PIN setup) may create one.
- The restore wait (1-3 min history sync with real chat/message counts) is where the "something to do" picks go: theme + notification status rows, both offline-safe and key-free. Font options were declined: one system font and one type scale by design law, and Android's text size is already honoured.

## Tried and ruled out
- Blaming Google sign-in alone: email/password sign-in takes the same path, because both save the server token before key setup runs.

## Watch out
- Sign-in saves the token first. The message layer reacts to the new identity at once, starts syncing and repairing, and the decrypt pass calls the "get or create" key method. On a fresh install that silently makes a NEW key pair. The router then sees "local key + server backup" and goes to Home: no restore, the new key is never uploaded, nothing decrypts until the PIN is entered from Profile.
- The backup check used during first key setup returns "no backup" on any network error, so a blip can generate and upload a new public key over the backed-up one. Use the tri-state check (unknown ≠ no backup).
- The Google sign-in server hook decodes the token without verifying its signature (only expiry and audience); any crafted token for an email signs in as that account. It also saves the original username instead of its computed free one, so a taken name answers 500.
- Live server facts: password auth accepts email OR username; username min 3 with no max or pattern on the server; SMTP is on.

In the code:
- Listener: message_repository_impl.dart authStore.onChange → _reconnect → sync/repair → decrypt_pass.dart _resolveKeys → encryption_service.dart getOrCreateKeyPair.
- Router check: encryption_sync_provider.dart (hasLocalPrivateKey → tryHasPocketBaseBackup → keyOk).
- First-time setup: auth_repository_impl.dart _initEncryptionKeys (uses hasPocketBaseBackup, catch-all false).
- Server hook: /opt/pocketbase/pb_hooks/google_auth.pb.js.
- Spec: docs/design/pages/auth.md sections J and K.
