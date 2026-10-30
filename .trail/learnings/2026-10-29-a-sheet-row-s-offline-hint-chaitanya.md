---
title: "A sheet row's offline hint must size to its longest line, or the row throws at large text"
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 34, tokens: 486721 }
id: l-f123f21e
scope: repo
status: active
src: agent
touches:
  - lib/core/theme/tokens.dart
  - lib/core/theme/app_theme.dart
  - lib/core/widgets/app_sheet.dart
  - lib/core/widgets/app_dialog.dart
  - lib/features/chat/widgets/reaction_picker.dart
  - lib/features/chat/widgets/attach_sheets.dart
  - lib/features/home/screens/add_friend_screen.dart
  - test/core/sheet_harness.dart
  - test/core/app_sheet_test.dart
  - test/core/app_dialog_test.dart
---

## Decided
The shared sheet row stays a ListTile (tests read its trailing Text), and the disabled row's "Available online" hint uses TextWidthBasis.longestLine.

## Tried and ruled out
- Plain trailing Text: at 200% text on a 360dp phone the hint wraps, and wrapped text takes the full parent width by default, so ListTile asserts "Trailing widget consumes the entire tile width" and the row is never laid out.
- Wrapping the trailing in Flexible/ConstrainedBox: breaks the existing menu test that casts ListTile.trailing to Text.

## Watch out
Any ListTile trailing Text that can wrap has the same assert. Only shows in a 360dp × 200% test, not at the default 800px.

In the code:
- lib/core/widgets/app_sheet.dart: SheetActionRow, disabled branch
- test/core/app_sheet_test.dart: "trailing value wraps at 360×200%"
