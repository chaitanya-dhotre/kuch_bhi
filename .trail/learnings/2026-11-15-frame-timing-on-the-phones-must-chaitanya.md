---
title: "Frame timing on the phones must be read from SurfaceFlinger, not gfxinfo, and installs must be split-per-ABI builds"
author: Chaitanya
date: 2026-11-15
branch: main
cost: { minutes: 5, tokens: 53521 }
id: l-e2690eb7
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/motion-work-log.md
---

## Decided
- Frame runs (motion pass, 2026-11-15) read the app's SurfaceView frame times from SurfaceFlinger, polled every 250 ms during a case, and count gaps over 16.7 ms and over 1.5 refresh periods. The M52 runs at 120 Hz and keeps only ~1 s of frames, so one read at the end loses most of a case.
- The user's test chats for device runs: the "Capybara" group (visible on Home on both phones) or the "Pixel Chait" chat.

## Tried and ruled out
- `dumpsys gfxinfo`: Flutter draws on its own surface, so gfxinfo sees 1–2 frames per case. Useless for this app.
- Installing the universal release APK: the phones carry split-per-ABI builds with version code 2001, so the universal APK (code 1) is refused as a downgrade.

## Watch out
- Tapping the composer opens the keyboard and moves the send button up. Find the send position with the keyboard open, or a scripted burst types but never sends.

In the code: layer = the `SurfaceView[com.chai.kuch_bhi/...](BLAST)` entry in `adb shell dumpsys SurfaceFlinger --list`; `--latency-clear "<layer>"` before, `--latency "<layer>"` during. Build: `flutter build apk --release --split-per-abi`, install `app-arm64-v8a-release.apk` (both phones are arm64-v8a). Composer send with the keyboard open: M52 (963,1400), Redmi (660,910). Numbers: docs/design/pages/motion-work-log.md.
