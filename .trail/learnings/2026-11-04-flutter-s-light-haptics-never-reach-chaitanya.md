---
title: "Flutter's light haptics never reach the motor on the Samsung M52, so the recorder calls the vibrator through a pinned package"
author: Chaitanya
date: 2026-11-04
branch: main
cost: { minutes: 8, tokens: 53090 }
id: l-7378ed45
scope: repo
status: active
replaces: l-3c1c09d3
src: agent
touches:
  - lib/features/chat/widgets/message_input.dart
  - test/chat/voice_recorder_test.dart
  - docs/design/pages/voice-recorder.md
  - docs/design/pages/voice-recorder-work-log.md
  - pubspec.yaml
---

## Decided
The voice recorder's haptics go through haptic_feedback, which calls Android's Vibrator directly, past the touch-haptic path Samsung drops (flutter/flutter#73987). The user chose it over HapticFeedback.vibrate(), which works but buzzes hard. Pinned to exactly 0.6.5: 0.7 and later need AGP 9, and this project is on 8.11.1. Errors are swallowed at the call site, because a haptic must never fail a recording.

## Tried and ruled out
- Blaming the phone's touch vibration setting: it was off on the M52, but turning it on changed nothing.
- Flutter's HapticFeedback.vibrate() alone: reaches the motor on the M52, but it is a long-press buzz, not the light tap the spec wanted.

## Watch out
- On the M52 the package takes its legacy path (only PRIMITIVE_NOOP, no amplitude control): a plain 55 ms buzz that ignores `usage`, so it fires even with touch vibration off, and light, medium and heavy feel the same.
- Don't argue from one setting. Android logs every vibration: `adb shell dumpsys vibrator_manager`, section "Previous vibrations for usage TOUCH", look for `opPkg: com.chai.kuch_bhi`. If a haptic isn't there, it never reached the motor. The list holds about 50 entries.
- The M52's adb wireless serial contains spaces; quote it, and don't parse `adb devices` with awk's $1.

In the code: lib/features/chat/widgets/message_input.dart _voiceHaptic; tests 50 and 51 in test/chat/voice_recorder_test.dart; pubspec.yaml pin.
