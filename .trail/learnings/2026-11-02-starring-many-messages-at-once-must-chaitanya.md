---
title: "Starring many messages at once must pace the server writes, because a refused unstar comes back on the next sync"
author: Chaitanya
date: 2026-11-02
branch: main
cost: { minutes: 1, tokens: 1657 }
id: l-2c18c91e
scope: repo
status: active
src: agent
touches:
  - lib/infrastructure/repositories/message_repository_impl.dart
---

## Decided
Bulk star/unstar (12.8 multi-select spec) goes through one repo method that writes every row on the phone first, then sends the server writes one at a time in the background: star creates paced to at most 15 per 5 s, a 429 waits 5 s and retries up to 3 times. Unstar (a list + delete, not a create) isn't paced. The album menu's Star (up to 20 rows) should use it too.

## Tried and ruled out
Looping the single-message star toggle over the selection: each call fires its server write unawaited, so N stars hit the server at once, and the server limits creates to 20 per 5 s, so a big selection gets 429s.

## Watch out
Star sync only ever adds stars: if the server holds a star record and the phone row isn't starred, the next sync stars it again. So an unstar whose server delete fails (offline, 429, error) comes back later, and a star whose create fails never reaches the server. Single stars have the same gap; the durable fix is sending stars through the outbox like reactions.

In the code:
- toggleStar: lib/infrastructure/repositories/message_repository_impl.dart ~2592-2650 (phone write, then unawaited create or list+delete)
- star sync re-adds: same file, _syncStarredMessages ~4745-4752 and _syncStarredMessagesUser ~4856
- rate limit: PocketBase `*:create` 20/5s (see the receipt-429 fix)
- spec: docs/design/pages/multi-select.md D6, decision 12, follow-up F-a
