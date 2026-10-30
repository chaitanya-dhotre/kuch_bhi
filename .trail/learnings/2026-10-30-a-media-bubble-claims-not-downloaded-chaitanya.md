---
title: "A media bubble claims 'not downloaded' only when it knows, and draws the full file once it is on the phone"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 6, tokens: 106678 }
id: l-a300ca49
scope: repo
status: active
src: agent
touches:
  - docs/backlog.md
  - docs/design/10-registry.md
  - docs/design/pages/media-work-log.md
  - docs/design/pages/media.html
  - docs/design/pages/media.md
  - lib/core/router/app_router.dart
  - lib/data/local/database/daos/media_blob_dao.dart
  - lib/features/chat/widgets/expiry_badge.dart
  - lib/features/chat/widgets/image_message_bubble.dart
  - lib/features/chat/widgets/message_bubble.dart
---

## Decided
- The bubble's download disc shows only on a positive "not on disk" answer (no blob row, or a row that isn't ready, or its file is gone). While the answer is unknown (stream not emitted yet, or it errored) the bubble shows no disc and keeps Play, so it never claims what it hasn't seen. This also keeps older widget tests, which don't fake the database, unchanged.
- Once the full file is on disk the photo bubble draws it at bubble width × screen density instead of the thumbnail. That fixes pixelation for old messages too, which a bigger thumbnail alone can't: the sender bakes the thumbnail in at send time.
- The check is read-only: it watches the blob row and never starts a download.

## Tried and ruled out
- Only raising the thumbnail size: it helps new sends only, and a thumbnail that looks sharp still hides that the photo isn't downloaded, which is what the user found misleading.

## Watch out
- Your own sent photo shows the disc until you open it once, because the sender's full copy isn't kept in the media cache after upload. That's truthful. Changing it belongs to the media-send work (backlog 12.4).

In the code: mediaFullLocalProvider (media_viewer_providers.dart) over MediaBlobDao.watchById; MediaDisc in expiry_badge.dart; thumbnails 640px at 70% in generateImageThumbnail; tests in test/media/media_download_state_test.dart.
