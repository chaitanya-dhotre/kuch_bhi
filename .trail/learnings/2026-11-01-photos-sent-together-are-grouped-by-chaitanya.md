---
title: "Photos sent together are grouped by a shared album id on each message, not by time or by an id hidden in the encrypted text"
author: Chaitanya
date: 2026-11-01
branch: main
cost: { minutes: 12, tokens: 237291 }
id: l-439250a6
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/albums.md
  - docs/design/pages/albums.html
---

## Decided
Spec only so far (albums spec, awaiting the user's PASS). An album item carries the record id of the album's first item plus its position, on the server message and on the local row. Grouping happens only where the chat list is built, over loaded rows; late items join the album at its earliest row. Album sends do not start their own upload: they go through the existing serial resume pass, so items upload one at a time in pick order.

## Tried and ruled out
- An id inside the encrypted message text: decrypted bodies live only in a session cache and are never stored, so the list builder can't group on them without changing the frozen decrypt pass. The server already sees N media records from one sender in the same minute, so hiding the id gains little.
- Grouping by sender plus a time window: two photos sent separately a minute apart merge, and an album resumed after a network drop splits.

## Watch out
- Each media send starts its upload immediately and unawaited, so N back-to-back sends upload in parallel; only the resume pass is serial (ids are time-sortable, so it goes in send order).
- Swipe-to-reply wraps every chat bubble with a horizontal drag; a sideways-scrolling album inside it fights that gesture.
- Multi-pick needs no new package: the installed image picker already picks several photos and videos at once with a limit.

In the code:
- message_repository_impl.dart: sendMediaMessage starts _uploadMediaMessage unawaited (~L1753); _resumeMedia is serial (~L2100-2121); _companionFromRecord ~L5021; create body ~L1873-1886.
- swipe_to_reply.dart onHorizontalDragUpdate; message_bubble.dart wraps content in SwipeToReply (~L379).
- image_picker 1.2.2 pickMultipleMedia({limit}).
- Spec: docs/design/pages/albums.{md,html}.
