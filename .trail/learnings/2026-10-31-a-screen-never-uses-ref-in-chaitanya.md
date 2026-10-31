---
title: "A screen never uses ref in dispose, and a reply draft belongs to one chat and dies with it"
author: Chaitanya
date: 2026-10-31
branch: main
cost: { minutes: 13, tokens: 121794 }
id: l-ed77c22d
scope: repo
status: active
src: agent
touches:
  - docs/backlog.md
  - lib/features/chat/providers/chat_provider.dart
  - lib/features/chat/screens/chat_screen.dart
  - lib/features/chat/widgets/message_context_menu.dart
  - lib/features/chat/widgets/message_input.dart
  - test/chat/reply_per_chat_test.dart
  - test/grep_gates_test.dart
  - docs/audits/bug-wave-2-work-log.md
  - lib/core/utils/media_utils.dart
  - lib/features/auth/screens/backup_pin_screen.dart
---

## Decided
- A ConsumerState never uses `ref` in `dispose()`. Riverpod throws there, and the exception silently skips every cleanup line after it, including `super.dispose()`. Read what dispose needs (here the presence service) once in `initState` and keep it in a field.
- The reply draft is per conversation and auto-disposed (`replyProvider(conversationId)`), so it can't follow you into another chat, and it is dropped when its chat closes without any write in dispose.

## Tried and ruled out
- Keeping one global reply and clearing it in dispose: that clear sat right after the line that threw, so it never ran, and a global reply can leak across chats whenever any cleanup is skipped.

## Watch out
- The symptom isn't a crash the user sees. Reply drafts leak into the next chat, are sent there and can't be decrypted on the other phone; presence never "leaves" the chat; and "markNeedsBuild … defunct" assertions show up later in the log, after the next chat opens.

In the code: chat_screen.dart initState/dispose; replyProvider in chat_provider.dart; the grep gate "no dispose() in lib touches ref" in test/grep_gates_test.dart; test/chat/reply_per_chat_test.dart.
