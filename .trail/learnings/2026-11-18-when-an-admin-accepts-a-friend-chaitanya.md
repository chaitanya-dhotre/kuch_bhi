---
title: "When an admin accepts a friend's new security code, the group key is renewed, because filling in a missing key row never fires"
author: Chaitanya
date: 2026-11-18
branch: main
cost: { minutes: 76, tokens: 1381256 }
id: l-c1486c95
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/delete-everyone-leftovers.md
  - lib/core/decrypt/body_cache.dart
  - lib/data/local/database/app_database.dart
  - lib/data/local/database/daos/messages_dao.dart
  - lib/features/chat/providers/chat_provider.dart
  - lib/features/chat/widgets/reply_quote.dart
  - lib/features/media/screens/media_docs_screen.dart
  - lib/features/starred_messages/screens/starred_messages_screen.dart
  - lib/infrastructure/ingest/ingest_boundary.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
---

## Decided
Device run 2026-11-18 (key-change warning, audit F3). On an admin's phone, Accepting a friend's new code rotates every group where I am admin and the friend is a member. The rotation wraps to pins, so the friend gets a new version under the new key. The rotations run in the background after Accept.

## Tried and ruled out
The spec's "catch-up wrap": write the friend's row at the current version only if it is missing. It never fired: a friend who started fresh still has a row at the current version, wrapped to their OLD key, and group_keys rows are never updated (a row may wrap another key). Nothing records which key a row was wrapped to, so "missing" can't be detected.
Awaiting the rotations inside Accept: one rotation took 2–4 s on the M52 and a friend in 5 shared groups held the Accept screen for ~15 s.

## Watch out
A phone only notices a friend's key change when it sends to or receives from that friend; a pull-to-refresh doesn't re-read keys. In a device test, send a message to make the change show up.
A reinstall restored with the recovery key keeps the same key; to test a change, take "I lost it" → Start fresh on the restore screen.

In the code: message_repository_impl.dart acceptContactKey / _rotateAfterAccept (test seam acceptRotations); test "admin Accept rotates the shared group" in test/security/key_change_warning_test.dart.
