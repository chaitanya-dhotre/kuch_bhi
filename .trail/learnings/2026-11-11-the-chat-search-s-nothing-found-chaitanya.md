---
title: "The chat search's \"Nothing found\" view is rebuilt after every keystroke, so anything it must remember for one search lives on the chat screen"
author: Chaitanya
date: 2026-11-11
branch: main
cost: { minutes: 12, tokens: 240178 }
id: l-d1755206
scope: repo
status: active
src: agent
touches:
  - test/chat/search_capy_test.dart
  - lib/features/chat/screens/chat_screen.dart
---

## Decided
- The mascot's look-around on "Nothing found" (Page 10 phase 3, X8) plays once per no-results stretch, and the "already looked around" flag lives on the chat screen's state, not in the empty-state widget. It resets when results show, when the query is cleared, or when search closes.

## Tried and ruled out
- Keeping the flag in the empty-state widget, as the phase 3 spec assumed ("the widget stays mounted while you type"). It does not: every keystroke marks the search pending, which swaps the list back in until the 200 ms debounced search answers, so the empty state unmounts and mounts again and the animation replayed on every pause in typing.

## Watch out
- Anything else that should happen once per search on the "Nothing found" view (an announcement, a timer) has the same problem.
- The chat widget tests open with reduced motion forced on (the composer's mic pulse never settles for pumpAndSettle); to test something that only moves with motion on, open reduced and flip it off afterwards (see the X8 search test).

In the code: lib/features/chat/screens/chat_screen.dart (_lookedAround, _SearchEmptyState, _onSearchChanged), test/chat/search_capy_test.dart.
