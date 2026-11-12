---
title: "The server only accepts message types from a fixed list, so a new message type must be added to that list on the live server before any phone can send it"
author: Chaitanya
date: 2026-11-11
branch: main
cost: { minutes: 14, tokens: 272609 }
id: l-a3edd8db
scope: repo
status: active
src: agent
touches:
  - lib/features/stickers/stickers.dart
  - lib/features/stickers/sticker_widgets.dart
  - test/stickers/sticker_send_test.dart
  - test/stickers/sticker_widgets_test.dart
  - docs/design/pages/mascot.md
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/features/chat/widgets/message_bubble.dart
  - lib/features/chat/widgets/message_input.dart
---

## Decided
- The live messages `type` field is a select with fixed values, not free text (checked read-only 2026-11-11). Stickers needed `sticker` added through a live migration, which went live before any sticker build was installed. A new type the phone sends without that step is refused with an opaque 400 ("type: Invalid value …"), and the outbox keeps retrying it.
- The migration re-adds the select field under its existing id with the extra value. PocketBase replaces a field with the same id in place, so no data moves, and the down step restores the old list.
- `type` was already locked in both update-rule branches, and no server hook reads or labels types (the push preview is always the generic one). So a new type needs only the value added: no rule or hook change.

## Tried and ruled out
- Leaving the server alone and relying on old-app fallback text: the fallback only helps receivers. Without the select value, the sender's create never reaches the server.

## Watch out
- Test the change on a `.backup` copy with a throwaway migration that saves one row of the new type. It fails before the change and passes after, which proves the select was the blocker.
- The values list in the migration is written out in full. Re-read the live list first, in case another type was added since.

In the code: live migration pb_migrations/1794400000_updated_messages_type_sticker.js (field id select625724656, values text,image,video,voice,poll,system,document,file,sticker); backup /home/ubuntu/pb_backups/data.db.20261111-stickers-pre; client create body in message_repository_impl.dart _sendTextOp sends 'type': msg.type.
