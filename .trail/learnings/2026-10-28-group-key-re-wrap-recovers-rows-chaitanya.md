---
title: Group key re-wrap recovers rows; rotation never deleted them
author: Chaitanya
date: 2026-10-28
branch: main
cost: { minutes: 1, tokens: 0 }
id: l-ebe875cf
scope: repo
status: active
src: agent
---

## Decided

Stuck `key_missing` rows in historical conversations are caused by a
DESTROYED PRIVATE KEYPAIR on the member device (pm clear / reinstall), not
by key rotation. Rotation writes a NEW version and keeps old ones — message
rows carry no key_version, so decryption must be able to try every version,
which is exactly why old versions are retained.

## Watch out

An admin re-wrap does NOT delete anything; it makes rows decryptable again:
an admin device that still holds the old key creates a fresh envelope to the
member's CURRENT public key; the local unwrap then succeeds and the repair
pass heals every row. If no device kept the old key, the rows are
unrecoverable permanently. The uniforms-under-a-new-version path only helps
when the old key material still exists somewhere.

## In the code

`_rotateGroupKey` (message_repository_impl.dart) allocates max+1 and stores
per-member envelopes under the member's CURRENT pubkey. Decryption collects
candidates versioned-slot-first in `getOrFetchGroupKeyCandidates`
(encryption_service.dart), and the skip line there is what marks a version
undecryptable. The give-up budget added for `_repairUndecrypted` reopens on
any membership/key change, so a re-wrap landing later DOES retrigger healing
automatically.
