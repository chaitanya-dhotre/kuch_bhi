# Group Invites (consent-based group joins) — Design Spec

- Date: 2026-09-24
- Status: approved by user (this session)
- Follows: bug #17 admin-remove fix (server rules live 2026-09-24)

## Context

Admin adds to groups are currently automatic and, after the leave/re-add test, undesired: a member who quit gets silently re-added. User request: adds become consent-based requests the invitee accepts or declines; the admin sees declined status.

Server-side, a member who quit is indistinguishable from someone who never joined (leave/remove deletes the member row). Therefore ALL admin adds become invites (user decision).

## User decisions (locked)

1. **Scope**: all adds = invites (uniform, consent-based).
2. **Accept UX**: like friend requests — FCM push (kb_requests channel) + existing requests surface with Accept/Decline.
3. **Key hand-off**: self-join + admin auto-rotate (see Accept flow). E2E: joiner holds no group key until an admin device rotates.

## Server changes (PocketBase 0.37.5, kuch-bhi.duckdns.org)

### New collection `group_invites`

| Field            | Type                       | Notes                          |
|------------------|----------------------------|--------------------------------|
| conversation_id  | relation → conversations   | required, cascade delete       |
| invited_user_id  | relation → users           | required                       |
| invited_by       | relation → users           | required                       |
| status           | select: pending/accepted/declined | single-select, required  |
| created, updated | autodate                   |                                |

Index: `UNIQUE (conversation_id, invited_user_id)` — one invite per user per group. Re-invite = PATCH the same row back to `pending` (idempotent; no duplicate rows).

### Rules

Back-reference semantics on this PB build (empirically verified 2026-09-24 via impersonation probes): multiple `@collection.X` conditions over the same path bind to ONE joined row (same-row). Plain `=` on a back-referenced field is match-ALL and breaks when any joined row differs — use `?=` for every back-referenced comparison.

```
ADMIN = (@collection.conversation_members.conversation_id ?= conversation_id
      && @collection.conversation_members.user_id ?= @request.auth.id
      && @collection.conversation_members.role ?= "admin")
```

| Rule | Value |
|------|-------|
| createRule | `ADMIN` |
| updateRule | `invited_user_id = @request.auth.id \|\| ADMIN` |
| deleteRule | `invited_user_id = @request.auth.id \|\| ADMIN` |
| listRule / viewRule | `invited_user_id = @request.auth.id \|\| ADMIN` |

On `group_invites`, the ADMIN clause correlates the invite row's `conversation_id` with the admin's member row in that conversation — verified same-row `?=` semantics apply.

### conversation_members.createRule extension (self-join)

```
@request.auth.id != "" && (
  @request.auth.id = conversation_id.created_by
  || ADMIN
  || (@request.auth.id = user_id
      && @collection.group_invites.conversation_id ?= conversation_id
      && @collection.group_invites.invited_user_id ?= @request.auth.id
      && @collection.group_invites.status ?= "pending")
)
```

Self-join pins `user_id = @request.auth.id` (own row only) and requires a pending invite for THIS user in THIS conversation. Non-invited users are rejected.

### Unchanged

`messages.createRule`, `conversation_members` view/update/delete rules, `group_keys` rules — already fixed and live (2026-09-24).

## Client changes (Flutter)

### Admin side

- `addMemberToGroup` → `sendGroupInvite(conversationId, userId)`:
  - admin check (existing `isCurrentUserAdmin`)
  - idempotent: fetch invite for (conv, user) → exists ? PATCH status=`pending` : CREATE `pending`
  - NO key rotation, NO public-key fetch, NO system message at invite time
- Add-member picker: per-user chips from this conversation's `group_invites` — `Pending`, `Declined` (with re-invite action). Toast "Invite sent".
- `removeMemberFromGroup` addition: **purge or decline any invites for the removed user in that conversation** (their deleteRule/updateRule allows ADMIN). Without this, a still-pending invite lets a removed member self-rejoin — security hole.
- Auto-rotate: on SSE `conversation_members` create (and sync backfill path) where conversation is a group, my role=admin, and the new member is not me → debounced (~3s per conversation) single `_rotateGroupKey`.

### Invitee side

- Repository subscribes to `group_invites` (SSE + existing poll fallback).
- Requests surface (same as friend requests): card "X invited you to join <group>" with Accept / Decline.
- Accept (self-join):
  1. create own `conversation_members` row (user_id=me, role=member)
  2. PATCH invite → `accepted`
  3. emit system message "Y joined the group" (member now; messages.createRule passes)
  4. local upsert of member row; conversation appears via existing sync; card leaves pending list
  - If member-row create fails with the UNIQUE(conversation_id,user_id) constraint (already a member via another path), treat as joined: mark invite accepted.
- Decline: PATCH invite → `declined`. Nothing else.

### FCM push

Extend the VM's `fcm_notify.pb.js` (existing friend-request push pattern) to push on `group_invites` create / update-to-pending: channel `kb_requests`, title "Group invite", body "<inviter> invited you to <group>". Tap opens the app (requests surface).

## Edge cases

- **Accept with no admin device online**: membership is instant; the group key arrives at the next admin-device rotation; messages sent in that window stay undecryptable for the joiner. Accepted limitation (short window in practice; same risk class as today's offline-admin remove flow).
- **Two admins auto-rotate simultaneously**: two key versions; members converge on the highest version (existing rotation behavior).
- **Removed member with a pending invite**: covered by the remove-flow invite purge above.
- **Invitee deleted/re-installed app**: pending invite rows persist server-side; fresh install re-syncs invites with other data.

## Testing / pass criteria

Server rule probes (superuser impersonation, as used 2026-09-24):
- non-admin invite-create rejected
- invitee self-join works only with own pending invite; cannot accept others' invites
- plain member cannot list others' invites; admin can list invites of their conversation

2-device end-to-end:
1. invite → invitee sees request card (+push) → accept → instantly a member, "Y joined the group" bubble, can send, reads messages once rotation lands
2. decline → admin picker shows "Declined" chip → re-invite works
3. remove still works end-to-end (re-test from 2026-09-24 fix) and removes any pending invite of the removed user (no self-rejoin)
4. no regressions: receipts, system bubbles, live media
