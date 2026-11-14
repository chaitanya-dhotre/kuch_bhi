---
title: "A restore that loses the connection waits for it instead of skipping chats, and group-key walks are shared per group"
author: Chaitanya
date: 2026-11-14
branch: main
cost: { minutes: 20, tokens: 317195 }
id: l-5f5c9bb5
scope: repo
status: active
src: agent
touches:
  - lib/services/encryption_service.dart
  - lib/features/auth/screens/backup_pin_screen.dart
  - test/auth/restore_overlay_test.dart
  - test/offline/restore_rev2_test.dart
  - docs/design/pages/restore-rev2-work-log.md
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/domain/repositories/message_repository.dart
---

## Decided
Restore rev 2 (built 2026-11-14, spec PASS all defaults, device check pending). The history sync keeps a chat for later when it fails with no HTTP answer (status 0) or a 429; offline it pauses on the restore screen (Finish later goes Home, the sync carries on), online it gets 2 retry rounds 15 s apart. Each chat's key, receipts and page 1 go out together, tick members come from local rows, and deleted/starred are fetched once for the whole account at the end. The conversations step is 1 request for memberships plus 1 per 40 chats for members, single-flight with one trailing pass. No join rotation when the phone sees a conversation's members for the first time. One group-key walk per group at a time; background refreshes skip a group walked in the last 60 s; no prefetch while the history sync runs.

## Watch out
`future.whenComplete(() => map.remove(id))` returns the removed Future, and whenComplete awaits a returned Future: if the map holds that same future, it waits on itself forever. Every group-key test hung until the callback got a block body.
A 403/404 chat is skipped, never retried. Receipts failing while page 1 works still leave that chat's ticks at `sent`, as before.
PocketBase 0.37.5 caps a filter at 3500 characters and 200 expressions (tools/search/provider.go); 40 conversation ids per `||` filter is about 1500.

In the code: lib/infrastructure/repositories/message_repository_impl.dart (syncAllHistory runChat/pass, _syncConversations/_convPasses/_syncConversationsPass, _tickIndex members:), lib/services/encryption_service.dart (_sharedGroupKeyWalk, _walkGroupKeys, groupKeyFreshFor), lib/features/auth/screens/backup_pin_screen.dart (RestorePhase.waitingForNetwork, offlineRestoreLine). Log: docs/design/pages/restore-rev2-work-log.md.
