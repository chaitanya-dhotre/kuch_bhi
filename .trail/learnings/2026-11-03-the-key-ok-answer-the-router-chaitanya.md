---
title: "The key-ok answer the router sees while sign-in is still loading is a placeholder, so it can't take a cold start to Home on its own"
author: Chaitanya
date: 2026-11-03
branch: main
cost: { minutes: 5, tokens: 116879 }
id: l-d8666a0e
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
On cold start the key-sync route first answers "key ok" while sign-in is still loading. That answer is a placeholder for "nobody signed in", not a check of the user's key. When sign-in settles the route reloads and keeps that placeholder as its previous value. The router now trusts a previous "key ok" during a reload only when it saw that answer for the same signed-in user, which keeps a profile save or a sign-in re-publish from bouncing the user through the splash. The cold-start wait itself is fixed in the route: on a device that holds a key, the one server read gets a 3 s budget. Past it the answer counts as unknown (Home, same as offline). A late "no backup" with setup due is published straight as needsSetup without another read.

## Tried and ruled out
A router-only change that trusts any previous "key ok" during a reload: on cold start that is the placeholder, so a reinstalled phone with no key would flash Home before Restore. Re-running the route on a late answer (invalidate): on a network that stays slow, every re-run times out again and reads again.

## Watch out
Only the key-holding branch has the budget. The no-key branch still waits on the server (5 tries) because there an unknown answer must not become a new key (K3).

In the code: lib/core/router/app_router.dart SyncRouteGate; lib/features/auth/providers/encryption_sync_provider.dart backupCheckBudget + check.timeout; tests in test/auth/sync_route_test.dart.
