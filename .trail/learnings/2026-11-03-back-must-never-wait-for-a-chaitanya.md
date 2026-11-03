---
title: "Back must never wait for a server write, and presence writes go out one at a time so a late leave can't undo the next chat"
author: Chaitanya
date: 2026-11-03
branch: main
cost: { minutes: 9, tokens: 52942 }
id: l-de3b49ef
scope: repo
status: active
src: agent
touches:
  - lib/core/router/app_router.dart
  - lib/features/auth/providers/encryption_sync_provider.dart
  - test/auth/sync_route_test.dart
  - android/app/src/main/kotlin/com/chai/kuch_bhi/MainActivity.kt
  - android/app/src/main/res/values-night/styles.xml
  - android/app/src/main/res/values/styles.xml
  - docs/design/pages/app-lock-work-log.md
  - docs/design/pages/app-lock.html
  - docs/design/pages/app-lock.md
  - lib/app.dart
---

## Decided
Closing a chat (system back, gesture or the back arrow) pops right away; the "left the chat" presence write runs in the background. Presence writes are chained so they reach the server in the order they were made, and leaving chat A is skipped once chat B has been entered.

## Tried and ruled out
Awaiting the leave write before popping (the code since May 2026): on bad mobile data (Airtel LTE, TLS handshakes failing, 8 s timeouts elsewhere) the write took ~10 s, so back looked dead while typing and scrolling still worked. It was reported as an app-lock bug and looked random because on a good connection the write takes a fraction of a second; ~50 tries on a good connection never reproduced it. The user's note of the time (13:12) and a logcat taken before killing the app found it.
Just popping without ordering: a slow "left A" could land after "entered B" and clear current_chat, so the other phone loses "In chat" and read handling breaks. The chat's own dispose already fires a leave late, so this race existed before.

## Watch out
Any UI action that awaits a network call before navigating will look like a freeze on slow data. The presence queue means one hung write delays later presence writes (they still land in order); there is no request timeout on them.

In the code: lib/services/presence_service.dart (_patch chains on _writes; _currentChat guards leaveChat); lib/features/chat/screens/chat_screen.dart PopScope onPopInvokedWithResult and the app-bar BackButton. Tests: test/offline/presence_write_order_test.dart, test/chat/chat_back_test.dart (both mutation-checked).
