---
title: "Reading a QR from a photo must not create and dispose a scanner controller, or the live camera on the same tab stops"
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 34, tokens: 484891 }
id: l-3e3af5ac
scope: repo
status: active
src: agent
touches:
  - lib/core/theme/tokens.dart
  - lib/core/theme/app_theme.dart
  - lib/core/widgets/app_sheet.dart
  - lib/core/widgets/app_dialog.dart
  - lib/features/chat/widgets/reaction_picker.dart
  - lib/features/chat/widgets/attach_sheets.dart
  - lib/features/home/screens/add_friend_screen.dart
  - test/core/sheet_harness.dart
  - test/core/app_sheet_test.dart
  - test/core/app_dialog_test.dart
---

## Decided
The add-friend Scan QR tab decodes a gallery photo through the scanner platform directly, with no controller made for it, so there is nothing to leak and nothing to dispose.

## Tried and ruled out
- Making a MobileScannerController per gallery pick and disposing it afterwards (what the Page 8 spec asked): in mobile_scanner 6.0.11 the controller's dispose() also disposes the shared platform scanner, which stops the live camera preview showing on the same tab. After a "no QR code in that photo" the user would be left with a dead camera.
- Leaving the per-pick controller undisposed (the old code): leaks a notifier and stream controller per pick.

## Watch out
Any second MobileScannerController in the app shares one platform instance; disposing any of them stops every live preview.

In the code:
- lib/features/home/screens/add_friend_screen.dart: _QrScanTabState._pickFromGallery calls MobileScannerPlatform.instance.analyzeImage(path)
- ~/.pub-cache/hosted/pub.dev/mobile_scanner-6.0.11/lib/src/mobile_scanner_controller.dart:440 (dispose → MobileScannerPlatform.instance.dispose())
