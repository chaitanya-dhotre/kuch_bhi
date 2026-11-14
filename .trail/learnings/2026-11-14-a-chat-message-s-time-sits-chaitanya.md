---
title: "A chat message's time sits on one line under its run, and a voice message's 36 levels ride in its encrypted body"
author: Chaitanya
date: 2026-11-14
branch: main
cost: { minutes: 7, tokens: 33113 }
id: l-704c5956
scope: repo
status: active
replaces: l-c0214366
src: agent
touches:
  - lib/features/chat/voice_body.dart
  - test/chat/voice_body_test.dart
---

## Decided
- Chat calm (2026-11-14): the time, ticks and star are one line drawn by the message row under a run's last bubble (every bubble in info mode). Bubble widgets draw content only; a new bubble kind must not add its own time. Corners depend on runStart.
- D-3 A: a voice body is the duration + one space + exactly 36 glyphs ▁…█. Every reader of a voice body must go through voiceBodyText/parseVoiceBody; no suffix or a bad one = generated bars. Chosen over a new server field because it needs no live change and stays encrypted.
- Placeholders breathe on one clock per SkeletonGroup, hidden for 300 ms; shimmer is gone.

## Watch out
- Phones on an older build show the bars after the duration ("0:12 ▁▃▅…").
- A new screen that shows a voice body must call voiceBodyText (test/chat/voice_body_test.dart checks the known readers).
- In widget tests a ChatBubbleFrame spans the row; measure its first Container, which includes the 12 dp own-side margin.

In the code: lib/features/chat/voice_body.dart, widgets/expiry_badge.dart, message_bubble.dart, core/widgets/skeleton.dart.
