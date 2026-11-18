---
title: "A member can move their own group-membership row into any other chat, and the real admin's phone then gives them the group key"
author: Chaitanya
date: 2026-11-16
branch: main
cost: { minutes: 9, tokens: 205232 }
id: l-55924082
scope: repo
status: active
src: agent
touches:
  - docs/audits/2026-11-16-security-cloudflare-skill.md
  - KUCH_BHI_PROJECT_BIBLE.md
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/services/presence_service.dart
  - docs/design/pages/server-rules.md
---

## Decided
Found in the 2026-11-16 security audit (not fixed yet; the fix will be specified and built separately). The second branch of the conversation_members update rule lets a row's owner change it while only locking `role`. So any signed-in user can create a chat, make themselves admin of it, then re-point that member row at any other group. The group's real admin's phone runs the key-gap reconcile on every resync, sees a member without the current key, rotates, and wraps the new key for every member the server lists, the intruder included. Two other routes reach the same place: an admin re-pointing an invite, and an invitee self-joining with role admin. Chat ids leak through `users.current_chat` / `typing_in`, which any signed-in user can list.

## Watch out
The N1–N9 rule fix (2026-11-15) deliberately left member create/update, invites, reactions, friendships and friend_requests alone. Do not assume those are scoped. Any server-side membership fix should also lock `conversation_id` and `user_id` on update. Client-side, rotation trusts the server's member list.

In the code: KUCH_BHI_PROJECT_BIBLE.md:763-764 (member create/update rules), :1050 (invite update), lib/infrastructure/repositories/message_repository_impl.dart:4656-4701 (_reconcileGroupKeyGaps) and :4120-4123 (rotation reads members from the server), lib/services/presence_service.dart:93,123. Report: docs/audits/2026-11-16-security-cloudflare-skill.md F1/F2.
