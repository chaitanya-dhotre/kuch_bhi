---
title: Group-key rotation keeps history; only a lost keypair orphans envelopes
author: Chaitanya
date: 2026-10-28
branch: main
cost: { minutes: 24, tokens: 0 }
id: l-05f54b27
scope: repo
status: active
src: agent
---

## Decided

Stuck `key_missing` rows are almost never a rotation's fault: rotation
(`_rotateGroupKey`) writes a NEW key_version and RETAINS historical versions
on purpose — old rows decrypt offline via versioned slots. The real killer is
a destroyed device keypair (`pm clear` / uninstall+reinstall): the
`group_keys` envelopes wrapped to the OLD public key become permanently
unwrappable (`Skipping undecryptable group key version`). Ciphertext intact,
unwrap ability gone.

Admin re-wrap RECOVERS rows (re-encrypt K_old to the member's current pubkey
→ repair pass heals them); it never deletes rows. Recovery needs an admin
device that still holds K_old — user ruled 2026-10-29: NOT worth it, test
data only, fresh start after finalisation.

## Watch out

Message rows carry NO key_version column — decryption brute-forces every
candidate. A truncating key fetch (single page) silently loses the OLDEST
keys; `getOrFetchGroupKeyCandidates` uses getFullList deliberately.

## In the code

_rotateGroupKey (message_repository_impl.dart) — version+1 writes, history kept.
getOrFetchGroupKeyCandidates (encryption_service.dart) — full-list fetch,
per-version slots, "Skipping undecryptable group key version" at the unwrap
catch = the orphan symptom.
