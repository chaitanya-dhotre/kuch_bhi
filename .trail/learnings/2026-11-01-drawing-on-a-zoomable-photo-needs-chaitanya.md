---
title: "Drawing on a zoomable photo needs the zoom layer switched off while the draw tool is on, not just its pan and zoom disabled"
author: Chaitanya
date: 2026-11-01
branch: main
cost: { minutes: 40, tokens: 1670685 }
id: l-6a6644cf
scope: repo
status: active
src: agent
touches:
  - docs/backlog.md
  - docs/design/10-registry.md
  - docs/design/pages/media-send-handoff.md
  - docs/design/pages/media-send-work-log.md
  - docs/design/pages/media-send.html
  - docs/design/pages/media-send.md
  - lib/core/constants/app_constants.dart
  - lib/core/utils/op_id.dart
  - lib/data/local/database/app_database.dart
  - lib/data/local/database/app_database.g.dart
---

## Decided
While the editor's Draw tool is selected, the pinch-zoom layer ignores all touches, so one finger draws. Crop mode keeps pan/zoom.

## Tried and ruled out
Setting the zoom layer's pan and scale to disabled in Draw mode: its scale gesture recognizer still joins the gesture arena and wins a one-finger drag, so drawing only started with two fingers (found on the phones, not by tests).

## Watch out
Widget tests did not catch this; gesture-arena behaviour needs a device check. The editor's single transform still drives preview, touch mapping and export, so the ignored layer must keep its transform, not be removed.

In the code: lib/features/media/screens/media_edit_screen.dart, `IgnorePointer(ignoring: _tool == 'Draw', child: InteractiveViewer(...))`.
