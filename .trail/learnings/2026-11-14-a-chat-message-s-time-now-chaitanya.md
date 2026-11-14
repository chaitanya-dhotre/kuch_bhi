---
title: "A chat message's time now sits on one line under its run, so no bubble draws its own time, and voice bars are generated until real levels have a home"
author: Chaitanya
date: 2026-11-14
branch: main
cost: { minutes: 25, tokens: 426891 }
id: l-c0214366
scope: repo
status: active
src: agent
touches:
  - lib/features/chat/widgets/message_bubble.dart
  - lib/core/widgets/skeleton.dart
  - lib/features/chat/screens/chat_screen.dart
  - test/chat/bubble_geometry_test.dart
  - test/chat/chat_calm_test.dart
  - docs/design/pages/chat-calm-work-log.md
  - lib/features/chat/widgets/expiry_badge.dart
  - lib/features/chat/chat_run_grouping.dart
  - lib/core/theme/tokens.dart
---

## Decided
- Chat calm (spec PASS 2026-11-14): the time, ticks and star live on one line drawn by the message row under a run's last bubble (or every bubble in info mode). Bubble widgets (text, emoji, sticker, media, voice, document, album) only draw content. A new bubble kind must not add its own time.
- Bubble corners depend on whether the bubble STARTS a run (runStart), not on whether it ends one; bubble widgets take runStart now.
- Voice bubbles use 36 bars generated from the message id (the same on both phones). A voice message's encrypted body is only its duration text ("0:12"), so real levels need either a suffix in that body (old builds would show it as text) or a new server field (a live PocketBase change, unencrypted). The user has not chosen yet.
- Loading placeholders breathe on one clock per SkeletonGroup and stay invisible (but sized) for 300 ms; the shimmer package is gone.

## Watch out
- In widget tests a ChatBubbleFrame's size is the full row (it aligns a box to its side); measure the first Container inside it, and that box includes the 12 dp margin on the bubble's own side.
- Photos are now taller (up to 1.25 × width), so tests that tap rows above a portrait test photo can find them off screen; use a landscape test photo.
- A video's size label comes from the server row's file_size, kept in the blob meta. Rows cached before this change have no size until they are fetched again.

In the code: lib/features/chat/widgets/expiry_badge.dart (ChatBubbleGeometry, ChatBubbleFrame, ChatBubbleTimestamp), message_bubble.dart (meta line, disc, reactions), voice_waveform.dart (generatedWaveLevels, bars), lib/core/widgets/skeleton.dart (SkeletonGroup), test/chat/chat_calm_test.dart.
