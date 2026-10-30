---
title: "The recovery key keeps its Copy button even though Samsung Keyboard's clipboard history keeps the key"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 45, tokens: 410751 }
id: l-c053ecfc
scope: repo
status: active
src: agent
touches:
  - lib/core/utils/recovery_key.dart
  - test/offline/key_backup_format_test.dart
  - test/core/recovery_key_test.dart
  - lib/features/auth/screens/backup_pin_screen.dart
  - test/auth/backup_secret_screen_test.dart
  - test/home/backup_upgrade_banner_test.dart
  - android/app/src/main/kotlin/com/chai/kuch_bhi/MainActivity.kt
---

## Decided
The recovery key screen keeps a Copy button. The copy goes through a small Android channel (MainActivity, "kuch_bhi/clipboard") that marks the clip sensitive, and after a successful save the app clears the clipboard with the platform's real clear. The user rejected dropping Copy: making people write a 25-character key down by hand costs more (typos, lost keys) than the clipboard-history exposure.

## Tried and ruled out
- Flutter's own Clipboard.setData plus copying an empty string after the save: both Gboard and Samsung Keyboard kept the key in their clipboard history in plain text, because they record a clip the moment it is copied.
- Expecting the sensitive flag to stop keyboards from storing it: on the device check (2026-10-31) Gboard still stores the entry but shows it as dots; Samsung Keyboard ignores the flag and shows the key. No Android API lets an app delete entries from a keyboard's history.

## Watch out
Saving the key in a password manager on the check step works well (the manager picks up the account email from a hidden username field), so that is the safer path to steer people to; Copy is the fallback.

In the code: lib/features/auth/screens/backup_pin_screen.dart (_copyKey, _clearClipboard), android/app/src/main/kotlin/com/chai/kuch_bhi/MainActivity.kt.
