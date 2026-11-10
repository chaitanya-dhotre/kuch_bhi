---
title: "The mascot is drawn and animated in Rive by Claude writing RML with the Rive CLI, replacing the rule to defer Rive and keep the old drawing"
author: Chaitanya
date: 2026-11-09
branch: main
cost: { minutes: 29, tokens: 287045 }
id: l-b08621c0
scope: repo
status: active
src: agent
touches:
  - docs/design/mascot/directions/gen.py
  - docs/design/mascot/directions/compare.html
  - docs/design/mascot/styles/gen_styles.py
  - docs/design/mascot/inventory.md
  - docs/design/mascot/inventory.src.html
  - docs/design/mascot/styles/gen_s1v2.py
  - docs/design/mascot/round2.html
  - docs/design/pages/mascot.md
---

## Decided
User, 2026-11-07 to 2026-11-09 (Page 10, spec awaiting PASS). The capybara mascot moves to Rive now instead of first extending the CustomPainter rig, and it is redrawn rather than layered from the old approved SVG. The user can't draw and won't hire an artist, so Claude authors every view as RML (Rive's text format) with the Rive CLI and checks it headless. This replaces the old backlog rule "Rive deferred until Tier 2; layer the approved SVG, no redraw".
Style chosen: S1 Sticker (dark-brown outline, flat fills, blush, yuzu on the head). Four views: Sit, Front, Head (for slots under 56 dp, eyes 1.4x) and Onsen (offline banner as a yuzu bath where queued messages float as yuzus). Eye rule from the user: idle = relaxed curved-line eyes, doing something = round eyes, intense = a focused look.
## Tried and ruled out
- Keeping the old capybara with soft gradients (direction C as first drawn): at 40 dp the face is ~10 dp tall and the soft muzzle smudges; body #C6894F is only 2.7:1 on light backgrounds. A Head view and a 9:1 outline (#5C3B28) fixed both.
- First S1 draft: a round mid-face muzzle made it read as "a brown seal" (user). What reads as capybara: a long blunt box-ended snout with the dark patch at the TIP, small eye high and set back, flat head top, no neck, ears at the back, toe ticks.
- A Duolingo-like flat style (big white eyes, no outline): more energetic, but at 40 dp it drifts toward pug or frog and costs ~50% more shapes. The user's inspiration folder was kawaii sticker style, not Duolingo.
## Watch out
- Performance limit from the device spike: one animated capybara is smooth on the Redmi S2, six drop it to ~40 fps. Keep at most 2 animated per screen, no Feather blur, few bones.
- Rive CLI captures are opaque (no alpha): render with the page's background colour. `--commands` renders many artboards in one session (much faster than one process each). Feathered fills need fillRule="clockwise"; every state machine layer needs an EntryState; an artboard without defaultStateMachineId ignores data binds.
- `pkill -f "http.server NNNN"` also kills the shell running it; use a bracket pattern like "[h]ttp.server".
In the code: drafting generators docs/design/mascot/styles/gen_s1v2.py (writes s1v2/ and expressions/ RML); spec docs/design/pages/mascot.{md,html}; inventory docs/design/mascot/inventory.md. CLI ~/.rive/bin/rive 1.9.1.
