---
title: "A message deleted for everyone keeps no ciphertext on the phone, so the refetch check must treat it as final"
author: Chaitanya
date: 2026-11-17
branch: main
cost: { minutes: 18, tokens: 376028 }
id: l-d69380f3
scope: repo
status: active
src: agent
touches:
  - KUCH_BHI_PROJECT_BIBLE.md
  - docs/design/pages/former-member-history-work-log.md
  - docs/design/pages/former-member-history.html
  - docs/design/pages/former-member-history.md
  - docs/server/hooks/former_member_record.pb.js
  - docs/server/migrations/1794800000_former_members.js
  - docs/server/migrations/1794800100_former_members_backfill.js
  - docs/server/tests/fm.pb.js
  - docs/server/tests/former_dry_run.sh
  - docs/server/tests/former_live_check.py
---

## Decided
delete-everyone-leftovers (built 2026-11-17, device check pending). Every write that marks a message deleted for everyone blanks its encrypted_body and iv in the same write: the ingest commit (upserts carrying the flag and tombstones), my own delete for everyone, and a once-per-run start-up sweep for rows from older builds. After the commit, the row's text leaves the body cache, and its local media is forgotten, but only when the row was not already deleted (no repeat file work on every echo). Replies no longer upload a reply_preview: nothing read it, and it kept the parent's text after a delete.

## Watch out
- The refetch filter compares the local body with the server's. A blanked row never matches, so without the "deleted on both sides = unchanged" skip it would refetch every deleted message forever.
- A Drift customUpdate re-emits every watcher of the table even when it changes zero rows. The sweep returns early when nothing matches; the disappearing "re-emits nothing" test caught it.
- The server still keeps the ciphertext and serves the media of deleted messages until expiry (spec §5, L6), so the phone fix alone doesn't stop a modified client.

In the code: lib/infrastructure/ingest/ingest_boundary.dart (commit, forgetMedia), MessagesDao.blankDeletedForEveryone, MessageRepositoryImpl.sweepDeletedForEveryone, docs/design/pages/delete-everyone-leftovers.md
