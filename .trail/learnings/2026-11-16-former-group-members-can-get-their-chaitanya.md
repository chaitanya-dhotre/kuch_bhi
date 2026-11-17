---
title: "Former group members can get their history back only through a server-written record with a time limit, and a leave probably never rotates the group key"
author: Chaitanya
date: 2026-11-16
branch: main
cost: { minutes: 7, tokens: 198837 }
id: l-4e5735fd
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/former-member-history.md
  - docs/design/pages/former-member-history.html
  - lib/infrastructure/repositories/message_repository_impl.dart
  - docs/design/pages/membership-rules.md
  - docs/design/pages/group-rejoin-history.md
  - KUCH_BHI_PROJECT_BIBLE.md
  - docs/superpowers/specs/2026-10-03-group-invites-rework-design.md
---

## Decided
Spec drafted 2026-11-16 (former-member-history, awaiting the user's PASS). Default: a new `former_members` collection that only a server hook writes, when a group member row is deleted. It holds `history_until` = the server time of the delete. Read-only rule branches on messages, message_media and conversations let a former member list rows up to that time. Clients can't write it, and no create or update rule reads it, so the F1 membership fix stays closed.

## Tried and ruled out
- Using the person's own group_keys rows as proof of former membership: no time limit is possible, so they would get every later message's metadata live. After a leave, they would also read it in clear (see below).
- A `left_at` column on conversation_members: every rule and client path that trusts members would need `left_at = ""`. Missing one reopens F1.

## Watch out
- By code read, a leave never rotates the key. The leaver's own rotate runs after its row is deleted, can't list members and returns early. Admin phones rotate only on a member create or a key gap. So the server's messages rule is the only barrier after a leave. Not yet confirmed on a device.
- `?>=` on an `@collection` back-reference is untested on PocketBase 0.37.5. Only the bare `<=` was tried, and it failed. The dry run must prove all three conditions bind to the same row before anything else.

In the code: lib/infrastructure/repositories/message_repository_impl.dart leaveGroup :4301-4362, _rotateGroupKeyNow :4110-4125, _subMembers :590-601, _syncConversationsPass :6491; bible §7 group_keys list rule :985; spec docs/design/pages/former-member-history.md.
