---
title: "A router refresh rebuilds a screen without the data it was opened with, so screens that need it keep a copy"
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 41, tokens: 863536 }
id: l-d5bb8a6f
scope: repo
status: active
src: agent
touches:
  - android/app/src/main/res/drawable-v21/launch_background.xml
  - android/app/src/main/res/drawable/launch_background.xml
  - android/app/src/main/res/values-night/colors.xml
  - android/app/src/main/res/values-night/styles.xml
  - android/app/src/main/res/values/colors.xml
  - android/app/src/main/res/values/styles.xml
  - docs/design/10-registry.md
  - docs/design/pages/auth-work-log.md
  - docs/design/pages/auth.html
  - docs/design/pages/auth.md
---

## Decided
Google onboarding keeps the sign-in result it was opened with in a router-level cache and reads that when the route is rebuilt without it. With no copy at all it falls back to Login instead of crashing.

## Tried and ruled out
Reading the passed-in data directly in the route builder. Any auth state change (an error included) makes the router refresh, the route is rebuilt with no data, and the cast threw a red error screen ("type 'Null' is not a subtype of type 'GoogleAuthResult'") on a taken username. Hot reload hides it; only a full restart shows it.

## Watch out
Any route that needs data passed at navigation time has the same hole while the auth provider can change under it. A test that mounts the screen directly will not catch it; the proof test uses the real router.

In the code: lib/core/router/app_router.dart `_onboardingPrefill` + `resetOnboardingPrefill()`; test/auth/onboarding_router_test.dart.
