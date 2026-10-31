---
title: "Expired media is told apart from a not-yet-uploaded one by the message's age: by the type's retention in the bubble, and by a day in the media store"
author: Chaitanya
date: 2026-10-31
branch: main
cost: { minutes: 8, tokens: 65013 }
id: l-bcb4d29c
scope: repo
status: active
replaces: l-3dd6b25a
src: agent
touches:
  - lib/infrastructure/media/media_blob_store.dart
  - lib/core/utils/media_utils.dart
  - lib/core/constants/app_constants.dart
  - lib/features/chat/providers/chat_provider.dart
---

## Decided
- A photo, video, voice note or document whose message is older than the longest the server keeps that type (any quality) plus one day shows as expired straight from the message date. The bubble does not ask for the file: no download, no wait, no retry. Limits: photo 60, video 30, voice 60, document 60 days.
- When the server has no record for the media and the message is over a day old, the media store marks it failed (dead link) instead of queued. The bubble then says "No longer available" and stops offering a retry. The user approved this change to the otherwise frozen store on 2026-10-31.
- The 45-second wait for a just-uploaded record runs only for messages under 10 minutes old, or for a blob not already failed. That rule only skips a wait, so 10 minutes is safe; the permanent "failed" mark uses a day.

## Tried and ruled out
- Treating only blobs the store had already marked failed as final: on the phones none of the expired items were failed. The server deletes expired records, a deleted record answers 404, and the store filed every 404 as "not landed yet" (queued). So expired media sat on a shimmer and then offered a retry that could never work.
- Marking a missing record as gone after 10 minutes: failed is never retried, and a 100 MB upload on a slow link can take longer than that.

## Watch out
- A photo between 30 and 60 days old may be an expired High-quality one. The receiver cannot know the quality, so the age rule leaves it alone; the store's one-day rule catches it once its record is gone.
- To see blob states on a phone: a debug build allows `adb exec-out run-as com.chai.kuch_bhi cat app_flutter/kuch_bhi.sqlite` (copy the -wal too). Then query media_blob_table joined to messages_table on server_id.

In the code: lib/core/utils/media_utils.dart isPastRetention; lib/core/constants/app_constants.dart retention*Days; lib/features/chat/widgets/{image,video,voice,document}_message_bubble.dart (checked before watching mediaFileProvider); lib/features/chat/providers/chat_provider.dart mediaFileProvider (10-minute fresh check); lib/infrastructure/media/media_blob_store.dart _runPipeline record-404 branch (over a day old → _fail dead_link); test/offline/media_stall_test.dart.
