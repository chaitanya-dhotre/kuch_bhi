---
title: "Marking a PocketBase field hidden also stops its owner from writing it, so hidden user fields need a write-back hook"
author: Chaitanya
date: 2026-11-16
branch: main
cost: { minutes: 10, tokens: 178944 }
id: l-f488c204
scope: repo
status: active
src: agent
touches:
  - docs/server/migrations/1794790000_updated_membership_presence.js
  - docs/server/hooks/user_fields_unhide.pb.js
  - docs/server/tests/mk.pb.js
  - docs/server/tests/membership_request_table.py
  - docs/server/tests/membership_dry_run.sh
  - docs/design/pages/membership-rules-work-log.md
  - docs/design/pages/membership-rules.md
  - docs/server/migrations/1794700100_updated_rules_scope.js
  - docs/server/tests/rules_request_table.py
  - docs/design/pages/server-rules-work-log.md
---

## Decided
The membership/presence fix (2026-11-16) hides five `users` fields at the schema level (presence, push token, key backup) so nobody else can read or filter them. On PocketBase 0.37.5 that also drops those fields from every non-superuser create/update body. The PATCH still answers 200 and the value doesn't change. So the same hook file has an owner-only `onRecordUpdateRequest` that re-reads the raw body and sets the fields itself.

## Tried and ruled out
- Reading `e.requestInfo().body` in the update hook: the update handler already replaced that body with the stripped copy (`requestInfo.Body = data` in `apis/record_crud.go`), so it is empty for hidden fields.
- An enrich-only hide (the old `key_backup_hide.pb.js`): a list filter on the field still works as a yes/no oracle. Only a schema-hidden field is refused in non-superuser filters (400).

## Watch out
- A dry-run check that only looks at the HTTP status of a write to a hidden field proves nothing. Read the value back as the owner.
- Any new hidden field that the app writes must be added to the write-back list in the hook.
- A chat-mate's unhide depends on the stored value, so a write that silently fails shows up as "the other phone sees no typing".

In the code: `docs/server/hooks/user_fields_unhide.pb.js` (enrich unhide + `onRecordUpdateRequest` with `e.bindBody` into a `DynamicModel` whose defaults are a "\u0000" not-sent marker); checks V4/V6b/V6d/V6e in `docs/server/tests/membership_request_table.py`; log `docs/design/pages/membership-rules-work-log.md`.
