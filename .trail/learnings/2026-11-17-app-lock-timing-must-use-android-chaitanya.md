---
title: "App lock timing must use Android's time-since-boot clock, because the wall clock can be moved and Dart's stopwatch stops while the phone sleeps"
author: Chaitanya
date: 2026-11-17
branch: main
cost: { minutes: 1, tokens: 1709 }
id: l-b35e23cb
scope: repo
status: active
src: agent
touches:
  - lib/features/app_lock/app_lock_controller.dart
  - lib/app.dart
---

## Decided
Both app-lock timers (the PIN wait after wrong tries, and "lock after being away") should be measured with Android's SystemClock.elapsedRealtime(), read through the existing privacy method channel. It counts sleep and the user cannot set it. It restarts at boot, so a reboot during a PIN wait restarts the wait at full length rather than trusting the wall clock.

## Tried and ruled out
Dart's Stopwatch as the tamper-proof clock: on Android it uses CLOCK_MONOTONIC, which stops while the phone is asleep. A phone left with the screen off for 10 minutes counts only its awake seconds, so "lock after 5 min" would stop locking.

## Watch out
Any wall-clock comparison in the lock can be beaten by moving the phone's clock: back by the time away skips the away lock with no PIN, and a clock moved far back also ends a PIN wait because a guard treats "more time left than the wait allows" as not waiting. Lock or wait logic must never rely on DateTime.now() alone.

In the code:
- lib/features/app_lock/app_lock_controller.dart: shouldLock, isWaiting, unlockWithPin, registerWrongAttempt
- lib/app.dart didChangeAppLifecycleState passes DateTime.now() to onHidden/onResumed
- MainActivity.kt "kuch_bhi/privacy" channel hosts platform helpers
- spec: docs/design/pages/client-security-wave2.md (F15)
