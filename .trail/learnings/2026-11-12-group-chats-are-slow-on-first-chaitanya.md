---
title: "Group chats are slow on first download because every key version costs a storage read and an isolate hop, and dead versions are walked three times"
author: Chaitanya
date: 2026-11-12
branch: main
cost: { minutes: 6, tokens: 163174 }
id: l-d3d5bab2
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/group-key-restore.md
  - lib/services/encryption_service.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/core/decrypt/decrypt_pass.dart
  - lib/core/utils/key_gap.dart
---

## Decided
Planning finding, 2026-11-12 (spec drafted, awaiting the user's PASS). On a fresh install each group's key list comes in one request, but every version then costs one secure-storage read (the transport-key cache is not in the in-memory key map) and one isolate hop for the AES attempt. Versions that open are rewritten to secure storage on every walk. When no version opens, the history sync walks the group three times with 400 + 800 ms sleeps, because the candidates wrapper turns every error into the same "missing key" error, so "the server answered, nothing opens" looks like a dropped connection. Proposed fix: no retry when the server has answered, one batch decrypt per wrapping member's key, write only changed slots, no walk without the device key pair, `fields` on the request, one timing line.

The server list is already only rows made for this user, so dead versions are not "from before I joined". They are rows where this user's key pair or the wrapping member's key pair changed after the row was made (sign-ins before the K1 fix, account switches, two phones on one account). The row stores who wrapped it, not which public keys were used, so the phone cannot tell which side changed. Messages under a dead version never decrypt for that user.

## Tried and ruled out
Remembering dead versions between walks: once the decrypts are batched, a failed tag costs microseconds, so a skip list is extra code for nothing.

## Watch out
The group-key prefetch runs on any conversation or member event, including while the restore screen is waiting for the recovery key. With no key pair every version fails and the walk ends "no decryptable group key". The phones' log buffers rotate fast, so the per-group split of run 1 is unknown. Measure with the proposed timing line.

In the code: encryption_service.dart getOrFetchGroupKeyCandidates (network walk), decryptGroupKey → getOrDeriveConversationKey (per-version storage read); message_repository_impl.dart syncAllHistory key retry loop, _getConvKeyCandidates, prefetchGroupKeys. Spec: docs/design/pages/group-key-restore.md.
