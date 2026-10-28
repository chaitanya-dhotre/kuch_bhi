---
title: "Reading a Flutter Android build failure: the log tail lies"
author: Chaitanya
date: 2026-10-28
branch: main
cost: { minutes: 179, tokens: 8787432 }
id: l-8bb3f5bb
scope: repo
status: active
src: agent
touches:
  - docs/backlog.md
  - lib/domain/repositories/message_repository.dart
  - lib/features/chat/chat_run_grouping.dart
  - lib/features/chat/providers/chat_provider.dart
  - lib/features/chat/screens/chat_screen.dart
  - lib/features/friend_requests/widgets/group_invite_card.dart
  - lib/features/friend_requests/widgets/request_card.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
  - test/chat_empty_kind_test.dart
  - test/offline/undecryptable_state_test.dart
---

## Decided

Assume a build SUCCEEDED until proven otherwise, because reading only the
tail of the log is how a passing build gets misread as a failure.

## Watch out

The Kotlin/AGP version gate looks like an abort but is not:
`errorKGPVersion = 2.2.20` and `errorAGPVersion = 8.11.1` are both compared
with a STRICT `<`, so a project sitting exactly on either number PASSES and
only gets the "will soon be dropped" warning. Do not bump them to "fix" a
build that already works.

Also: the debug APK lands in `build/app/outputs/flutter-apk/`, not
`build/app/outputs/apk/debug/` — looking in the wrong directory also reads
as "no APK was produced".

## In the code

android/settings.gradle.kts pins Kotlin 2.2.20 and AGP 8.11.1. Confirm a
verdict by grepping the full log for `BUILD FAILED` or `Built build/...apk`,
never by reading the last few lines.
