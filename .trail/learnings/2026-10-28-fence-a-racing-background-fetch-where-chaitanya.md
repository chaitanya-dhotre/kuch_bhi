---
title: "Fence a racing background fetch where it is PUBLISHED, not where it is stored"
author: Chaitanya
date: 2026-10-28
branch: main
cost: { minutes: 3771, tokens: 816796019 }
id: l-3d52143d
scope: repo
status: active
src: agent
touches:
  - docs/design/00-foundation.md
  - docs/design/10-registry.md
  - docs/design/pages/captures/chat-emulator-chat.png
  - docs/design/pages/captures/chat-emulator-dark.png
  - docs/design/pages/captures/chat-emulator-font-scale-1.3.png
  - docs/design/pages/captures/chat-emulator-reduced-motion.png
  - docs/design/pages/captures/chat-emulator-scroll-smoke.png
  - docs/design/pages/captures/chat-emulator-search-no-results.png
  - docs/design/pages/captures/chat-floating-dark.png
  - docs/design/pages/captures/chat-floating-home.png
---

## Decided

An action (accept/decline) and a background refresh race. The action
invalidates, which starts a new fetch; the older refresh is still in flight
and resolves with a payload captured BEFORE the action.

Evicting the handled row from the cache at action time does NOT fix this.
The stale payload republishes it anyway. Put the fence in the PUBLISH path
(discard the stale refresh outright) and additionally refuse to persist a
stale payload. Both, not either.

## Tried and ruled out

- Cache eviction at action time only: the row still came back, because the
  stale fetch republished and re-persisted it after the eviction ran.
- Fencing inside the load function only, returning the previous state: that
  returns the pre-action value, which is still the wrong row count.

## Watch out

A test that asserts on the FINAL state will pass while the bug is live. The
action's own rebuild converges on the correct list seconds later and hides
the transient. Record every publish the source makes (a listener filtering to
settled data states, since a loading state retains the previous value) and
assert none of them contain the resurrected row.

## In the code

Action generation counter bumped by all four actions; `_refresh` discards a
stale refresh; `_load` refuses to snapshot a stale payload. Both request
sources carry it via `refreshForTest()` as the reachable trigger.
