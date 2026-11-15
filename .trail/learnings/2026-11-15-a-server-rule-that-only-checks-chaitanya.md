---
title: "A server rule that only checks you are in some chat lets you read and edit every chat, so each rule must tie the membership to the row's own chat"
author: Chaitanya
date: 2026-11-15
branch: main
cost: { minutes: 72, tokens: 2596815 }
id: l-bdbe5eba
scope: repo
status: active
src: agent
touches:
  - docs/design/00-foundation.md
  - docs/design/pages/chat.md
  - docs/design/pages/motion-work-log.md
  - docs/design/pages/motion.html
  - docs/design/pages/motion.md
  - lib/core/theme/app_theme.dart
  - lib/core/theme/page_motion.dart
  - lib/core/theme/tokens.dart
  - lib/core/widgets/app_avatar.dart
  - lib/core/widgets/app_button.dart
---

## Decided
Live rules were tightened on 2026-11-15 (user go-ahead, device PASS). A rule like "a membership row exists for me" with no link to the row being read passed for anyone who was in any chat at all. It let any member list and rename every chat, list every membership and every read receipt, and forge a read receipt in someone else's name (which also starts that message's disappearing clock). Each rule now joins the membership to the row's own chat id, or the receipt to a message the caller sent, or the row's user to the caller.

## Tried and ruled out
- Receipts create limited to "recipient is me" only: the sender pre-creates an empty receipt for every other member on each send, so the rule also allows the message's sender, but only with delivered and read both empty.
- Dropping the "I created it" branch on reading a chat: a new chat has no member rows yet, so the creator must be able to read it.
- Re-running signed-in checks against the live server: it needs tokens for real accounts. The checks ran on two copies (old rules, new rules) with a throwaway token route; live was verified by comparing the rule set's hash with the tested copy.

## Watch out
- Any new collection or rule: never write a bare "member of some chat" condition. Test it as an outsider who is in other chats.
- The chat list is about 4x slower with the scoped rule (4 ms to 18 ms on 37 chats). Watch it if the server grows.
- The token route file is for test copies only; it must never go into the live hooks folder.
- The server's Python is 3.10: no backslashes inside f-string expressions in test scripts.
- Verification and change-email mails still link to the blocked admin path, like the reset mail did.

In the code:
- spec and log: docs/design/pages/server-rules.md, server-rules-work-log.md
- migration: docs/server/migrations/1794700100_updated_rules_scope.js (down step restores the old rules; tested)
- tests: docs/server/tests/rules_dry_run.sh, rules_request_table.py, tok.pb.js
- live backup: /home/ubuntu/pb_backups/data.db.20261115-rules-pre
- client call that needs the sender branch: lib/infrastructure/repositories/message_repository_impl.dart (receipt pre-create near "Receipt created for recipient")
