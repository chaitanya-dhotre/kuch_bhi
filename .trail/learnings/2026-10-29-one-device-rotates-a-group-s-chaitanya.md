---
title: "One device rotates a group's key one change at a time, waiting at most two minutes for a stuck one"
author: Chaitanya
date: 2026-10-29
branch: main
cost: { minutes: 37, tokens: 639924 }
id: l-a1d51c45
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/group-info-handoff.md
  - docs/design/pages/group-info.md
  - lib/features/groups/screens/group_settings_screen.dart
  - lib/features/groups/screens/create_group_screen.dart
  - lib/features/groups/providers/group_admin_provider.dart
  - docs/design/10-registry.md
  - test/groups/group_info_actions_test.dart
  - docs/backlog.md
  - test/serial_per_key_test.dart
  - lib/core/utils/serial_per_key.dart
---

## Decided
Every group-key rotation on a device (remove, leave, join debounce, key-gap repair) goes through one per-group queue. A rotation waits for the previous one on the same group to settle, capped at 2 minutes.

Why: after the 30s UI bound unlocks a removal, an admin could start a second remove or leave while the first was still rotating. Background rotations could overlap the same way.

## Tried and ruled out
- A UI-only guard in the groups notifier that refused a second remove/leave until the first settled. Dropped: it missed the background rotations, and it blocked the group until app restart whenever a call never returned (PocketBase HTTP has no timeout).
- An unbounded lock. Dropped for the same hang reason.

## Watch out
The 2-minute cap means overlap is still possible after a hang. That is safe only because the rotation never overwrites an existing version row and retries at the next version (up to 3 times). Keep that collision retry if the rotation is ever rewritten. Two admins on two phones are not covered by the queue at all; only the collision retry protects them.

In the code: lib/core/utils/serial_per_key.dart (SerialPerKey, maxWait 2 min) · message_repository_impl.dart `_rotateGroupKey` wraps the unchanged `_rotateGroupKeyNow` · test/serial_per_key_test.dart
