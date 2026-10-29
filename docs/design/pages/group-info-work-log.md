# Group Info + Create Group — implementation work log

Date: 2026-10-29  
Scope: Page 4, checklist `docs/design/pages/group-info.md`, spec `group-info.html`.
Implemented by Mimo (freebuff) from `group-info-handoff.md` while Omnirush was down; graded and
finished by Claude.

## Evidence

| Check | Result |
|---|---|
| E2E boundary | PASS — `_createGroup` diff vs HEAD = the two `MemberKeyMissingError` throws + catch copy only; rotation body unchanged (only wrapped, see below) |
| Full Flutter suite | PASS — 366/366 (baseline 307 + 55 page tests + 4 `SerialPerKey`) |
| Flutter analyze | 0 errors (87 pre-existing info/warning diagnostics) |
| Diff whitespace | PASS — `git diff --check` |
| Device check | PASS — user, Samsung Galaxy M52 (admin + member views, offline, create flow, both themes) |

## Implemented

- Shared pieces: C4a `showActionSheet`, C4b `ConversationMenuAction.destructive`, C11
  `showDisappearingDialog` (chat + Group Info), R10a `SettingsTile.destructive`, R3a
  `BusySpinner` (added at grading: the groups grep gate bans `CircularProgressIndicator`, A6
  allows a per-row spinner).
- `GroupAdminNotifier` owns every Group Info mutation: busy keys per surface, 8s bound, 30s
  UI-only bound on remove/leave (never cancelled or retried).
- Group Info and Create rebuilt to the checklist; tests under `test/groups/` +
  `test/chat/disappearing_dialog_test.dart` + groups grep gate.

## Grading fixes (Claude)

- `debugPrint` error detail restored on 4 catch sites (A4 keeps detail there).
- Backlog §11.5 risk: a second remove/leave after the 30s unlock (or a join / key-gap background
  rotation) could rotate the group key concurrently on one device. All rotations now pass through
  a per-group queue (`SerialPerKey` in `lib/core/utils/serial_per_key.dart`, wrapped around the
  unchanged `_rotateGroupKeyNow`). A stuck predecessor holds the queue ≤2 min; the existing
  collision retry covers that overlap.

## Open / deferred

- The six product decisions: `docs/backlog.md` §11 (all at spec defaults).
- Two admins on two devices rotating at once still relies on the server-side collision retry.
