---
title: "PocketBase expands a single relation to one object, so read it by dot path"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 31, tokens: 165285 }
id: l-f1d6fe42
scope: repo
status: active
replaces: l-fedad1b5
src: agent
touches:
  - test/offline/reactions_offline_test.dart
  - lib/features/chat/widgets/reaction_bar.dart
---

## Decided
Read expanded single-relation fields by dot path, e.g. `record.getStringValue('expand.user_id.display_name')`.
A single relation (maxSelect 1) expands to one object, not a list: `get<List<dynamic>>('expand.x')`
wraps the raw Map in a list, and `.getStringValue` on that Map throws. A dot path also returns ''
when an API rule hides the expand.

## Watch out
Widgets may not import `package:pocketbase` (a grep gate blocks network SDK imports outside the
repositories), so `get<List<RecordModel>>` is only an option there.

In the code: none left using it (the who-reacted sheet now reads Drift); applies to any new expand.
