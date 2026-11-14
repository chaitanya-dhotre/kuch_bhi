---
title: "A fresh install of a group admin probably rotates every group's key during the restore, because every member looks new to the phone"
author: Chaitanya
date: 2026-11-13
branch: main
cost: { minutes: 7, tokens: 183105 }
id: l-0440b7b2
scope: repo
status: active
src: agent
touches:
  - docs/design/pages/restore-rev2.md
---

## Decided
Planning finding, 2026-11-13 (restore rev 2 spec, awaiting the user's PASS). The conversations step before the restore's chat loop took about 58 s on the M52 (26 chats) and 9 s on the Redmi (17 chats) on the same network. Its own work is about 27 sequential requests (10–15 s at hotspot latency), so something ran next to it on the M52. The likeliest cause in the code: on a fresh install no member row exists locally, so the step schedules a join rotation for every member of every group where this account is an admin and the elected owner. Once the key pair is restored those rotations run for real (member list, version read, one users.getOne + one wrap + one group_keys create per member), several groups at once. A successful rotation logs nothing, so it was invisible. It also fits groups having 14–19 key versions. Not proven: logs were not kept and nobody checked which test account administers the groups. The spec proposes skipping the join rotation on first sight of a conversation, a "[Group] rotated" log line, one members request per 40 conversations, and a single-flight conversations pass.

## Watch out
The rotation election reads admins from local rows, which on a fresh install hold only the ones upserted so far, and a later "not the owner" answer never cancels a timer already set. The conversations pass has no single-flight: SSE conversation/member events and every resume (Google sign-in, switching apps to copy the recovery key) start another full pass. My memberships are read with getList, so only the first 30 chats.

In the code: message_repository_impl.dart _syncConversations (getList memberships, per-conversation conversation_members getFullList, _maybeScheduleRotate for members not in localMemberIds), _maybeScheduleRotate / _isRotationOwner, _rotateGroupKeyNow. Spec: docs/design/pages/restore-rev2.md.
