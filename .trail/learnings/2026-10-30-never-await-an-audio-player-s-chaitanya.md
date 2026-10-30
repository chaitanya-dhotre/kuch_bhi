---
title: "Never await an audio player's play(): it finishes only when playback stops"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 14, tokens: 192140 }
id: l-7a578542
scope: repo
status: active
src: agent
---

## Decided
Start playback without awaiting it (`unawaited(player.play())`). With just_audio, `play()` returns a
future that completes when playback pauses or ends, not when it starts. Awaiting it inside a
try/finally that clears a loading flag keeps the spinner up for the whole clip, and the pause icon
never shows. That was the bug the user saw on device (2026-10-30).

## Watch out
Use `playerStateStream` (playing / processingState) for the icon, never the play() future.

In the code: `voice_message_bubble.dart` `_togglePlay`, `media_docs_screen.dart` `_VoicePlaySheet._init`.
