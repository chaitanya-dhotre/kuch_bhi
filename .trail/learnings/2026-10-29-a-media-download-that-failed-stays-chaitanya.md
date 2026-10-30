---
title: "A media download that failed stays failed until the cached result is dropped, so any retry must invalidate it first"
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 24, tokens: 430019 }
id: l-d64d6bba
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/sheets-work-log.md
  - ".handoffs/2026-10-30T0034-auto-pause-919a31.md"
  - lib/features/chat/providers/chat_provider.dart
  - lib/features/media/screens/media_docs_screen.dart
---

## Decided
The voice note sheet's Try again invalidates the media-file provider for that note before loading again. The provider itself is left as it is (shared with every bubble and viewer).

## Tried and ruled out
- Re-running the sheet's load on Try again (what the first Page 8 build did): the media-file provider is a plain, non-auto-dispose family, so after an offline attempt returns null, every later read returns the same cached null at once. Try again showed the error again until an app restart.

## Watch out
Any other "retry" on a media download (image, video, document) has the same trap: re-reading the provider is not a retry. A test that only checks the error appears will pass with the bug; count the fetches.

In the code:
- lib/features/chat/providers/chat_provider.dart: mediaFileProvider (FutureProvider.family, not autoDispose)
- lib/features/media/screens/media_docs_screen.dart: _VoicePlaySheetState._retry → ref.invalidate(mediaFileProvider(MediaRef(...)))
- test/media/voice_sheet_test.dart: asserts 2 fetches after Try again
