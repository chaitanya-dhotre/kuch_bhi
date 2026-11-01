---
title: "A zoomable photo keeps the zoom layer full-screen and clamps every move to the photo's own rectangle"
author: Chaitanya
date: 2026-11-01
branch: main
cost: { minutes: 6, tokens: 39503 }
id: l-5e72aa3d
scope: repo
status: active
src: agent
touches:
  - docs/audits/viewer-followups-work-log.md
  - docs/backlog.md
  - lib/features/chat/widgets/reply_quote.dart
  - lib/features/media/screens/media_viewer_screen.dart
  - test/chat/reply_quote_expired_test.dart
  - test/media/media_viewer_screen_test.dart
  - test/media/media_viewer_video_test.dart
  - docs/design/10-registry.md
  - docs/design/pages/media-send-handoff.md
  - docs/design/pages/media-send-work-log.md
---

## Decided
- The photo viewer's zoom layer fills the screen with the photo drawn contain-centred. After every controller change (pinch, pan, double-tap tween), the translation is clamped per axis: centred while the scaled photo is smaller than the screen, edges pinned to the screen edges once bigger. That is what stops zoom and pan from showing black past the photo.

## Tried and ruled out
- `InteractiveViewer(constrained: false)` with a child sized to the photo: it lays the child out at the top-left (its `alignment` only sets the scale origin), so the photo jumped to the top of the screen. Once zoomed, it also still panned into the black.

## Watch out
- A test that checks a layout flag or a SizedBox size can pass on this bug. Test the outcome instead: double-tap in the black band, drag hard both ways, and check that the photo's edges never come inside the screen.
- The clamp needs the photo's width and height; with no size known it falls back to no clamp.

In the code: `_clampZoom`, `_photoRect` and the LayoutBuilder around InteractiveViewer in media_viewer_screen.dart; test "zoom stays inside the photo; centred at 1x".
