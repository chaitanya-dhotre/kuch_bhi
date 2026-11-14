---
title: "Restore progress repaints are throttled with a timer, not a timestamp, and widget tests need a short pump after a burst"
author: Chaitanya
date: 2026-11-12
branch: main
cost: { minutes: 12, tokens: 208291 }
id: l-23b6df27
scope: repo
status: active
src: agent
touches:
  - lib/infrastructure/repositories/message_repository_impl.dart
  - test/offline/history_sync_test.dart
  - docs/design/pages/history-sync-work-log.md
  - lib/features/auth/screens/backup_pin_screen.dart
  - test/auth/restore_overlay_test.dart
---

## Decided
History-sync S4 (2026-11-12): the restore screen paints download progress at most every 100 ms. The first event paints at once; later events wait and a 100 ms timer paints the latest (leading + trailing). `complete` cancels the timer and paints at once.

## Tried and ruled out
- A timestamp check that drops events inside 100 ms (the spec's wording): the last event of a burst is never painted until the next event, so the count can sit stale for a whole page fetch. It also can't be tested: widget tests run on a fake clock but DateTime.now() is real time.

## Watch out
- In widget tests one long `tester.pump(1600 ms)` draws a single frame at its end. A deferred repaint (the trailing timer) fires inside that pump but rebuilds only at the end, so any periodic timer reading widget props in the same pump (the restore envelopes, I3) sees the old value and counts a change on its next tick. Pump 100 ms after a progress burst, then the rest. A phone draws every 16 ms, so the app is fine.

In the code:
- lib/features/auth/screens/backup_pin_screen.dart `_applyProgress`, `_progressTimer`, `_pendingProgress`
- test/auth/restore_overlay_test.dart "K1b: centre check…" (100 + 1500 ms pumps) and the S4 gate-6 test
