---
title: "Publish the capybara rig into the project and move the file out, and install split-per-ABI release builds so the phone accepts the update"
author: Chaitanya
date: 2026-11-11
branch: main
cost: { minutes: 16, tokens: 109301 }
id: l-589fcb26
scope: repo
status: active
src: agent
touches:
  - assets/mascot/capy.riv
  - docs/design/mascot/k1/apply_k1.py
  - docs/design/mascot/k1/frames.commands
  - docs/design/mascot/k1/render.sh
  - docs/design/pages/mascot-work-log.md
  - docs/design/pages/mascot.html
  - docs/design/pages/mascot.md
  - lib/features/auth/screens/backup_pin_screen.dart
  - lib/features/mascot/capy.dart
  - mascot/capy/scene.rml
---

## Decided
- Device builds for the M52 are installed as the split-per-ABI arm64 APK. The phone already has version code 2001 (Flutter's split numbering: 2000 for arm64 plus build 1), so a plain fat APK (version code 1) is refused as a downgrade. Uninstalling to get around that would wipe the phone's chats.

## Watch out
- `rive mascot/capy --publish --output-dir=assets/mascot` resolves the output dir relative to the project folder, so it writes mascot/capy/assets/mascot/capy.riv. Move that file to assets/mascot/capy.riv and delete the stray folder, or the app keeps shipping the old rig.
- In widget tests with timers, `tester.pump(duration)` runs timers before it builds the next frame. A periodic tick that reads widget props sees the old values unless the test pumps a frame after changing the inputs. A device always draws a frame in between.

In the code: flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64, then adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk; test/auth/restore_overlay_test.dart (pump after sync.progress).
