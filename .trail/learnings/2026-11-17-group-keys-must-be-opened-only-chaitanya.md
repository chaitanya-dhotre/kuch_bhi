---
title: "Group keys must be opened only with a wrapper key the phone has accepted, or the server can hand out its own group key"
author: Chaitanya
date: 2026-11-17
branch: main
cost: { minutes: 9, tokens: 204230 }
id: l-91a27de2
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/key-change-warning.md
  - docs/design/pages/key-change-warning.html
  - lib/services/encryption_service.dart
  - docs/design/00-foundation.md
  - docs/design/10-registry.md
---

## Decided
Spec drafted 2026-11-17 (key-change-warning, audit F3, awaiting the user's PASS). Each phone pins every contact's public key on first sight and encrypts/decrypts only from the pin; a different server key becomes "pending" with a local "security code changed" line, a blocking card in the DM, and skipped group wraps until Accept (catch-up wrap on an admin's phone). My own key mismatch no longer deletes the private key; a Keep / Restore screen asks.

## Watch out
The audit only named DM sends and wrapping TO members. The group-key walk also trusts the server: it opens each wrapped group key with the wrapper's current server public key (expand of encrypted_by_user_id). A server writer who swaps an admin's key can wrap a group key it made, and members would send under it. The fix is to try only that wrapper's accepted keys (pin + history). Side effect: versions wrapped before an admin's own reset open again with the history key.
Every user fetch overwrites users.public_key; the single funnel is UsersDao.upsertUser/upsertUsers, so the pin check goes there and users.public_key becomes display-only.

In the code: lib/services/encryption_service.dart groupKeyFields (:496) and the walk (:776-800); message_repository_impl.dart _getConvKey (:6386-6413), rotation (:4141-4157); decrypt_pass.dart _resolveKeys (:415-433); auth_repository_impl.dart _initEncryptionKeys (:582-597).
