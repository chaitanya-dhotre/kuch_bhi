---
title: Choosing High quality for a photo or video also halves how long the server keeps it
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 1, tokens: 1571 }
id: l-98a32c45
scope: repo
status: active
src: agent
touches:
  - lib/services/media_upload_service.dart
  - lib/core/constants/app_constants.dart
  - lib/features/chat/widgets/message_input.dart
---

## Decided
The quality choice (Normal / High) sets two things, not one: the compression level and the server retention. High photos are kept 30 days (Normal 60); High videos 15 days (Normal 30). Documents and voice notes are kept 60 days. Any text that tells the sender about quality should also say how long it is kept, read from the constants, never hard-coded.

Sent chat photos carry no EXIF/GPS: the compressor drops it by default (keepExif is false), so the chat send path needs no extra stripping (unlike avatar uploads, which re-encode on purpose).

## Watch out
"High = better" is the obvious reading, but it gives the recipient half the time to save the file. A retention constant changed without the user-facing text (or the reverse) silently misleads senders.

In the code:
- retention: lib/services/media_upload_service.dart retentionExpiry (switch on media type + quality)
- days: lib/core/constants/app_constants.dart retentionPhotoNormalDays=60, retentionPhotoHighDays=30, retentionVideoNormalDays=30, retentionVideoHighDays=15, retentionVoiceDays=60 (documents reuse it)
- compression: media_upload_service.dart compressImage (normal 1280/60, high 2560/90; FlutterImageCompress default keepExif false)
- picker: lib/features/chat/widgets/message_input.dart _showQualityPicker
