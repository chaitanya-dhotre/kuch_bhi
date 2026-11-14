---
title: "A removed group member's phone needs two conversation syncs to lock, and nothing schedules the second one"
author: Chaitanya
date: 2026-11-14
branch: claude/fervent-noether-6c030c
cost: { minutes: 4, tokens: 123022 }
id: l-b9c19c2c
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/removal-lock.md
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/infrastructure/services/group_create_service.dart
---

## Decided
Planning finding, 2026-11-14 (removal-lock spec, awaiting the user's PASS). The false-removal guard condemns a membership only after 2 separate sync passes that each find the row gone (list miss + point query). The removed phone gets at most one trigger after removal (probably the SSE delete of its own member row), so it logs "membership miss 1/2 … holding verdict" and then waits for a resume or restart. Miss counts are in memory, so a restart starts again at 1 (the ~1 min wait seen on the Redmi). Default fix: a pass that holds a confirmed miss sets one 5 s timer for a follow-up pass; the guard stays at 2.

## Tried and ruled out
Lowering the guard to 1 miss: drops the protection the task asked to keep. A server push alone: needs a live hook and does not fix the cold-start wait.

## Watch out
Whether the SSE delete event reaches a removed member is unverified (the conversation_members rules are not in the repo). The spec's device step 2 answers it from logcat. Group creation writes server member rows before local ones, so the old fresh-group race cannot trip a 5 s re-check.

In the code: lib/infrastructure/repositories/message_repository_impl.dart `_syncConversationsPass` reconcile loop, `_removalMissCounts`, `_removalConfirmMisses`; spec docs/design/pages/removal-lock.md
