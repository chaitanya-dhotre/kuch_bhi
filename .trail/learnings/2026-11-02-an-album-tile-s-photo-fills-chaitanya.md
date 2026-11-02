---
title: "An album tile's photo fills the box the album gives it, and its tests use a photo shaped unlike the tile"
author: Chaitanya
date: 2026-11-02
branch: main
cost: { minutes: 29, tokens: 502200 }
id: l-4c30456b
scope: repo
status: active
src: agent
touches:
  - lib/features/chat/widgets/image_message_bubble.dart
---

## Decided
In tile mode (album bubble in the chat, collage tiles) the photo bubble fills whatever box the album sizes for it, cropped with BoxFit.cover. The album decides the shape (180dp-high tiles clamped to [100, bubble − 40] wide; collage rects capped at 2:1 / 4:5), not the photo.

## Tried and ruled out
Reusing the single photo bubble's own sizing inside the tile (maxWidth 210 + AspectRatio of the photo in a loose Stack): any tile whose shape differs from the photo letterboxes. On the device, wide photos in the chat tiles left the bubble colour showing below them, and collage photos stopped at 210dp with black gaps.

## Watch out
The first tests passed on the bug because every test photo had exactly the tile's shape (3:4 into a 135×180 tile). A layout test for tiles must use a photo whose aspect differs from the tile and assert the photo's rect equals the tile's rect.

In the code: lib/features/chat/widgets/image_message_bubble.dart (tile mode = onTileTap != null → StackFit.expand), test/chat/album_bubble_test.dart and test/media/album_screen_test.dart fill checks. The video bubble already used StackFit.expand.
