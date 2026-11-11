---
title: "The restore capybara shuts its eyes with lids drawn over any face, throws the key past its ear, and cuts to the vault pose under reduced motion"
author: Chaitanya
date: 2026-11-11
branch: main
cost: { minutes: 14, tokens: 287480 }
id: l-73a4a8e3
scope: repo
status: active
src: agent
touches:
  - docs/design/mascot/k1/apply_k1.py
  - docs/design/pages/mascot.md
  - lib/features/mascot/capy.dart
---

## Decided
(Proposed in the K1b restore spec, mascot §I, 2026-11-11, awaiting the user's PASS.)
- Eyes shut while opening an envelope is a separate face drawn in front of every mood face: body-coloured lids over the eyes plus closed arcs. Only the envelope one-shot shows it, so it works over whatever mood Flutter set.
- The key toss arcs up past the right ear, not straight up: straight up it crossed the face and hid behind the yuzu.
- The vault pose's 400 ms step-aside has a second, instant transition gated on reducedMotion, listed first so it wins.

## Tried and ruled out
- Hiding the mood faces by keying their opacity in the envelope one-shot: a keyed property holds its value for the whole animation, so every mood face would be forced off for all 1.5 s, not just while the eyes are shut.

## Watch out
- Pose layer transitions are not gated by reducedMotion (only Action one-shots are). A pose mix that moves the capybara needs its own reduced-motion cut.
- The X8b search glass (mascot §H) and K1b both add to the Pose enum and scene.rml. X8b owns ids 0:520–0:533, K1b 0:540–0:566; whoever builds second rebases onto the other's rig. Combined draft size about 56.7 KB of the 60 KB cap.

In the code: docs/design/mascot/k1/apply_k1.py (Face_shut 0:558, to_vault() transitions, tosskey/envelope animations), render.sh + frames.commands; spec docs/design/pages/mascot.md §I, mascot.html S9.
