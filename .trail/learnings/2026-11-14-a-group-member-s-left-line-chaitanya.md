---
title: "A group member's left line must be posted before their member row is deleted, and the joined guard only counts the current membership"
author: Chaitanya
date: 2026-11-14
branch: main
cost: { minutes: 18, tokens: 170322 }
id: l-ff04a1e4
scope: repo
status: active
src: agent
touches:
  - test/offline/group_rejoin_history_test.dart
---

## Decided
Found in the rejoin-history device check (2026-11-14, user PASS). Two group system lines never showed after a leave or re-add, both bugs older than that build:
- "X left the group" was posted after the leaver's member row was deleted (order set 2026-10-13 so a failed delete could not post a false "left"). The messages create rule needs a current member, so the server refused the post silently and only the leaver saw the line. Now: look up the member row, post the line, then delete. User accepted the trade-off: a "left" line can show if the delete alone fails right after a successful lookup (rare; the caller still gets the error).
- "X joined the group" is guarded against duplicates by an exact-body lookup. On a re-add it matched the line from the first membership and skipped the new one. The guard now only counts lines created since the current member row's join time.

## Watch out
Any new system line a member sends about themselves must go out while they are still a member. Lines about other members (removed by an admin) are sent by the admin, so they are unaffected.

In the code: message_repository_impl.dart leaveGroup (emit before conversation_members delete), _emitJoinedWhenKeyReady (since: my member row joinedAt); messages_dao.dart findSystemMessage `since`. Tests: test/offline/group_rejoin_history_test.dart.
