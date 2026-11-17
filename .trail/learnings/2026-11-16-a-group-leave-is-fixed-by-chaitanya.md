---
title: "A group leave is fixed by the admin's phone rotating when a key holder is no longer a member, not by the leaver"
author: Chaitanya
date: 2026-11-16
branch: main
cost: { minutes: 5, tokens: 150881 }
id: l-9ebc4079
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/leave-rotation.md
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/core/utils/key_gap.dart
  - docs/design/pages/removal-lock.md
  - lib/services/encryption_service.dart
---

## Decided
Spec drafted 2026-11-16 (leave-rotation, awaiting the user's PASS). Default: the elected rotation owner's phone runs one stateless check per chat (a member missing the current key, or a current-key holder who is no longer a member) and rotates. It is triggered when its sync drops a member who is gone from the server, plus the resume key-gap net. The owner is elected from the fresh server member list, not the local one, because the local list can still name the leaver as the smallest-id admin.

## Tried and ruled out
- The leaver rotating before it deletes its row: only admins may create group_keys rows, so plain members can't. A changed or crashed app skips it, and the key-gap check would rotate the still-member leaver back in.
- A server hook: the server has no group key, so it can only signal, and the stateless check needs no signal.

## Watch out
- The check must run inside the per-chat serial slot and call the inner rotate directly. Calling the outer rotate from inside queues behind itself for the 2-minute cap.
- An admin's own removal deletes the local member row before its sync runs, so the sync never schedules a second rotation for it.

In the code: lib/infrastructure/repositories/message_repository_impl.dart leaveGroup :4301-4362, _rotateGroupKeyNow :4110, sync member-gone loop :6659-6668, _reconcileGroupKeyGaps :4656; lib/core/utils/key_gap.dart; bible group_keys createRule :987; spec docs/design/pages/leave-rotation.md.
