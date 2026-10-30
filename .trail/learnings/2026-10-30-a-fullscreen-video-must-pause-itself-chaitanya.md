---
title: "A fullscreen video must pause itself when the app leaves the foreground, and viewer buttons must sit outside the photo's double-tap detector"
author: Chaitanya
date: 2026-10-30
branch: main
cost: { minutes: 40, tokens: 440770 }
id: l-c4992ce7
scope: repo
status: active
src: agent
touches:
  - lib/features/chat/widgets/expiry_badge.dart
  - lib/features/media/providers/media_viewer_providers.dart
  - lib/features/media/screens/media_viewer_screen.dart
  - test/chat/expiry_label_test.dart
  - test/media/viewer_harness.dart
  - test/media/media_viewer_screen_test.dart
  - test/media/media_viewer_video_test.dart
  - test/media/media_entry_points_test.dart
  - docs/design/pages/media-work-log.md
---

## Decided
- The media viewer pauses its video on every app lifecycle state except resumed. The video plugin's own lifecycle observer remembers "was playing" when the app is paused and calls play() again on resume, so leaning on it alone makes a video restart by itself when you come back to the app. Pausing on `inactive` (which always comes before `paused`) means the plugin records "not playing" and leaves it alone.
- The viewer's top bar and video controls are siblings of the gesture layer, not children of it. A detector with onDoubleTap holds the gesture arena for the 300ms double-tap window, so any button inside it fires 300ms late.
- The viewer reads the media blob row (read-only) from the moment it opens. A blob already marked failed (expired, dead link, decrypt, verify) is terminal, but the media-file provider still waits 45s for a media event before it returns null; reading the row first shows the honest end state at once.

## Tried and ruled out
- Relying on video_player's built-in observer for "background pauses, back stays paused" (what the spec assumed): it resumes playback on return.
- Bar inside the full-screen GestureDetector (first build): every Close/Share/Save tap on a loaded photo was delayed by the double-tap timeout.

## Watch out
- Widget tests: the first frame of a push with a Hero builds the new route offstage (Hero measuring), so finders miss it; pump one more frame.
- The image cache keeps a pending real-IO load for a path across tests in the same file; clear it before seeding a fake completer under that path, or the seed is ignored.
- A FileImage never resolves in fake async; seed the image cache to test decode errors or GIF frames.

In the code: lib/features/media/screens/media_viewer_screen.dart (didChangeAppLifecycleState, _view, the outer Stack in _build), video_player 2.11.1 lib/video_player.dart _VideoAppLifeCycleObserver, test/media/media_viewer_video_test.dart ('app to background pauses; back stays paused'), test/media/media_viewer_screen_test.dart (decode failure, GIF tests).
