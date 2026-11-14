---
title: "On a cold start the launcher capybara changes twice, and both changes are meant to happen"
author: Chaitanya
date: 2026-11-14
branch: main
cost: { minutes: 8, tokens: 127476 }
id: l-19c842ec
scope: repo
status: active
src: agent
touches:
  - lib/core/widgets/app_logo_tile.dart
  - test/core/app_logo_tile_test.dart
  - docs/design/pages/mascot.md
  - docs/design/mascot/phase5/icon.py
---

## Decided
User device check 2026-11-14 (M52, Android 12+, 5b launcher icon): a cold start shows three pictures. First, Android's own splash draws the adaptive icon's capybara large, with no teal plate (the system splash uses the foreground, not the background colour). Then Flutter's splash shows AppLogoTile (the same capybara on the teal tile, 88 dp, smaller). Then, if the start takes over 1 s, the guarding capybara replaces the tile (phase 3 E4). The user saw "the icon change twice" and accepted it; this matches mascot.md K6 and K8 item 11.

## Watch out
- Only change this if the user asks for smoother. Options: windowSplashScreenIconBackgroundColor in a values-v31 theme (adds the teal circle to the system splash), or matching the Flutter tile's size to the system splash icon. Neither removes the jump completely.
- The generated adaptive-icon XML must not contain "--" in a comment (for example "--ship"): aapt refuses to compile it.

In the code: docs/design/mascot/phase5/icon.py (ship mode, run `python3 docs/design/mascot/phase5/icon.py --ship <scratch> android/app/src/main/res`), lib/core/widgets/app_logo_tile.dart, android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml.
