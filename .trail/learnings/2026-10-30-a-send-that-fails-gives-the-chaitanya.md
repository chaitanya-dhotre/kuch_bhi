---
title: "A send that fails gives the text back instead of a failed bubble, because a send can only fail before its message is saved"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 14, tokens: 130361 }
id: l-5f792a14
scope: repo
status: active
src: agent
touches:
  - test/chat/send_failure_test.dart
  - test/offline/load_more_failure_test.dart
  - test/grep_gates_test.dart
  - lib/features/chat/providers/chat_provider.dart
  - lib/features/chat/widgets/message_input.dart
  - lib/features/chat/screens/chat_screen.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/domain/repositories/message_repository.dart
  - docs/audits/bug-wave-1-work-log.md
---

## Decided
A text or media send that is rejected restores what the user typed (text, reply quote, or the voice preview) and shows a toast. It does not create a failed bubble. Every throw in the send path happens before the message row and its outbox op are written, and those two writes are one transaction. Offline text sends never throw: they queue as pending bubbles. A failed bubble would need a row that must not exist (a removed group member, for example).

## Tried and ruled out
A "failed bubble the user can retry" (the audit's preferred fix): there is no row to mark at the point of failure, and making one for a not-a-member rejection would let a removed member queue messages.

## Watch out
- Offline media is different: the row is written first and the unawaited upload then marks it `failed`. It is not queued in the outbox, so a voice note or document sent in airplane mode shows failed. That code sits in the frozen upload pipeline.
- A failed older-history page must not move the paging offset. The server paging is page = offset/40 + 1, so moving the offset on a failed page skipped 40 messages and marked history as ended.
- Widget tests: tapping the composer's send button misses in a bare Scaffold host. Use the keyboard submit action (`testTextInput.receiveAction(TextInputAction.done)`), which runs the same send.

In the code: SendMessageNotifier / SendMediaMessageNotifier rethrow (chat_provider.dart); MessageInput._send restores the text (message_input.dart); loadMoreMessages has an 8s timeout + rethrow; _loadMore + HistoryLoadFailedRow (chat_screen.dart). Tests: test/chat/send_failure_test.dart, test/offline/load_more_failure_test.dart.
