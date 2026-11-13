---
title: "Hats on the capybara are drawn once and placed into each view, and the free Rive plan adds 13.9 KB to every published file"
author: Chaitanya
date: 2026-11-12
branch: main
cost: { minutes: 4, tokens: 61810 }
id: l-2c24bd19
scope: repo
status: active
replaces: l-571715c8
src: agent
touches:
  - docs/design/pages/mascot.md
---

## Decided
(Proposed in the Page 10 phase 5 spec, mascot §K, 2026-11-12, awaiting the user's PASS.)
- Night and festival looks (nightcap, party hat, Diwali lamp) are each drawn once as a component artboard and placed into the Sit, Front, Head and Onsen views as nested artboards, switched by a `look` enum on a Look layer. Drawn into every view they cost +13 KB; nested, +7 KB. A hat can't live in a second file: it must ride on the artboard of the head it sits on.
- The app icon uses a full-body capybara (Front or Sit), not the Head bust (user).

## Tried and ruled out
- A lying "Loaf" view cut from the Head view onto a long body: the user said it does not look good at all. Onboarding is parked until other apps' onboardings have been reviewed.
- Mobbin through its MCP on the free plan: every search returns "requires a paid plan".

## Watch out
- About 13.9 KB of every published .riv is the Free-plan watermark (published minus the CLI's "built" size). Budgets are on the published file.
- The Sit artboard also has a Bone named "Head": match `<Artboard ... name="Head">` on the Artboard tag.
- `rive update` (1.9.2) was needed before renders; `advance` takes frames or "150ms", not "0.1".

In the code: docs/design/mascot/phase5/apply_phase5.py (R11 looks), render.sh, icon.py; docs/design/pages/mascot.md §K.
