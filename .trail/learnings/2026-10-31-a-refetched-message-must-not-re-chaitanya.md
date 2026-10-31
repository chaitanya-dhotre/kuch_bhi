---
title: "A refetched message must not re-badge: stored times are whole seconds, server times have milliseconds"
author: Chaitanya
date: 2026-10-31
branch: main
cost: { minutes: 14, tokens: 199796 }
id: l-bb46b14e
scope: repo
status: active
src: agent
touches:
  - test/offline/refetch_churn_test.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
  - docs/audits/bug-wave-3-work-log.md
  - docs/backlog.md
---

## Decided
The unread badge for an incoming message compares times at second precision. A message in the same second as the conversation's last message badges only if it was not already stored before this fetch. A refetch whose decrypt misses again keeps the earlier "key missing" or "failed" verdict instead of resetting it to "pending". A sender's receipt status is written only when it changes.

## Tried and ruled out
- Skipping the badge for any message already stored locally: background push notifications store the row without badging and rely on the next fetch to badge it, so those badges would be lost.
- Skipping every same-second message (the first fix): a reply landing in the same second as your own send never badged. The independent review caught it.

## Watch out
- The resync deliberately refetches messages it could not decrypt, as retries. Anything that runs per fetched row (badge, preview, verdict) must be safe to repeat. A group whose newest message can't be decrypted shows it first: its unread went up on every resync, and its preview flipped from "Can't decrypt" to a skeleton that never resolved.
- Every drift write re-emits the whole message list, even one that writes the same value. Writing an unchanged status was what flooded the open chat with list emits.

In the code:
- `_bumpConversationForIncoming(..., wasStored:)`, `_ingestDecryptState(existing:, record:)` and `_updateMsgReceiptStatus` in lib/infrastructure/repositories/message_repository_impl.dart
- drift stores DateTime as unix seconds (no build.yaml override); PocketBase `created` carries ms
- tests: test/offline/refetch_churn_test.dart (backlog 13.2, 13.3; 2026-10-31)
