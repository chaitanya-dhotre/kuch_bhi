---
title: "A removed group member's phone locks the chat with a quick server re-check 5 seconds after the first miss, not a second full sync"
author: Chaitanya
date: 2026-11-14
branch: claude/fervent-noether-6c030c
cost: { minutes: 20, tokens: 90269 }
id: l-196a87fd
scope: repo
status: active
replaces: l-b9c19c2c
src: agent
touches:
  - docs/design/pages/removal-lock.md
  - lib/infrastructure/repositories/message_repository_impl.dart
  - test/offline/removal_reconcile_char_test.dart
---

## Decided
The false-removal guard still needs 2 confirmed misses (list miss + point query each). A removed phone gets exactly one sync trigger: the SSE delete of its own member row does reach it (device run 2026-11-14, Redmi logcat). So a held miss now sets one 5 s timer, and that re-check asks the server only about the held chats instead of running a full conversation sync. Device PASS 2026-11-14.

## Tried and ruled out
A full conversation sync as the re-check (round 1): it worked, but one full sync takes 5–15 s on the Redmi (cold start ~15 s) because it rewrites every chat's rows, so the lock took ~20 s. Lowering the guard to 1 miss: drops the protection against stale snapshots. A server push to the removed member: not needed, the SSE delete already arrives.

## Watch out
The re-check runs in the conversation-pass slot so it never overlaps a full sync; a chat left from this phone before the timer fires must be skipped, or it gets a false "You were removed" bubble. The lock still waits for the first full sync (~8 s); getting under 10 s would mean checking removals before that sync's per-chat rewrites. The verdict now logs "[Conv] removal confirmed for <id>".

In the code: lib/infrastructure/repositories/message_repository_impl.dart `_removalMiss`, `_removalRecheckPass`, `_scheduleRemovalRecheck`, `removalRecheckDelay`, `_convPasses(recheckOnly:)`; spec docs/design/pages/removal-lock.md
