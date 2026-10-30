---
title: "A photo's expiry date is how long the server keeps it, not disappearing messages, and a failed media download is never retried"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 15, tokens: 278148 }
id: l-3fbc6c51
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/media.md
  - docs/design/pages/media.html
  - lib/services/media_upload_service.dart
  - lib/infrastructure/media/media_blob_store.dart
  - lib/features/chat/providers/chat_provider.dart
  - lib/data/local/database/tables/messages_table.dart
  - lib/domain/entities/message.dart
---

## Decided
- Every photo, video, voice note and document carries an expiry date. That date is the server's retention window, set at upload by type and quality. It is NOT the disappearing-messages timer. Anything that wants to treat "disappearing" media differently (hide Save/Share, warn) cannot use the media expiry; per-message disappearing expiry lives only in the local messages table and is not on the Message entity.
- The media store marks a download as failed (expired, dead link, failed verify, failed decrypt) and never retries it. Only offline or a missing record leaves it queued. So a viewer's "Try again" can only help a queued or plain-null load. For failed ones, show an honest end state (expired / can't decrypt) instead of a retry button.

## Watch out
- Opening media offline that was never downloaded: the media provider returns null only after waiting up to 45s for the media record, so any "fetch, then open" UI looks frozen offline. Open the screen first and load inside it; on reconnect, invalidate the provider and read again.
- A missing conversation key ends up queued, not failed, so it cannot be told apart from "not landed yet" without touching the key path.

In the code: lib/services/media_upload_service.dart:46 (retentionExpiry → expires_at), lib/infrastructure/media/media_blob_store.dart requestBlob (failed is terminal; 404 → dead_link, 401/403 → expired, others → queued), lib/features/chat/providers/chat_provider.dart:61-83 (45s mediaArrived wait), lib/data/local/database/tables/messages_table.dart:47 (per-message expiresAt, not on lib/domain/entities/message.dart).
