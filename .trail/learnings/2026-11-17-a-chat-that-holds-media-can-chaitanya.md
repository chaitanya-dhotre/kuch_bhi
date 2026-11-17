---
title: "A chat that holds media can't be deleted, so live test scripts must delete the sender before the chat, and leftovers go through a guarded one-off migration"
author: Chaitanya
date: 2026-11-17
branch: main
cost: { minutes: 21, tokens: 143592 }
id: l-b6bae35c
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
2026-11-17, wave 2 live re-check. The media row's chat link is required and has no cascade, so deleting a chat that holds any photo or file returns 400. Its creator can't be deleted either, because a chat's creator link is required. The user chose a guarded one-off migration to remove the leftovers: it deletes only if the rows are still the empty dryrun ones. That needs one extra restart.

## Tried and ruled out
- Deleting them in the admin UI: it works, but it's a manual step for the user.
- Leaving them: harmless, but a "dryrun" account would stay visible in user search.
- Direct SQL deletes: they skip PocketBase cascades (e.g. former_members).
- Signing in as superuser: not done with the live password.

## Watch out
- In a live test, delete the message sender first (that cascades their messages and media), then the chats, then the other users.
- On PocketBase 0.37.5, `<back-relation>:length` in a rule is refused ("unknown field"). For "no rows yet", use a bare `!=` on an aliased `@collection`.
- Changing rules through the API on a test copy writes auto-migration files. Give a rule probe its own copy, or `migrate down 1` reverts the wrong file.

In the code: docs/server/tests/wave2_live_check.py (cleanup order), docs/server/migrations/1794810100_cleanup_wave2_dryrun.js, docs/server/tests/wave2_dry_run.sh (probe on port 8097).
