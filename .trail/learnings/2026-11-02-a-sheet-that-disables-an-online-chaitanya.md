---
title: A sheet that disables an online-only action must watch the connection while open and check again after the confirm
author: Chaitanya
date: 2026-11-02
branch: main
cost: { minutes: 49, tokens: 737336 }
id: l-add90874
scope: repo
status: active
src: agent
touches:
  - docs/design/10-registry.md
  - docs/design/pages/multi-select-work-log.md
  - docs/design/pages/multi-select.html
  - docs/design/pages/multi-select.md
  - lib/core/config/fake_message_repository.dart
  - lib/domain/repositories/message_repository.dart
  - lib/features/chat/screens/album_screen.dart
  - lib/features/chat/screens/chat_screen.dart
  - lib/features/chat/widgets/message_bubble.dart
  - lib/features/chat/widgets/message_context_menu.dart
---

## Decided
The multi-select delete sheet watches the online flag live (a Consumer inside the sheet), so Delete for everyone dims and wakes while the sheet is open, and the delete checks online again right after the confirm dialog: offline there means a toast "Available online", nothing deleted, selection kept. Found on the device (12.8 round 1): reading the flag once when the sheet opened left the row enabled after the internet dropped, and an offline delete for everyone showed deleted, then came back on reopen (server-first, the next fetch restores it).

## Tried and ruled out
Reading isOnlineProvider once and passing a bool into the sheet builder (what the album collage did): stale for as long as the sheet stays open.

## Watch out
Any other sheet or dialog that gates an online-only action (pin, delete for everyone in the single menu) with a bool read at open time has the same gap.
Widget tests that pump the whole chat screen never settle unless the chat runs with reduced motion: the composer's mic pulse repeats forever. Seed text bodies into bodyCache; the provider override alone left the bubbles on their placeholder.

In the code:
- lib/features/chat/widgets/selection_bar.dart: deleteSelectedMessages, _deleteChoice
- test/chat/multi_select_test.dart: _pumpChat harness (MediaQuery disableAnimations, bodyCache seed), "the sheet follows the connection live"
