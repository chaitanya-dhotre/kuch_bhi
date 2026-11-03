---
title: "A long loading screen right after opening or unlocking is the startup backup check on a slow connection, not the app lock"
author: Chaitanya
date: 2026-11-03
branch: main
cost: { minutes: 30, tokens: 360369 }
id: l-59e8f381
scope: repo
status: active
src: agent
touches:
  - android/app/src/main/kotlin/com/chai/kuch_bhi/MainActivity.kt
  - android/app/src/main/res/values-night/styles.xml
  - android/app/src/main/res/values/styles.xml
  - docs/design/pages/app-lock-work-log.md
  - docs/design/pages/app-lock.html
  - docs/design/pages/app-lock.md
  - lib/app.dart
  - lib/core/router/app_router.dart
  - lib/data/local/database/tables/app_settings_table.dart
  - lib/features/app_lock/app_lock_controller.dart
---

## Decided
Diagnosed 2026-11-03 (app lock device test): "after unlocking it keeps loading for 10–12 s" is the cold-start splash. Once sign-in state settles, the key-sync check re-runs and makes one server read of the user's record. While it reloads, the router sends the user to the splash even though the previous answer was "key ok". On mobile data with failing TLS handshakes that one read took 6–19 s; the same server answered in 45 ms from a laptop. App lock only made the wait visible after unlocking. Left as is on the app lock change; a separate task was proposed to keep Home up when the reload already holds "key ok".

## Tried and ruled out
Blaming app lock work: none of it is on the network path at start (the lock reads one secure-storage entry before the app starts; the PIN hash runs in a background isolate).

## Watch out
Swiping the app away from Recents kills it, so every "unlock" in such a test is a cold start. Check logcat for "Killing ... remove task" before assuming a resume.

In the code: lib/features/auth/providers/encryption_sync_provider.dart (watches authProvider, calls tryHasPocketBaseBackup); lib/core/router/app_router.dart redirect logs "[RouterRedirect] ... syncLoading: true" → location "/". Measure with: adb logcat --pid=<pid> | grep -E "RouterRefresh|RouterRedirect".
