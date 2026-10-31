---
title: "A media download gives up after 8 seconds of silence, not after 8 seconds in total, because files reach 100 MB"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 26, tokens: 320370 }
id: l-53f78d3f
scope: repo
status: active
src: agent
touches:
  - lib/infrastructure/offline/connectivity_signal.dart
  - lib/features/chat/providers/chat_provider.dart
  - lib/infrastructure/services/link_preview_service.dart
  - lib/features/chat/widgets/media_retry.dart
  - lib/infrastructure/media/media_blob_store.dart
  - lib/features/auth/screens/backup_pin_screen.dart
  - test/media/media_retry_test.dart
  - test/offline/media_stall_test.dart
  - test/home/open_chat_busy_test.dart
  - test/home/friend_code_error_test.dart
---

## Decided
- The media download is bounded on silence: 8s waiting for the response headers, then 8s between body chunks. A long download that keeps receiving bytes is never cut off. The record lookup before it gets a plain 8s bound. A stall throws into the pipeline's existing catch, so the blob ends "queued" (resumed on reconnect), never "failed".
- Opening a chat from Home bounds only the wait (8s), not the conversation sync behind it. Dart's timeout does not cancel the sync, which touches membership and key-rotation scheduling, so it finishes in the background and the next tap finds the chat locally.

## Tried and ruled out
- A flat 8s timeout on the whole download (what the audit and the brief first suggested): files can be 100 MB, so every large video on a slow link would time out and stay unavailable.
- Bounding the network reads inside the conversation sync instead of the Home wait: that sync also runs for resync and the restore history sync, which would then fail on slow links.

## Watch out
- A media load that returns nothing is cached for good (the provider is not auto-disposed). It now re-runs on the next offline-to-online flip, but on a network that stalls while still online, only a tap-to-retry recovers it.

In the code: lib/infrastructure/media/media_blob_store.dart (_stallBound, send().timeout + ByteStream(stream.timeout)), lib/features/home/screens/home_screen.dart _openChat, lib/infrastructure/offline/connectivity_signal.dart invalidateOnReconnect, lib/core/constants/app_constants.dart maxFileSizeMb = 100, test/offline/media_stall_test.dart.
