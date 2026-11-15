---
title: "A message that flies from the composer must be drawn with the app's text style and must find its bubble by a mark, not by guessing"
author: Chaitanya
date: 2026-11-15
branch: main
cost: { minutes: 31, tokens: 544960 }
id: l-d9a884a0
scope: repo
status: active
src: agent
touches:
  - docs/design/00-foundation.md
  - docs/design/pages/chat.md
  - docs/design/pages/motion-work-log.md
  - docs/design/pages/motion.html
  - docs/design/pages/motion.md
  - lib/core/theme/app_theme.dart
  - lib/core/theme/page_motion.dart
  - lib/core/theme/tokens.dart
  - lib/core/widgets/app_avatar.dart
  - lib/core/widgets/app_button.dart
---

## Decided
- The send flight is drawn in the app's top-level overlay, which has no Material above it, so its text must sit inside a transparent Material and take the row's text style. Without that, Flutter draws its debug text style (yellow underline, monospace), and the wider font wraps the text differently than the bubble does.
- Voice notes, stickers and emoji-only texts fly a picture of their own bubble, taken on the row's first frame. The row draws at near-zero opacity and about 1 dp tall for that frame, because a list doesn't paint a row of zero height, and a fully transparent row isn't painted either.
- The bubble frame marks its own box (a MetaData tag) and the flight looks for that mark. The margin sits outside the marked box.
- Stickers are decoded at chat size when the sticker sheet opens. The sheet shows them smaller, so they are cached as a different image, and the chat-size one would otherwise not be ready on the row's first frame.

## Tried and ruled out
- Finding "the first box narrower than the row": it picked the hidden swipe-to-reply arrow (22 dp, at the left), so an invisible icon flew and stickers seemed not to animate.
- Animating the real bubble from the composer up to its place: the list clips anything outside its area, and the composer sits below it.

## Watch out
- A text placed in a fixed-size box gets stretched to that box's height; the flying text needs a loose height (OverflowBox minHeight 0).
- Hero flights also run in that overlay: a Hero whose child holds text needs a Material inside it.

In the code: lib/features/chat/widgets/bubble_entrance.dart (_textFlight, _shotFlight, _visualRect), ChatBubbleFrame.box in expiry_badge.dart, precacheChatStickers in sticker_widgets.dart, ChatHero in app_avatar.dart. Device recordings and numbers: docs/design/pages/motion-work-log.md.
