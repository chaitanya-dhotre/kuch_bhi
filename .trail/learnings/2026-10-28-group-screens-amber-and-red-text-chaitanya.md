---
title: "Group screens: amber and red text fail contrast, create adds directly while Add invites, remove/leave rotate keys so never retry them"
author: Chaitanya
date: 2026-10-28
branch: main
cost: { minutes: 15, tokens: 246958 }
id: l-10d911ad
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/group-info.html
  - docs/design/pages/group-info.md
  - docs/design/00-foundation.md
  - lib/infrastructure/repositories/message_repository_impl.dart
  - lib/features/groups/screens/create_group_screen.dart
  - lib/features/groups/screens/group_settings_screen.dart
---

## Decided
- Marigold accent used as TEXT on light surfaces is ~2.0–2.2:1 and the error red is 3.91:1; both fail the 4.5:1 body rule. Accent stays a fill/track/border; destructive actions = error-coloured icon + ink label (a darker errorText token would need a foundation amendment).
- Creating a group adds the chosen friends as members straight away (no invite), while "Add" in group info sends invites. Kept on purpose: making create send invites is a repository + E2E change, a separate task.
- Remove-member and leave-group rotate the group key inside the repository. A UI timeout on them must only unlock the UI and say "still working". It must never cancel or retry the call (a retry hits "not an active member"). Promote/demote/invite/switch get the normal 8s bound (PocketBase HTTP has no timeout).

## Watch out
- Group info turns a members-stream error into "0 members" and silently drops admin controls; the add-to-group sheet says "all friends are already in this group" while friends are still loading. Both are false empties.
- The disappearing-messages dialog exists twice (chat has the checkmark, group info doesn't); chat's menu lets any member change it but group info hides it from non-admins.
- Don't add a timeout to create-group: it would race its own server rollback.

In the code:
- Contrast numbers: tokens from docs/design/00-foundation.md §2 (accent #EFA00B on #FFFFFF / #FFF3DC; error #E5484D on #FFFFFF).
- removeMemberFromGroup / leaveGroup → _rotateGroupKey in lib/infrastructure/repositories/message_repository_impl.dart.
- Create flow: _createGroup in lib/features/groups/screens/create_group_screen.dart (direct conversation_members writes); invites: sendGroupInvite.
- Spec + checklist: docs/design/pages/group-info.{html,md}.
