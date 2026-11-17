---
title: "A removed or departed group member loses the whole group, history included, once their phone is cleared or reinstalled"
author: Chaitanya
date: 2026-11-16
branch: main
cost: { minutes: 1, tokens: 0 }
id: l-d866ea02
scope: repo
status: active
src: agent
touches:
  - lib/infrastructure/repositories/message_repository_impl.dart
  - KUCH_BHI_PROJECT_BIBLE.md
---

## Decided
This comes from the design, not from the server-rules fixes. A fresh sign-in lists chats only from the user's own member rows. Removing someone or leaving deletes that row on the server. The messages and conversations rules also need current membership. So once the phone's local database is gone, nothing on the server leads back to the group or lets its history download. The old copy only ever lived on the phone. Letting a former member keep read-only history is a product decision that needs a spec (a "former member" cutoff on the server instead of a deleted row). It is not a client fix.

## Watch out
- Don't "fix" this by relaxing the members or messages list rules or the membership rules. A former member must never be able to rejoin or post that way.
- If a removed member was the group's creator, the conversations rule's creator branch still lists the chat row itself, but with no history. Expect that difference when testing.

In the code: the restore chat list is `_syncConversationsPass` in `lib/infrastructure/repositories/message_repository_impl.dart` (filter `user_id="$myId"` on `conversation_members`); removal deletes the row around `:4040-4066`; rules in `KUCH_BHI_PROJECT_BIBLE.md` §7.
