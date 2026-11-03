---
title: "Deleting a text that hasn't been sent yet cancels it, and its queue entry is what tells the server"
author: Chaitanya
date: 2026-11-03
branch: main
cost: { minutes: 8, tokens: 182290 }
id: l-4d685c37
scope: repo
status: active
src: agent
touches:
  - docs/backlog.md
  - test/offline/text_send_cancel_test.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/data/local/database/daos/messages_dao.dart
  - lib/infrastructure/ingest/ingest_boundary.dart
---

## Decided
- Deleting an own text that the queue has not had confirmed by the server is a cancel, whether the user picked "for me" or "for everyone": an unsent row reached no one (the multi-select sheet already sends unsent rows to "for me"). The row gets the same `cancelled` status tombstone as a cancelled media send.
- The text's queue entry stays and does the cancel when the worker reaches it: it marks the server copy deleted for everyone (a 404 means the create never landed), then drops the row, any echo row and the entry. Offline, the mark fails, the entry backs off and retries. A failed entry is dropped at once (the server refused it), so it no longer blocks the chat's later sends.
- Deleted while the create is in flight: the confirmation step re-reads the row inside its transaction and never stamps a cancelled row; the drain-ack stamp in the ingest commit skips it too.
- A text's server id is its queue entry id, not its local id, so the ingest finds a cancelled text's echo through a join on the queue table and keeps it hidden.

## Tried and ruled out
- Deleting the row and entry locally when the entry has 0 attempts: reconnecting resets attempts to 0, so 0 does not prove the create never reached the server.
- Putting the server id on the cancelled row so the ingest matches it: a row with a server id but device-clock time poisons the resume watermark.

## Watch out
- The cancel check and the confirmation stamp must share one transaction (they do: the queue-entry read plus the tombstone write in the delete, and the re-read plus stamp at confirmation). Split them and a delete can hide a message that was already delivered.

In the code: MessageRepositoryImpl.deleteMessage, _cancelTextSend, _finishCancelledText, _sendTextOp (top check, duplicate-id path, ack transaction); IngestBoundary.commit phase 1b; MessagesDao.cancelledSendIds; test/offline/text_send_cancel_test.dart.
