---
title: "A router refresh keeps a screen's data through the router's codec, so a screen no longer keeps its own copy"
author: Chaitanya
date: 2026-11-07
branch: claude/competent-nobel-a7fd14
cost: { minutes: 2, tokens: 18198 }
id: l-5d801476
scope: repo
status: active
replaces: l-d5bb8a6f
src: agent
touches:
  - lib/core/router/app_router.dart
  - test/auth/onboarding_router_test.dart
  - test/chat/chat_route_refresh_test.dart
---

## Decided
- Data passed at navigation time survives a router refresh through the router's in-memory codec, on every route. Read it directly in the route builder. The old rule, keep a copy per screen, was a workaround for one route; the same loss later drew the grey chat screen on the M52. The onboarding copy is gone, which also stops a Google idToken sitting in a static.
- A route with no data at all still needs a fallback: onboarding shows Login, chat and group settings go to Home.

## Tried and ruled out
- A per-screen copy: it has to be repeated on each route, and any route that skips it crashes on a refresh.

## Watch out
- Removing the codec brings back the crash on a taken Google username as well as the grey chat. A test that mounts a screen directly will not catch this; the proof uses the real router. Hot reload hides it; only a full restart shows it.

In the code: lib/core/router/app_router.dart `_LiveExtraCodec`; test/auth/onboarding_router_test.dart; test/chat/chat_route_refresh_test.dart.
