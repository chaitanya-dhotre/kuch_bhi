---
title: "A settings row's trailing value must be flexible and end-aligned, or it overflows at large text or sits mid-row"
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 18, tokens: 113694 }
id: l-a5052a26
scope: repo
status: active
src: agent
touches:
  - docs/design/10-registry.md
  - docs/design/pages/captures/settings-board-desktop.png
  - docs/design/pages/captures/settings-board-phone.png
  - docs/design/pages/settings-work-log.md
  - docs/design/pages/settings.html
  - docs/design/pages/settings.md
  - lib/core/widgets/page_app_bar.dart
  - lib/core/widgets/settings_tile.dart
  - lib/features/profile/screens/crop_photo_screen.dart
  - lib/features/profile/screens/edit_profile_screen.dart
---

## Decided
A text value in a settings row's trailing slot (version, counts, status) is wrapped as Flexible + Align(centerEnd). Flexible lets it shrink and wrap at 200% text; Align pins it to the row end.

## Tried and ruled out
- Fixed trailing Text (the shared row's default): at 200% text on a 360dp phone the row overflowed (79px with a version like "1.0.12 (34)").
- Bare Flexible + textAlign.end: no overflow, but next to the row's Expanded title the Flexible gets half the row and the text takes only its own width at the START of that half, so it sat mid-row on device. textAlign has nothing to align within.

## Watch out
Widget tests at the default 800px width and 1x text show neither bug. Pin the value's right edge (row end = screen width − list inset − tile padding) and add a 200%-text, 360dp test.

In the code:
- lib/core/widgets/settings_tile.dart: title is Expanded, trailing is placed as-is
- lib/features/settings/screens/about_screen.dart: Version row trailing = Flexible(child: Align(alignment: AlignmentDirectional.centerEnd, child: value))
- test/settings/about_screen_test.dart: "version value sits at the row end" (expects 800 − 12 − 16 = 772) and "G3: 200% text on a 360dp phone"
