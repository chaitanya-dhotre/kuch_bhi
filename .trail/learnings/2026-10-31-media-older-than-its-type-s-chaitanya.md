---
title: "Media older than its type's longest retention is shown as expired from the message date alone, because a purged server copy looks like a not-yet-uploaded one"
author: Chaitanya
date: 2026-10-31
branch: main
cost: { minutes: 14, tokens: 376478 }
id: l-3dd6b25a
scope: repo
status: active
src: agent
touches:
  - docs/audits/bug-wave-2-work-log.md
  - lib/core/utils/media_utils.dart
  - lib/core/constants/app_constants.dart
  - lib/infrastructure/media/media_blob_store.dart
---

## Decided
- A photo, video, voice note or document whose message is older than the longest the server keeps that type, at any quality, plus one day, is shown as expired straight from the message date. The bubble does not ask for the file at all: no download, no 45-second wait, no retry. Limits: photo 60, video 30, voice 60, document 60 days.
- A photo between 30 and 60 days old may be an expired High-quality one, but the receiver cannot know the quality, so it still waits and offers a retry.

## Tried and ruled out
- Treating only a blob the store marked "failed" as final (the first review fix): on the device none of the expired items were failed. The server purges expired media records, a purged record answers 404, and the store files a 404 as "not landed yet" (queued), the same as the upload race for a brand-new message. So expired media sat on a shimmer and then a retry that could never work.

## Watch out
- The store's reconnect drain still re-requests every queued blob, purged ones included (one record lookup each per reconnect). That store is frozen pipeline code.
- Read the phone's own database to see blob states: a debug build allows `adb exec-out run-as com.chai.kuch_bhi cat app_flutter/kuch_bhi.sqlite` (copy the -wal too), then query media_blob_table joined to messages_table on server_id.

In the code: lib/core/utils/media_utils.dart isPastRetention, lib/core/constants/app_constants.dart retention*Days, lib/features/chat/widgets/{image,video,voice,document}_message_bubble.dart (checked before watching mediaFileProvider), lib/infrastructure/media/media_blob_store.dart _runPipeline (record 404 → queued).
