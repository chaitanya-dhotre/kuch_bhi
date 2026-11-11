---
title: "In the capybara rig the first child draws in front, and chat search can hang forever if one message lookup fails"
author: Chaitanya
date: 2026-11-11
branch: main
cost: { minutes: 9, tokens: 210341 }
id: l-9fb5600d
scope: repo
status: active
src: agent
touches:
  - docs/design/mascot/search/apply_search.py
  - docs/design/pages/mascot.md
  - mascot/capy/scene.rml
  - lib/features/chat/screens/chat_screen.dart
---

## Decided
- To hold something over the Sit capybara's face (the X8b magnifying glass, spec mascot §H, drafted 2026-11-11), the near front paw moves to the top of its parent's child list. In this rig the first child draws in front and later children draw behind (the belly is listed before the body, the yuzu highlight before the yuzu). Nothing of the head overlaps the paw at rest, so the resting frame stays pixel-identical (0 px differ).

## Watch out
- Chat search shows 0/0 before it has finished: the counter only knows the match count, and the chat list stays on screen while the search runs. In a long chat the search looks up bodies one at a time (each may need a decrypt, capped at 2 s), so 0/0 can last many seconds.
- If one body lookup throws, the unawaited scan dies, onResults never runs and the "search pending" flag stays true for good. Any UI keyed on "still searching" must treat a throwing lookup like a timeout (no body), or it never ends.

In the code: mascot/capy/scene.rml (Sit: PawLHolder 0:154 before RootBone); docs/design/mascot/search/apply_search.py; lib/features/chat/screens/chat_screen.dart (_resolveSearchBody, ConversationSearchController._scan, the counter Text in the search bar).
