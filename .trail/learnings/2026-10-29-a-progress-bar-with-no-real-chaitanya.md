---
title: "A progress bar with no real value must hide its own screen-reader value, because Flutter only accepts a number there"
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 41, tokens: 863536 }
id: l-8dfed850
scope: repo
status: active
src: agent
touches:
  - android/app/src/main/res/drawable-v21/launch_background.xml
  - android/app/src/main/res/drawable/launch_background.xml
  - android/app/src/main/res/values-night/colors.xml
  - android/app/src/main/res/values-night/styles.xml
  - android/app/src/main/res/values/colors.xml
  - android/app/src/main/res/values/styles.xml
  - docs/design/10-registry.md
  - docs/design/pages/auth-work-log.md
  - docs/design/pages/auth.html
  - docs/design/pages/auth.md
---

## Decided
When reduce motion parks the restore bar at a fixed 30%, the bar's own semantics are excluded and a wrapping Semantics announces "In progress". With a real fraction the bar reports its own percent.

## Tried and ruled out
Passing a word as the bar's semanticsValue: the semantics update throws (a progress bar's value must be a valid number) and the screen breaks. Letting it report 30% announces a fake number.

## Watch out
Only shows up with semantics on (tester.ensureSemantics / TalkBack); plain widget tests pass.

In the code: lib/features/auth/screens/backup_pin_screen.dart `_RestoreOverlayState._buildRestore`; test/auth/restore_overlay_test.dart "reduced motion parks…".
