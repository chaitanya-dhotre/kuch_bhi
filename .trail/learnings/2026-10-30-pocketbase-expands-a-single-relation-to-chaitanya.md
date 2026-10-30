---
title: "PocketBase expands a single relation to one object, so read it by dot path"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 3, tokens: 175287 }
id: l-fedad1b5
scope: repo
status: active
src: agent
touches:
  - docs/design/10-registry.md
  - docs/design/pages/sheets-work-log.md
  - docs/design/pages/sheets.html
  - docs/design/pages/sheets.md
  - lib/core/theme/app_theme.dart
  - lib/core/theme/tokens.dart
  - lib/core/widgets/app_dialog.dart
  - lib/core/widgets/app_sheet.dart
  - lib/features/chat/screens/chat_screen.dart
  - lib/features/chat/widgets/attach_sheets.dart
---

## Decided
Read expanded single-relation fields by dot path, e.g. `record.getStringValue('expand.user_id.display_name')`.
A single relation (maxSelect 1) expands to one object, not a list. `get<List<dynamic>>('expand.user_id')`
wraps that raw Map in a list, and calling `.getStringValue` on the Map throws. The old who-reacted
sheet hid this behind `catch (_) {}` and was always empty. A dot path also returns '' when an
API rule hides the expand.

## Watch out
Widgets may not import `package:pocketbase` (a grep gate blocks network SDK imports), so
`get<List<RecordModel>>` is not an option outside the repositories.

In the code: `reaction_bar.dart` `reactionDetailProvider`.
