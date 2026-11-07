---
title: "Pages keep their router data across a refresh through an in-memory codec, and a missing Conversation is handled in the page builder, not a redirect"
author: Chaitanya
date: 2026-11-07
branch: claude/competent-nobel-a7fd14
cost: { minutes: 1, tokens: 0 }
id: l-3ffa46a2
scope: repo
status: active
src: agent
touches:
  - lib/core/router/app_router.dart
---

## Decided
- Reproduced 2026-11-07 with the real router: after a push, a refresh rebuilds the stack from go_router's encoded copy, and with no extraCodec every non-JSON extra came back null. Both the chat and group settings threw the logcat error.
- The router has an in-memory codec: a token goes out, the same object comes back. A refresh keeps the page key, so the chat does not remount and typed text stays. It also fixes the FCM "already viewing this chat" check, which read a null extra after a refresh, and view profile. It removed the need for the saved onboarding prefill, which also kept a Google idToken in a static.

## Tried and ruled out
- A route-level redirect to Home for a null extra: go_router drops a redirect equal to the stack's base location, and a page pushed over Home has base /home. It does nothing and the builder still crashes. The fallback lives in the builder.

## Watch out
- A refresh loses the Future from go_router's push (flutter#128122), so a pop result never arrives if a refresh ran while the page was open. Use Navigator.push for a page whose result you await: that survives a refresh and returns its result.
- The codec keeps objects, not strings or numbers: a String or num extra throws in Expando.
- Widget tests that open a real drift database through the shared offline harness hang when it closes in fake time. Use AppDatabase.test() there.

In the code: lib/core/router/app_router.dart `_LiveExtraCodec`, `_backToHome`; test/chat/chat_route_refresh_test.dart; go_router 14.8.1 lib/src/configuration.dart L373-L392, lib/src/match.dart decoder.
