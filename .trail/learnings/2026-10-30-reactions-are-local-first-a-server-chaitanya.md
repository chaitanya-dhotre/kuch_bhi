---
title: "Reactions are local-first: a server read must never undo a reaction still in the send queue"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 31, tokens: 165285 }
id: l-b0e46ba2
scope: repo
status: active
src: agent
touches:
  - test/offline/reactions_offline_test.dart
  - lib/features/chat/widgets/reaction_bar.dart
---

## Decided
Reactions live in the local reactions table and go to the server through the outbox (kinds
`reaction_add` / `reaction_remove`); the local row id is the PocketBase record id, so a retry after a
lost answer hits our own id (400 → getOne → done). The UI only watches the local table; a server read
merges into it.

## Watch out
- A server read must keep every reaction op that is not `sent`. Read the queue BEFORE the request (an
  op sent during it still counts) and AGAIN inside the write transaction (an op queued during it
  counts too). Reading it only before deleted a reaction tapped mid-read, and its send was dropped
  silently.
- The outbox runs FIFO per conversation and a failedTerminal head blocks every later op, text sends
  included. So the reaction senders drop a refused op (400/403/404/413) themselves instead of leaving
  it terminal, and never return `deferred` for something that can't ever send.
- Undo cancels the queued add only when it was never tried (`attempts == 0`), decided inside the
  transaction. A tried add may have landed with its answer lost, so it gets a delete (404 = done).
- Guard the read's write with the session epoch: a read in flight across sign-out must not write the
  old account's rows after the wipe.

In the code: `message_repository_impl.dart` `addReaction`, `removeReaction`, `refreshReactions`,
`_sendReactionAddOp`, `_sendReactionRemoveOp`; tests in `test/offline/reactions_offline_test.dart`.
