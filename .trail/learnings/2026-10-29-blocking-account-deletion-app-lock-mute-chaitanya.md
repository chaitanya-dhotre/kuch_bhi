---
title: "Blocking, account deletion, app lock, mute and notification preferences look built but are not, so Settings offers none of them"
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 1, tokens: 0 }
id: l-2561fc62
scope: repo
status: active
src: agent
touches:
  - pubspec.yaml
---

## Decided
Settings holds only what works end to end: theme, a notification STATUS row that opens Android's app settings, and About. Every other candidate is its own task, because a row for it would promise something the app does not do.

## Tried and ruled out
- In-app notification switch / per-type toggles: the server push hook sends every message and stores no per-user preference, so a switch would not stop pushes. Only the OS permission is real.
- Blocked-users list: the repository has block/unblock/list methods but nothing calls them and nothing filters a blocked user's messages or requests. The live blocked_users collection was never verified.
- Delete account: the repository method deletes only the users row, orphaning memberships, group keys and messages. Needs a server cascade, and sits in the key boundary.
- App lock: local_auth is a dependency with zero uses.
- Mute: the conversations table has a muteUntil column that nothing reads or writes.
- Privacy toggles (read receipts, typing, last seen): presence writes last_seen and typing_in unconditionally; nothing reads a preference on either side.

## Watch out
"The method exists" is not "the feature exists". Check callers and server enforcement before putting a row in front of users.

In the code:
- friend_repository_impl.dart blockUser/unblockUser/getBlockedUserIds (0 callers)
- auth_repository_impl.dart deleteAccount (0 callers)
- pubspec.yaml local_auth (0 uses in lib/)
- conversations_table.dart muteUntil (unused)
- presence_service.dart last_seen / typing_in always written
- server hook fcm_notify.pb.js pushes every message
- permission_handler already used in message_input.dart; POST_NOTIFICATIONS declared
