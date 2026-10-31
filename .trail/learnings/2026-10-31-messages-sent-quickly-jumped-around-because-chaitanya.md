---
title: Messages sent quickly jumped around because the ack re-stamps with the later server time and same-second ties fell to random ids
author: Chaitanya
date: 2026-10-31
branch: main
cost: { minutes: 9, tokens: 167276 }
id: l-2bcc54b1
scope: repo
status: active
src: agent
touches:
  - test/offline/burst_send_order_test.dart
  - lib/core/utils/op_id.dart
  - lib/data/local/database/daos/messages_dao.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
---

## Decided
- A still-queued text send is lifted to the server time of an ack that just landed (it will be created on the server later anyway), in the same transaction as the ack, so the acked message never overtakes it. Only rows with no serverId are lifted, so the server-time-only watermark rule holds.
- Same-second ties (drift stores createdAt in whole seconds) break on serverId, and op ids (which become the server id) now start with a per-process monotonic millisecond prefix, so they sort in send order and the same on every device. Unsent rows (null serverId) sort newest, then rowid = insertion = send order.

## Tried and ruled out
- Storing createdAt in milliseconds: needs a schema migration and a converter on a core column, and still would not stop the ack jump (server time = device send time + latency).
- rowid as the tiebreak for every row: a fetched page arrives newest-first, so same-second incoming messages would be shown reversed.
- Sorting all unsent rows below everything: a long media upload would sit at the bottom and jump back up at its ack.

## Watch out
- Server time of message 1 is later than the device time of message 2 whenever the user types faster than one send round trip, even with perfect clocks. Any new ack path (media at create ack) should lift queued texts the same way.
- Media message creates don't pass an id, so their server ids are random; same-second ties next to them are random but the same on every device.

In the code:
- lib/core/utils/op_id.dart (generateOpId), MessagesDao.liftQueuedTextSends and the orderings in lib/data/local/database/daos/messages_dao.dart and conversationLastMessageProvider
- calls in _sendTextOp ack txn and resolveDuplicateSend (lib/infrastructure/repositories/message_repository_impl.dart)
- test/offline/burst_send_order_test.dart (2026-10-31)
