---
title: On the Samsung M52 only vibrate() reaches the motor; the lighter haptic types are dropped even with touch vibration on
author: Chaitanya
date: 2026-11-04
branch: main
cost: { minutes: 9, tokens: 516136 }
id: l-3c1c09d3
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/voice-recorder.md
  - docs/design/pages/voice-recorder-work-log.md
  - lib/features/chat/widgets/message_input.dart
  - test/chat/voice_recorder_test.dart
---

## Decided
The voice recorder's haptics use HapticFeedback.vibrate(), from one helper, with a test pinning it. It's the only type confirmed on both the M52 and the Redmi. Other screens still use mediumImpact and are silent on the M52 (spec follow-up F-d).

## Tried and ruled out
Blaming the phone's touch vibration setting alone: it was off on the M52, and turning it on changed nothing. It's necessary, not sufficient.

## Watch out
- Don't argue from one setting. Android logs every vibration: `adb shell dumpsys vibrator_manager`, section "Previous vibrations for usage TOUCH", look for `opPkg: com.chai.kuch_bhi`. If a haptic isn't there, it never reached the motor. The list holds about 50 entries.
- The M52's adb wireless serial contains spaces; quote it, and don't parse `adb devices` with awk's $1.
- Why the phone drops them isn't established. Its vibrator reports no effects and no amplitude control. vibrate() may feel stronger on phones that honour the light types.

In the code: lib/features/chat/widgets/message_input.dart _voiceHaptic; test 50 in test/chat/voice_recorder_test.dart. Flutter's mapping: PlatformPlugin.java vibrateHapticFeedback.
