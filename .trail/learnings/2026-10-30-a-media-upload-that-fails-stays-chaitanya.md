---
title: "A media upload that fails stays on the 'uploading' placeholder forever, so the placeholder itself must show the failure"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 3, tokens: 42084 }
id: l-31083ba4
scope: repo
status: active
src: agent
touches:
  - docs/audits/bug-wave-1-work-log.md
  - lib/domain/repositories/message_repository.dart
  - lib/features/chat/providers/chat_provider.dart
  - lib/features/chat/screens/chat_screen.dart
  - lib/features/chat/widgets/message_input.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
  - test/chat/send_failure_test.dart
  - test/grep_gates_test.dart
  - test/offline/load_more_failure_test.dart
  - test/chat/failed_media_placeholder_test.dart
---

## Decided
A voice note or document whose upload failed never gets a server id, so the chat keeps drawing the in-flight placeholder for it, not the real media bubble. The placeholder therefore checks the failed status and shows a static "… not sent" row (no spinner). Own placeholders use the normal full-accent bubble.

## Watch out
- Accent-coloured ink on a faint accent shell is unreadable in dark mode. Pair own-bubble ink with the full accent background.
- Photo and video placeholders still shimmer when failed. There is still no retry for a failed media upload (that code is frozen).

In the code: _OptimisticMediaPlaceholder / _FailedUploadRow in the chat message bubble; test/chat/failed_media_placeholder_test.dart.
