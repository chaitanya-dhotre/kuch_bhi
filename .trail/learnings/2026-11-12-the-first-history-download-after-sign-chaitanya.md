---
title: The first history download after sign-in is slow mainly because every own message looks up its ticks with three network calls in a row
author: Chaitanya
date: 2026-11-12
branch: main
cost: { minutes: 7, tokens: 174946 }
id: l-76614240
scope: repo
status: active
src: agent
touches:
  - docs/design/feedback-2026-11-plan.md
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/services/encryption_service.dart
  - lib/features/auth/screens/backup_pin_screen.dart
  - docs/design/00-foundation.md
---

## Decided
Planning finding (2026-11-12, friends reported ~5 min restore on mobile data). The main cost of the restore/history sync is the tick status lookup for each OWN message on a fresh install: three sequential server requests per message (receipts, the message again, member list). At ~200 ms per round trip, 500 own messages is about 5 minutes. Proposed fix (not built yet): compute tick status once per conversation (one receipts query by conversation + one member list), same rules in memory, shared by the history path and the normal catch-up batch path.

## Watch out
- The same per-message lookup also runs in the normal catch-up batch, so a phone that was offline a long time pays it too.
- History sync also decrypts each message through its own compute() isolate and commits one row at a time; the batch path (one decrypt isolate and one commit per page) already exists but history sync doesn't use it.
- Home only opens after ALL history is downloaded.
- Estimate is from code reading only; confirm with timing logs on a test-account sign-in before and after.

In the code:
- syncAllHistory: lib/infrastructure/repositories/message_repository_impl.dart:3312 (sequential per chat, awaits each row)
- per-own-message lookup: _cacheMsgInner :5346 -> _computeSenderStatus :5730; also _cacheMessagesBatch :4679
- per-message isolate: lib/services/encryption_service.dart:305 decryptMessage -> compute()
- restore caller goes Home only after sync: lib/features/auth/screens/backup_pin_screen.dart:372-427
- plan: docs/design/feedback-2026-11-plan.md item 4 (S1-S5)
