---
title: A drift schema bump here also bumps three migration tests and needs a guard for the minimal test databases
author: Chaitanya
date: 2026-11-01
branch: main
cost: { minutes: 21, tokens: 348749 }
id: l-f27529de
scope: repo
status: active
src: agent
touches:
  - lib/data/local/database/daos/messages_dao.dart
  - lib/features/chat/chat_run_grouping.dart
  - lib/features/chat/widgets/album_bubble.dart
  - test/offline/album_send_test.dart
  - lib/features/chat/screens/chat_screen.dart
  - test/chat/album_grouping_test.dart
  - test/chat/album_bubble_test.dart
  - lib/features/chat/providers/chat_provider.dart
  - docs/design/pages/albums-work-log.md
  - lib/data/local/database/app_database.dart
---

## Decided
Every new drift schema version (v12 media-send, v13 albums) edits the `user_version` assert in three existing migration tests: `placeholder_ui_test` (T9.3), `sealed_preview_test` (P7.5) and `media_blob_meta_test` (v11 → v12). They pin the current version on purpose; bumping them is part of the schema change, not "editing a test to pass".

## Watch out
- The migration fixtures are minimal: the v9 one has only `messages_table`, the v11 one only `media_blob_table`. A new `from < N` step must check `sqlite_master` for its table first (as v11/v12/v13 do), or it throws on the fixture that lacks it.
- Hand-written codegen: a table with more than 20 columns cannot use `Object.hash` (20-argument limit); drift switches to `Object.hashAll([...])`. The messages table reached 21 at v13.
- `ssePinDeleteCompanion` rebuilds the whole message row (delete-then-insert), so every new messages column must be carried there too, or an SSE pin toggle resets it.
- A grep gate in `grep_gates_test` counts exactly two `rejected: $e'); rethrow;` send notifiers in `chat_provider.dart`; a third notifier fails it. The album send is called on the repository directly.

In the code: `lib/data/local/database/app_database.dart` (`from < 13`), `app_database.g.dart` (`MessagesTableData.hashCode`), `message_repository_impl.dart` (`ssePinDeleteCompanion`), `test/grep_gates_test.dart` ("bug wave 1").
