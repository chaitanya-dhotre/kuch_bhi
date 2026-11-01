---
title: "A cancelled media send is remembered by a cancelled status, kept inside the ingest commit, because the server copy rewrites the hidden flag until the cancel re…"
author: Chaitanya
date: 2026-11-01
branch: main
cost: { minutes: 6, tokens: 46394 }
id: l-8e5e2acf
scope: repo
status: active
replaces: l-a642f52a
src: agent
touches:
  - lib/infrastructure/ingest/ingest_boundary.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
  - test/offline/media_send_followups_test.dart
  - test/offline/media_send_harness.dart
  - docs/audits/wave-4-work-log.md
---

## Decided
- A media send cancelled after its create ack is hidden and gets status `cancelled`, the durable tombstone. The ingest commit (the one writer for fetch, SSE and single-message caching) re-reads its target rows inside its transaction and keeps any `cancelled` row hidden and cancelled. Status writers never overwrite it, and resume marks the server copy, then deletes the row.
- Deleting an own media send is a cancel only when it can't have reached anyone complete: no server id yet, or failed. A pending upload deleted "for me" keeps uploading, and its finish clears the upload latch.

## Tried and ruled out
- Guarding in the companion builders: fetch and SSE build them from a row read before the decrypt step, so a cancel in that gap was overwritten.
- A sticky deleted-for-everyone flag for every row; delete-for-me, blob rows or the server flag as the marker. None can tell "not marked yet" from "marked and fetched back".
- Cancel on every delete of a latched send: the latch can be set while the photo is uploading or already on the server, so "Delete for me" unsent it.

## Watch out
- A 404 on the cancel mark while the upload is still running means the create may still land: keep the row.
- A photo queued before a text can still be overtaken on reconnect (the server orders the text first).

In the code: IngestBoundary.commit phase 3a; MessagesDao.markCancelledLocally / updateMessageStatus / pendingOwnMedia; MessageRepositoryImpl.deleteMessage, _markCancelledOnServer; test/offline/media_send_followups_test.dart.
