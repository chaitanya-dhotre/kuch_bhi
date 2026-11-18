---
title: "A message deleted for everyone is blanked on the server by direct SQL, so it can never be saved again"
author: Chaitanya
date: 2026-11-18
branch: main
cost: { minutes: 15, tokens: 197808 }
id: l-a1bd22ca
scope: repo
status: active
src: agent
touches:
  - docs/server/hooks/delete_everyone_purge.pb.js
  - docs/server/migrations/1794820000_updated_media_hide_deleted.js
  - docs/server/migrations/1794820100_cleanup_deleted_for_everyone.js
  - docs/server/tests/deleted_request_table.py
  - docs/server/tests/deleted_dry_run.sh
  - docs/design/pages/delete-everyone-leftovers-work-log.md
  - docs/design/pages/delete-everyone-leftovers.md
---

## Decided
2026-11-18, delete-everyone-leftovers §5 (live, user yes). When a message is flagged deleted for everyone, a server hook deletes its media rows (PocketBase removes the files) and blanks its body, iv and reply preview, plus the preview of any reply quoting it. It writes with direct SQL, like the disappearing-messages cron: the body fields are Required, and a saved record would broadcast a second update to every phone.

## Tried and ruled out
- `saveNoValidate`: works, but phones get a second realtime update with an empty body, and the update hooks run again.
- Making the body fields optional: then clients could also create messages with empty bodies.

## Watch out
- Any later save of a blanked row (a repeated delete, a pin) gets `400 validation_required`. Expired disappearing rows behave the same way. The client's delete and cancel paths treat that as done. Any new client write to a message must not retry a 400 forever.
- Media uploaded after the delete was the gap dry run 1 found. The upload rule now refuses it (400). A cancelled send's upload pipeline ignores the error because `ticket.cancelled` is set.
- The PATCH response and the realtime update still carry the old ciphertext, built from the in-memory record. Every receiver already held it.

In the code: docs/server/hooks/delete_everyone_purge.pb.js, docs/server/migrations/1794820000_updated_media_hide_deleted.js, 1794820100_cleanup_deleted_for_everyone.js; log docs/design/pages/delete-everyone-leftovers-work-log.md
