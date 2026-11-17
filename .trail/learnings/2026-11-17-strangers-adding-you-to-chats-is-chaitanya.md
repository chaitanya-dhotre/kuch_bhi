---
title: "Strangers adding you to chats is fixed by requiring a friendship for direct adds, while forged system notices can't be fixed by a server rule"
author: Chaitanya
date: 2026-11-17
branch: main
cost: { minutes: 6, tokens: 175988 }
id: l-eba765e1
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/server-rules-wave2.md
  - docs/design/pages/server-rules.md
  - docs/design/pages/membership-rules.md
  - KUCH_BHI_PROJECT_BIBLE.md
  - lib/infrastructure/repositories/friend_repository_impl.dart
  - lib/infrastructure/services/group_create_service.dart
---

## Decided
Spec server-rules-wave2 drafted 2026-11-17 (awaiting the user's PASS). Direct adds to a chat (group create, DM) must be friends of the adder; everyone else only through an invite they accept. That matches the app: the group picker lists friends only, the only DM path is right after a friend request is accepted, and later adds are always invites. Friendships may then only be created by the recipient of an accepted request, because a friendship becomes the key to adding someone.

The creator branch of the members create rule is narrowed to the creator's own first admin row while the chat has no member rows yet. That closes the hole where a removed creator re-adds themselves and the admin's phone then wraps the group key for them.

## Tried and ruled out
- Blocking system notices on the server (type = "system"): every member posts real ones (the joiner posts "joined", the leaver posts "left" before its row is deleted, admins post removed/promoted/demoted, the creator posts "created the group"). A rule can't tell real from forged. Fix belongs in the app (show who posted it).
- Enforcing blocks in rules now: the app has no block feature (the block repository methods have no caller), and a rule can't say "no block row exists" across two fields. When a block feature ships, blocking should delete the friendship, which the friend requirement then enforces.

## Watch out
- "No member rows yet" relies on a bare `!=` against `@collection.conversation_members:existing`, which PocketBase checks against ALL rows. That for-all meaning broke a date cutoff before, but is exactly right here. Never tried on 0.37.5: the dry run must test it first, with a back-relation `:length = 0` and then a flat create hook as fallbacks.
- A refused reaction is dropped silently by the outbox, so a wrong reactions rule shows up only as missing reactions on the other phone.

In the code: docs/design/pages/server-rules-wave2.md (N10–N18, X-1..X-8); friend_repository_impl.dart:59-130, 245-284; group_create_service.dart; message_repository_impl.dart _emitSystemMessage and its callers.
