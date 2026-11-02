---
title: "The server silently ignores message fields it doesn't know, and the message update rule only blocks the fields it names"
author: Chaitanya
date: 2026-11-01
branch: main
cost: { minutes: 13, tokens: 259839 }
id: l-fed4703a
scope: repo
status: active
src: agent
touches:
  - docs/audits/wave-4-work-log.md
  - docs/backlog.md
  - lib/core/utils/jpeg_without_exif.dart
  - lib/data/local/database/daos/messages_dao.dart
  - lib/features/chat/screens/chat_screen.dart
  - lib/features/chat/widgets/message_context_menu.dart
  - lib/features/chat/widgets/reply_quote.dart
  - lib/features/chat/widgets/voice_message_bubble.dart
  - lib/infrastructure/ingest/ingest_boundary.dart
  - lib/infrastructure/repositories/auth_repository_impl.dart
---

## Decided
Any new field on messages needs two live changes, not one: add the field, and add it to both branches of the messages update rule. The albums spec's W1 does both, and lands before any phone runs a build that sends the new fields.

## Watch out
- PocketBase here drops unknown create-body fields without an error. The media create has always sent `media_id: ''` although `messages` has no such field. A client that ships before its schema change loses the new field silently: nothing fails, the data just isn't there.
- The messages update rule is a deny-list: one branch lets the sender mark deleted-for-everyone, the other lets any member update, each listing fields that must not be set. A new field that isn't listed can be changed by any member of the chat on anyone's message.
- The push hook on message create reads only id, conversation and sender, and sends one push per message.

In the code:
- Live read 2026-11-01 (read-only): `_collections` row `messages` (fields, createRule, updateRule); hooks `/opt/pocketbase/pb_hooks/fcm_notify.pb.js`, `disappearing_messages.pb.js`.
- Client create body: message_repository_impl.dart `_uploadMediaMessage` (sends `media_id`).
- Spec: docs/design/pages/albums.md, "Live PocketBase" (R1, W1).
