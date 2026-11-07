---
title: "A disappearing message's clock starts when it is read, and the server, not the phone, fixes how long it lasts"
author: Chaitanya
date: 2026-11-05
branch: main
cost: { minutes: 23, tokens: 310958 }
id: l-cc18803f
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/disappearing.md
---

## Decided
- User, 2026-11-05 (spec PASS): the timer starts when a message is read, not when it is sent, so an unread message never disappears. Each phone counts from its own read. The sender's copy and the server copy count from the moment everyone has read it.
- The length is fixed once, by the server, when the message arrives. Phones copy it and never derive it from the chat's timer. Old messages have no length, so nothing can stamp them.
- Changing the timer or turning it off leaves sent messages as they are, including clocks already running. User's choice, and it replaces the backlog's "off clears stamps".
- First launch of the fixed build clears every local expiry once. They were all guesses, and no enable time was ever recorded.

## Tried and ruled out
- A per-chat "enable time" compared at ingest: a chat-level value cannot tell which timer a message was sent under, and cannot keep sent messages unchanged when the timer changes.
- Fixing expires_at at arrival (arrival + timer): simplest, but an unread message would be deleted, which is what the user objected to.
- Keeping one server expiry that phones copy: a phone offline past the read or the delete never learns it. Own read time and receipts are always available to the phone.
- Saving the message record when its clock starts: that broadcasts, and phones re-ingest the row. The hook uses direct SQL.

## Watch out
- The server never deleted anything before this. No client set messages.expires_at (0 of 633 rows), so the 2026-10-12 "server hard-deleted the history" conclusion was wrong: the loss was phone-only. The scroll-up test was void because the chat declares history exhausted when it has fewer rows than its offset, without calling the server.
- A date bound into a PocketBase filter as an ISO string compares as text against stored dates: stored has a space, ISO has a T, and the space sorts first. A row expiring later the same UTC day matches. Use @now. The media expiry cron has the same flaw.
- The message SSE handler never checked the action, so a server delete re-ingested the dead record. It ignores deletes now.
- A new column must be carried by every full-row rebuild, because the ingest commit is delete-then-insert.

In the code:
- Spec: docs/design/pages/disappearing.md.
- message_repository_impl.dart: _companionFromRecord, markConversationRead, _updateMsgReceiptStatus, onMessageEvent, _disappearAfterOf. messages_dao.dart: startClockOnIncoming, startClockOnRow.
- Server: messages.disappear_after, pb_hooks/disappearing_stamp.pb.js, disappearing_messages.pb.js.
