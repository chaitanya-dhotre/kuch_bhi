---
title: "Decrypted media stays on the phone with no age limit, because the server deletes it and the phone's copy is the only one left"
author: Chaitanya
date: 2026-11-01
branch: main
cost: { minutes: 5, tokens: 291693 }
id: l-a3b8261f
scope: repo
status: active
src: agent
touches:
  - lib/data/local/database/daos/messages_dao.dart
  - lib/infrastructure/ingest/ingest_boundary.dart
  - lib/infrastructure/repositories/message_repository_impl.dart
  - test/offline/media_send_followups_test.dart
  - lib/infrastructure/media/media_blob_store.dart
  - docs/backlog.md
---

## Decided
- The user decided (2026-11-01) that decrypted media in the phone's cache is never removed by age. The server deletes media after its retention, so a sweep would lose the user's photos, videos and voice notes for good. Only the size cap evicts (re-downloadable media only while the server still has it), and logout wipes the whole cache.

## Tried and ruled out
- The security audit's TTL sweep (evict media not opened for 30 days): rejected for the reason above, with or without an exemption for starred/pinned media.

## Watch out
- A future audit will flag "cleartext media with no TTL" again; point it here instead of re-proposing a sweep.

In the code: lib/infrastructure/media/media_blob_store.dart (janitor, evictIfNeeded, wipeMediaCache); docs/audits/2026-10-30-security.md §4.3; docs/backlog.md 14.6.
