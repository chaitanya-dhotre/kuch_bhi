---
title: "Read rules that combine two membership checks must use back-relations, because two @collection joins with OR get slow as the joined table grows"
author: Chaitanya
date: 2026-11-17
branch: main
cost: { minutes: 21, tokens: 383113 }
id: l-8e3362f0
scope: repo
status: active
src: agent
touches:
  - docs/server/migrations/1794800000_former_members.js
  - docs/server/hooks/former_member_record.pb.js
  - docs/server/tests/fm.pb.js
  - docs/server/tests/former_request_table.py
  - lib/infrastructure/repositories/message_repository_impl.dart
  - test/offline/former_groups_test.dart
  - docs/server/tests/former_dry_run.sh
  - docs/design/pages/former-member-history-work-log.md
  - docs/server/tests/former_rule_timing.py
  - docs/server/tests/former_timing_run.sh
---

## Decided
In PocketBase 0.37.5 read rules, write membership checks as back-relations (`conversation_id.conversation_members_via_conversation_id.user_id ?= @request.auth.id`), not `@collection` pairs, whenever a rule ORs two membership-style branches. Dry run 2026-11-17 on a copy of live: messages list of 2,000 rows went 5 s (two @collection branches) -> 115 ms (two back-relation branches); the old single @collection member rule was 183 ms. Same meaning, T1–T16 and U/V tables unchanged.
Same-row checks hold for both forms: `?>=` on `@collection.former_members.history_until` and on `..._via_...history_until` both kept the per-row time limit (check F3).

## Tried and ruled out
- `@collection.X || @collection.Y`: cost grows with the joined collection's total size (476 ms with few former rows, 5 s with 31), not with this chat's rows.
- Alias (`:fm`) or putting the cheap branch first: no change.
- Back-relation only on the new branch (old member branch kept as @collection): still 3x slower than before.

## Watch out
Time any new `||` branch on a copy with the joined collection populated across many chats; a near-empty table hides the blow-up.

In the code: docs/server/migrations/1794800000_former_members.js, docs/server/tests/former_rule_timing.py, docs/design/pages/former-member-history-work-log.md
