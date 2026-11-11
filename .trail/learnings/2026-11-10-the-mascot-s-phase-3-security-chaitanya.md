---
title: "The mascot's phase 3 security moments use the front view on the lock screen and drop the unlock hop, because the lock must leave at once"
author: Chaitanya
date: 2026-11-10
branch: main
cost: { minutes: 13, tokens: 273050 }
id: l-f36c0297
scope: repo
status: active
src: agent
touches:
  - docs/design/mascot/phase3/apply_phase3.py
  - docs/design/pages/mascot.md
  - lib/features/mascot/capy.dart
  - docs/design/mascot/phase2/actions.png
---

## Decided
(Proposed in the Page 10 phase 3 spec, docs/design/pages/mascot.md §G, 2026-11-10, awaiting the user's spec PASS.)
- App lock: the capybara uses the Front view holding the key, not the Head view first planned. The Head view's lookX only tilts the head, so "eyes follow the PIN dots" reads as a nod; Front slides its whole face left/right (rig range raised from ±6 to ±10 so it shows at 72 dp) and eases over 0.2 s.
- No happy hop on unlock: the app-lock spec (E4) makes the lock leave the instant the PIN is right, so the hop would never be seen, and the lock must never wait on the mascot.
- Group key rotation has no banner in the app; rotation runs inside the admin's remove and is awaited, so a successful remove means the new key exists. K3 is a new small card after a remove, not a banner.
- Search "looks around" is a one-shot when "Nothing found" appears, not a "searching" state: search is local and finishes before such a state would show.

## Watch out
- Capybaras under the lock are Offstage, which keeps them mounted and possibly ticking. Measure on the Redmi before adding TickerMode around the hidden app: muted tickers would also pause any awaited animation in the app under the lock.
- The splash may only swap its logo for the capybara when the .riv is already loaded, otherwise the splash would show an empty box.

In the code: docs/design/mascot/phase3/apply_phase3.py (rig edits: LookEase interpolator 0:511, swapKey/lookAround triggers 0:514/0:515), render.sh + frames.commands; hooks lock_overlay.dart:304, backup_pin_screen.dart:954, group_settings_screen.dart:230, splash_screen.dart:73, chat_screen.dart:1693.
