# Group Invites Rework — Design (W2 delta)

Date: 2026-10-03. Supersedes the gaps left by `2026-09-24-group-invites-design.md`
(its happy path shipped; this doc covers the on-device findings).

## Context — verified root causes (2026-10-03)

1. **Invites were dead server-side**: every `group_invites` create returned an
   opaque 400 since the 24 Sep hook deploy (PB process held a broken hook
   state). The client caller swallowed all errors and toasted
   "Invite(s) sent" → false success. Fixed 3 Oct by reloading the instrumented
   hook; verified live: create / decline / re-invite all 200, user confirmed
   cards + accepts on device.
2. **New members see pre-join history as 🔒 garbage.** Key rotation on join
   gives the joiner only the current key; pre-join messages are undecryptable
   by design — but the client shows them anyway.
3. **Rotation requires an admin device online.** If all admins miss the
   live SSE member-create event, rotation never happens: joiner can't read or
   send; old members chat unaffected.
4. **Rejoin-after-leave is broken.** `acceptGroupInvite` tolerates the
   UNIQUE-duplicate member row, but the row keeps `role = 'left'` → the
   rejoined member cannot send.
5. **CM updateRule hole**: any member can update any member row of their
   conversation (self-promotion to admin possible).
6. **No invite management UI**: admins cannot see/cancel pending invites in
   group info.

## Decisions (user-approved 2026-10-03)

- **Option A — Signal-style history cutoff.** New members never see
  pre-join content. Rejected alternative: key-archive distribution (complex,
  weakens rotation).
- **Admin resume reconciliation** for missed rotations.
- **Keyless-joiner UX**: banner + disabled composer, not silent pending.
- **Error surfacing**: no more false-success toasts.

## Design

### D1. History cutoff (client-only — amended 2026-10-03 during T1)

- **Server-side cutoff is NOT expressible on this PB build.** Back-reference
  rules support only `?=` (equality); a bare `@collection…created <= created`
  comparison evaluates as FOR-ALL over every member row of the conversation,
  which erased old members' history (probe: 76 → 0 rows). `messages`
  list/viewRule stay at the original member-visibility rule.
- Protection model: pre-join rows are undecryptable by the joiner (they never
  receive superseded key versions) — the crypto IS the barrier; the raw API
  exposes only opaque ciphertext + metadata to a member. Same class of
  guarantee as Signal's server behavior for non-delivered history.
- Client: `watchMessages` path hides (a) rows older than the local member
  `joinedAt`, (b) non-media rows with null `decryptedBody` (never render
  ciphertext — also hides the FCM background-isolate placeholder flash).
- Local `joinedAt` sync fix: fall back to the server CM row `created`
  (autodate, true join time) — today's sync maps the never-set `joined_at`
  field to `DateTime.now()` (sync time), which is wrong.
- Kept from the T1 rule patch (verified by probes): `conversation_members.updateRule`
  hardening (role changes admin-only — blocks member self-promotion) and
  `group_keys.listRule` admin access (needed by D2).

### D2. Admin resume key reconciliation

On `resyncOnResume`: for every group where I'm admin, fetch server members +
group_keys (listRule extended to let conv admins list rows — encrypted per
recipient, useless to the admin), diff → members with no key row or a stale
version → if I'm the elected rotation owner (`_isRotationOwner`) → debounced
`_rotateGroupKey`. Pure diff function is unit-tested.

### D3. Keyless-joiner UX

`groupKeyReadyProvider` (poll 3s while false). Chat screen: group + keyless →
banner "Waiting for group key from a group admin…" + composer disabled
(reuses `canSend`/`restrictionMessage` gating). Join bubble emission stays
as-is (`_emitJoinedWhenKeyReady`).

### D4. Rejoin (amended during T5 — no code needed)

Rejoin-after-leave works natively: `leaveGroup` DELETES the server member row
(only local Drift keeps `role='left'` for UI gating — the server role select
doesn't even contain a `left` value), so a re-accept creates a fresh member
row (`role=member`, `created=accept time`) and the next `_syncConversations`
overwrites the local `left` role. The planned server hook flip was dead code
(role='left' is impossible server-side) and was dropped.

**Hook pitfall (root cause of the whole invite outage, verified by A/B
probe):** a PB JS hook whose callback returns a helper function's return
value (`return notifyInvite(e.record, e)`) breaks every create/update on that
collection with an opaque 400 on this PB build. Hooks must be FLAT — direct
`return e.next()` inside the arrow body (mirror `fcm_notify.pb.js`). Also:
never deploy hook files through unquoted SSH heredocs — `$app` gets expanded
away by the remote shell (the 3 Oct first redeploy did exactly that).
Use scp.

### D5. CM updateRule hardening

Role changes require a conv admin; members may update only their own row and
may not set `role` (blocks self-promotion; keeps last_read writes working).

### D6. Invite management UI

Group settings (admin): "Invites" section — pending list with **Cancel**
(delete row; deleteRule already allows admin), declined with **Re-invite**
(reuse `sendGroupInvite` flip-to-pending).

### D7. Error surfacing

Invite send loop reports per-user failures ("Invited 2, failed 1 — try
again"); decline handler gets the same catch/notify treatment as accept.

## Out of scope (logged for W1/backlog)

- **Rejoin history loss (user-reported 2026-10-04):** a member who leaves
  and rejoins loses visibility of messages sent during their FIRST
  membership stint — the cutoff uses the member row `created`, and rejoin
  creates a fresh row. Fix needs join-history that survives leave/rejoin
  (e.g. `first_joined_at` carried across, or soft-deleted member rows).
- Key-archive for reinstall history decryption (old versions are deleted on
  rotate; already-lost keys stay lost).
- Rotation-gap messages (sent pre-rotation while keyless) remain hidden for
  the joiner — client hides undecryptable rows; server still stores them.
- Media bubbles in the keyless window keep the download placeholder.
- Leaver-triggered rotation unblocks a keyless joiner (leaveGroup rotates and
  distributes the new key to remaining members) — correct, but the keyless
  banner clears without an admin coming online; copy may confuse.
- `_fetchAndCacheConversation` syncs members via `getList` (30-row default
  cap) — groups with >30 members truncate; the other sync path uses
  getFullList.
