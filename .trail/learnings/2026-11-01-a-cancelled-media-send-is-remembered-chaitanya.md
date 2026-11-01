---
title: "A cancelled media send is remembered by a cancelled status, because the server copy rewrites the hidden flag until the cancel reaches it"
author: Chaitanya
date: 2026-11-01
branch: main
cost: { minutes: 17, tokens: 269561 }
id: l-a642f52a
scope: repo
status: active
src: agent
touches:
  - test/offline/media_send_followups_test.dart
  - test/media/voice_retry_tap_test.dart
  - test/chat/multi_delete_confirm_test.dart
  - test/services/group_icon_exif_test.dart
  - lib/data/local/database/daos/messages_dao.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/features/chat/widgets/voice_message_bubble.dart
  - lib/features/chat/widgets/message_context_menu.dart
  - lib/features/chat/screens/chat_screen.dart
  - lib/core/utils/jpeg_without_exif.dart
---

## Decided
- A media send cancelled after its create ack is hidden locally and marked with status `cancelled`. That status is the durable tombstone: a page fetch or live update keeps the row hidden, no status writer (receipts included) overwrites it, and the resume pass finds it to mark the server copy deleted for everyone. The local row is deleted once that mark lands.
- Deleting an own send that still holds its upload latch is a cancel: it frees the pinned blobs and hides the empty server copy from receivers, "Delete for me" included, because no complete copy ever reached them.

## Tried and ruled out
- Making the local deleted-for-everyone flag sticky for every row: delete-for-everyone writes it locally even when the server call fails, so that path would silently diverge from receivers.
- Using delete-for-me, the blob rows or the server flag as the marker: none can tell "server not marked yet" from "already marked and fetched back", so resume would re-mark the same messages on every pass.

## Watch out
- The fetch, SSE and receipt paths rebuild own rows from the server. Any new local-only state on a message needs a column or status those paths carry over, or the next fetch erases it.
- A photo queued before a text can still be overtaken on reconnect (the server orders the text first). Only the text outbox waiting for the earlier media create would fix it.

In the code: MessagesDao.markCancelledLocally / updateMessageStatus / pendingOwnMedia; MessageRepositoryImpl._companionFromRecord, ssePinDeleteCompanion, deleteMessage → cancelMediaUpload; test/offline/media_send_followups_test.dart; docs/audits/wave-4-work-log.md.
