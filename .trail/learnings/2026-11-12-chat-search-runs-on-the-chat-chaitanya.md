---
title: "Chat search runs on the chat screen over the loaded messages, not through the repository's search, so a search rule must live on the screen"
author: Chaitanya
date: 2026-11-12
branch: main
cost: { minutes: 8, tokens: 264748 }
id: l-ea7c8f96
scope: repo
status: active
src: agent
touches:
  - assets/stickers/celebrate.webp
  - assets/stickers/chill.webp
  - assets/stickers/guarding.webp
  - assets/stickers/hi.webp
  - assets/stickers/lol.webp
  - assets/stickers/love.webp
  - assets/stickers/on-my-way.webp
  - assets/stickers/sleepy.webp
  - assets/stickers/sorry.webp
  - assets/stickers/thanks.webp
---

## Decided
- In-chat search scans the messages the chat screen has already loaded (a debounced controller that reads each body). The repository's search method is not on that path. So a rule like "stickers never match" goes in the screen's candidate list. The repository copy stays for consistency but changes nothing the user sees.

## Tried and ruled out
- Filtering sticker rows only in the repository's search prefilter (stickers phase 4 build): its unit test passed, but on the phone stickers still showed up in results.

## Watch out
- The search controller's own tests inject the body lookup and never build the candidate list, so they can't catch this. Use the chat-screen search widget test, with a row whose body contains the query.

In the code: lib/features/chat/screens/chat_screen.dart candidate list before `_search.setQuery` (skips type 'sticker'); ConversationSearchController in the same file; test/chat/search_capy_test.dart "a sticker never matches…"; repository searchMessages in message_repository_impl.dart.
