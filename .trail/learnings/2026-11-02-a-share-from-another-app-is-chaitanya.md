---
title: "A share from another app is held by the chat's composer until a group's send rule settles, because group chats start unable to send"
author: Chaitanya
date: 2026-11-02
branch: main
cost: { minutes: 23, tokens: 369070 }
id: l-fb8a9c29
scope: repo
status: active
src: agent
touches:
  - lib/features/share/share_payload.dart
  - lib/services/share_in_service.dart
  - lib/features/share/share_target_screen.dart
  - test/share/share_payload_test.dart
  - test/share/share_harness.dart
  - test/share/share_in_service_test.dart
  - test/share/share_target_screen_test.dart
  - test/chat/message_input_share_test.dart
  - docs/design/pages/share-in-work-log.md
  - lib/features/chat/widgets/message_input.dart
---

## Decided
- The Send to picker is a plain pushed page on the root navigator, so the router can't replace it. It closes with the chosen chat and the share service then opens that chat, unless that chat is already the router's top page.
- The composer takes a handed-over share once and holds it. A group chat's composer starts with sending off for its first frames (members and key readiness are streams), so the share runs when sending turns on, and is dropped with "You can't send messages in this chat." after 5 s if it never does.
- The picker's own can-send check reads the repository directly (members stream first value, usable-key check, 3 s cap) instead of awaiting the auto-disposed providers.

## Tried and ruled out
- Clearing the share when the composer can't send on its first frame: every group share would be lost.
- pumpAndSettle in composer widget tests: the mic button's pulse repeats forever, so it never settles. Pump fixed steps.

## Watch out
- The composer's drafts are a static per-chat map that outlives a test; use a new chat id per test or text leaks between tests.
- Kotlin copies and clearShared share one single-thread executor, so a clear after a cancelled copy waits for the in-flight copy and never leaves a stray file.

In the code: lib/services/share_in_service.dart (_open, _checkNow), lib/features/share/share_target_screen.dart (_canSend, _pick), lib/features/chat/widgets/message_input.dart (_takeShare, _maybeRunShare, didUpdateWidget), MainActivity.kt shareIo; docs/design/pages/share-in-work-log.md.
