---
title: "Chat entrances are decided once per message id from the list, and the send flight lands by finding the bubble's own fill box"
author: Chaitanya
date: 2026-11-15
branch: main
cost: { minutes: 29, tokens: 450552 }
id: l-155e3c2a
scope: repo
status: active
src: agent
touches:
  - lib/core/theme/tokens.dart
  - test/core/motion_tokens_test.dart
  - lib/core/widgets/press_scale.dart
  - lib/core/theme/page_motion.dart
  - lib/core/widgets/change_motion.dart
  - lib/features/chat/widgets/bubble_entrance.dart
  - test/chat/motion_test.dart
  - test/core/motion_widgets_test.dart
  - docs/design/pages/motion-work-log.md
---

## Decided
- Motion pass (2026-11-15). Which rows animate in is decided from the whole message list, not in the list's item builder: the first list a chat screen sees is history (no entrance), a later new id among the newest two rows gets one, and a known id never replays, so refetch and resync re-emits stay still. Off-screen rows are never built, so a decision made in the builder would replay when they scroll into view.
- The send overlay (text grows out of the composer field) finds its target by walking the new row for the first background DecoratedBox with a colour and a radius: that is the bubble's fill, so the flight ends on the real rect, radius and colour without adding keys to the bubble widgets.
- Exit curves are used flipped: Flutter applies a reverse curve to the falling value, so an unflipped ease-in exit decelerates.

## Tried and ruled out
- Opacity wrappers that stay in the tree at opacity 1: several existing tests count Opacity widgets to check the offline dim and broke. Use FadeTransition (a different widget type) or no wrapper at rest.
- Interval end past 1.0 for a staggered fifth item: Interval asserts end <= 1; clamp it.

## Watch out
- With Android "Remove animations" on, Flutter already runs normal AnimationControllers at 5 % of their duration, so a 150 ms reduced-motion fade is ~8 ms on a phone. Tests that set the platform flag see the same.
- A `late int x = widget.field` initialiser runs on first read, which may be in didUpdateWidget with the new widget; set it in initState.
- AlbumScreen's layout test measures the page on the push's first frame, so it encodes the page transition's start offset (24 dp now).

In the code: lib/features/chat/widgets/bubble_entrance.dart (ChatEntrances, BubbleEntrance), lib/core/widgets/change_motion.dart, lib/core/theme/page_motion.dart, docs/design/pages/motion-work-log.md.
