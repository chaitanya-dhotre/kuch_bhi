---
title: "New emoji show as boxes on older phones because Flutter skips Android's emoji pack, so the app ships a cut-down emoji font as a fallback"
author: Chaitanya
date: 2026-11-18
branch: main
cost: { minutes: 32, tokens: 154251 }
id: l-7a423a40
scope: repo
status: active
src: agent
touches:
  - lib/core/theme/app_theme.dart
  - lib/features/groups/screens/group_settings_screen.dart
  - lib/features/groups/screens/create_group_screen.dart
  - lib/core/widgets/app_avatar.dart
  - lib/features/home/screens/home_screen.dart
  - test/core/initials_test.dart
  - test/profile/profile_screen_test.dart
  - pubspec.yaml
  - lib/main.dart
---

## Decided
Native Android apps get new emoji through EmojiCompat (downloaded by Play services). Flutter draws text itself and never uses it, so on the Samsung M52 any emoji newer than the phone's own font showed as a blank box. The user picked "only the new emoji" (2026-11-18): a font cut from Noto Color Emoji down to the 668 emoji from Unicode Emoji 13.1 onward (2.8 MB, the APK grows by about 2.6 MB). It is set as ThemeData.fontFamilyFallback, so familiar emoji keep the phone's own look and only the new ones come from the bundled font.

## Tried and ruled out
- Bundling the whole Noto Color Emoji (about 10 MB): every phone would show Google-style emoji. Too big for what it fixes.
- Downloading the font at runtime: it would need the network before emoji render.

## Watch out
- Flutter tries fontFamilyFallback before the phone's system fonts. So any character the cut-down font holds draws in Google style even where the phone has its own version, including the parts that new ZWJ sequences are built from.
- To add newer emoji later, re-cut from upstream: `pyftsubset NotoColorEmoji.ttf --text-file=<sequences> --layout-features='*'`, with the sequences taken from Unicode's emoji-test.txt.
- Throwaway test accounts that received group messages can't be deleted through the API. The sender's pre-created receipts and the group-key rows are required links to them with no cascade.

In the code:
- Font: `assets/fonts/NotoEmojiNew/NotoEmojiNew.ttf`, with its licence in `OFL.txt`.
- `lib/core/theme/app_theme.dart`: `fontFamilyFallback`.
- `lib/main.dart`: registers the licence for About → Licences.
- Upstream file: `googlefonts/noto-emoji` `2D/fonts/NotoColorEmoji.ttf`.
