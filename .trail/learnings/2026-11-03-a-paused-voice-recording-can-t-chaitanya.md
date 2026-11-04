---
title: "A paused voice recording can't be played back, so listening ends it; the recorder plugin already pauses itself on calls"
author: Chaitanya
date: 2026-11-03
branch: main
cost: { minutes: 10, tokens: 228874 }
id: l-49bdd1bb
scope: repo
status: active
src: agent
touches:
  - docs/backlog.md
  - docs/design/pages/voice-recorder.md
  - docs/design/pages/voice-recorder.html
  - lib/features/chat/widgets/message_input.dart
  - lib/features/chat/widgets/voice_message_bubble.dart
---

## Decided
(Proposed in the 12.6 voice recorder spec, 2026-11-03, awaiting the user's spec PASS.) Pause and resume use the
recorder plugin's own pause()/resume(), which keep one file. The recording is AAC in an MP4 container, and that file
can't be played until recording stops, so the paused panel offers "Stop and listen", which ends the recording.
The waveform comes from getAmplitude() on one 100 ms timer, the same timer that drives the clock. The plugin's own
amplitude stream is just a periodic timer making that same call, and one timer runs under the widget-test clock.

## Tried and ruled out
Letting you listen and then keep recording (WhatsApp style): that means joining audio files, which needs a new
package. Ruled out.

## Watch out
- The plugin already pauses on audio-focus loss (a call, an alarm, another recorder; its default
  audioInterruption is pause) and reports it on onStateChanged. Nothing in the app listened, so a hold that got
  interrupted, or one that outlived a Home press, recorded silence.
- The first mic press opens the permission dialog while the finger is down. Release lands during the dialog, and
  on "Allow" recording started with no finger on the mic. Check the permission status first; never record from the
  press that asks.
- The hold gesture's pointer is followed after the mic row is swapped out. Phase 2 tracks it with one Listener on
  the composer panel, which stays mounted.

In the code: lib/features/chat/widgets/message_input.dart (_startRecording, _RecordingRow, _VoicePreviewRow);
record 6.2.0 lib/src/record.dart pause/resume/getAmplitude/onStateChanged; record_android AudioRecorder.kt
requestAudioFocus; Android amplitude = dBFS, floor -160 (PCMReader.kt). Spec: docs/design/pages/voice-recorder.md.
