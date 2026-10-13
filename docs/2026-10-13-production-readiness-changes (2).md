# Production Readiness Changes — 2026-10-13

## Scope

This document records the group-messaging production-readiness work completed
on 2026-10-13.

Primary incident:

> A group member whose app was stopped or whose local cache was cleared could
> reopen the group and see only post-rotation messages.

The investigation covered:

- group-key schema and API rules;
- group creation;
- member join, leave, removal, and rejoin paths;
- key rotation and version allocation;
- message fetch, pagination, and cache hydration;
- local membership-history cutoffs;
- historical-key retrieval;
- decrypt passes and repair passes;
- PocketBase live data and permissions.

No git commit was created. The working tree contained unrelated pre-existing
changes and untracked files; they were preserved.

## Root causes found

### Client-side root causes

1. Cold message fetch intentionally loaded only the newest 40 rows. Older
   messages required pagination.
2. Initial batched fetch used only the newest group key. Historical ciphertext
   failed decryption and became hidden before the multi-key lazy decrypt pass
   could run.
3. Repair logic retried with one fresh key, not all retained historical keys.
4. Group-key history retrieval was capped at 200 records.
5. Versioned local key slots were written but not fully used for offline
   candidate recovery.
6. A stale cached current key could be used for outgoing encryption after a
   server-side rotation.
7. Missing group public keys were silently skipped during creation/rotation.
8. Rotation collision handling could overwrite another concurrent rotation's
   envelope with ciphertext for a different random key.
9. Leave membership deletion errors were swallowed before rotation.
10. Leave/removal paths could emit a false lifecycle message or leave stale
    active-key material in local storage.
11. Missing local group membership could cause the history cutoff to be null;
    the read path did not fail closed.
12. Local cutoff values could remain stale across membership reconciliation.
13. Group creation used device-local timestamps instead of server membership
    timestamps for history boundaries.
14. Multi-request group creation could leave a partial server group after a
    later request failed.

### Live backend root causes

1. `group_keys.createRule` allowed any authenticated user to create key rows.
2. `group_keys.updateRule` allowed any authenticated user to rewrite key rows.
3. `group_keys` relation fields and `key_version` were optional despite the
   client contract requiring them.
4. `group_keys.viewRule` did not match the intended admin-access model.
5. `messages.deleteRule` was open/blank.
6. `messages.updateRule` allowed overly broad member updates.
7. `conversations.deleteRule` was open/blank.
8. No server transaction could atomically combine membership removal with
   client-generated E2E key rotation.
9. The deployed invite hook comment claimed rejoin repair, but the hook only
   sent invite notifications.

## Client changes

### Historical key retrieval

File: `lib/services/encryption_service.dart`

- Added complete group-key candidate hydration.
- Reads all retained key versions instead of a maximum 200 rows.
- Uses descending server `key_version` order when online.
- Keeps the newest server key first for authoritative current-key use.
- Retains older versions for historical message decryption.
- Reads versioned secure-storage slots for offline recovery.
- Rejects an empty or undecryptable successful server response instead of
  silently using a stale cached key.
- Added a local-only cached-key lookup for immediate offline optimistic
  enqueue.
- Preserved zero-key hard failure behavior.

Important distinction:

- Optimistic enqueue may use a locally cached key without network I/O.
- The outbox drain re-resolves the authoritative current key before server
  publication.

### Multi-key fetch and decrypt paths

File: `lib/infrastructure/repositories/message_repository_impl.dart`

Group-key candidates now flow through:

- cold message fetch;
- warm cursor fetch;
- pagination/load-more fetch;
- single-message fetch;
- full-history synchronization;
- undecrypted-row repair;
- per-record cache hydration.

Each ciphertext is attempted against retained candidate keys. Successful rows
store the fingerprint of the key that actually decrypted them. Unresolved rows
remain retryable instead of becoming terminal failures.

The existing `DecryptPass` multi-key implementation is now reachable from the
paths that previously hid historical rows before lazy decryption could run.

### Group-history visibility

Files:

- `lib/infrastructure/repositories/message_repository_impl.dart`
- `lib/core/utils/group_visibility.dart`

Changes:

- Group rows fail closed when no local membership record exists.
- `createdAt < memberJoinedAt` remains the local pre-join cutoff.
- Membership reconciliation clears cached cutoffs.
- Fresh conversation hydration clears the affected cutoff.
- Local joins use server `joined_at`, then server record `created`, as fallback.

This prevents a fresh-install or membership-sync race from exposing group
history while the local authorization boundary is unknown.

### Rotation hardening

File: `lib/infrastructure/repositories/message_repository_impl.dart`

- Rotation reads current server membership before distributing a key.
- Every current member must have a public key.
- Public-key failures abort rotation instead of silently skipping a member.
- All envelopes are prepared before the first write.
- Concurrent `(conversation, user, version)` collisions no longer overwrite
  an existing envelope with a different random key.
- Rotation retries at a later version after a detected collision.
- Historical key versions are retained.
- Empty groups no longer fail after the last member leaves.
- Key-gap reconciliation rotates groups with no key rows instead of treating
  version zero as complete.

### Leave, removal, and membership safety

File: `lib/infrastructure/repositories/message_repository_impl.dart`

- Removing oneself through the admin-removal path is rejected; the leave path
  must be used.
- Removing the last admin is rejected.
- Removal verifies the target against live server membership.
- Leave membership deletion is no longer swallowed.
- Leave lifecycle messaging occurs after confirmed server deletion but before
  local key cleanup/rotation.
- Removed-member cleanup clears the active local group-key slot while retaining
  historical versions.
- Retry/send gates continue to reject left or removed group members.

File: `lib/data/local/secure_storage/secure_storage_service.dart`

- Added `clearCurrentGroupKey(conversationId)` for group membership-loss
  cleanup.

### Group creation safety

Files:

- `lib/features/groups/screens/create_group_screen.dart`
- `lib/infrastructure/services/group_create_service.dart`

- All selected members are public-key preflighted before conversation creation.
- A missing encryption key aborts creation instead of creating a member who
  cannot receive the initial group key.
- Initial version-one group key is written to both compatibility and versioned
  local slots.
- Server membership timestamps are used for local cutoffs.
- Failed multi-request creation attempts roll back the server conversation and
  local Drift aggregate when possible.
- Added a service method for creator-authorized conversation rollback.

## Tests added or updated

Files:

- `test/offline/decrypt_pass_test.dart`
- `test/offline/char_harness.dart`

Regression coverage added for:

- a pre-rotation ciphertext decrypting from a retained historical key after
  cache hydration;
- versioned secure-storage key fixtures;
- group-key cache cleanup test support.

## Live PocketBase changes

Target:

- SSH host: `100.64.208.55`
- Hostname: `kuch-bhi-network`
- PocketBase: `0.37.5`
- Process bind: `127.0.0.1:8090`

### `group_keys`

Applied live:

- `conversation_id`: required, cascade delete.
- `user_id`: required, cascade delete.
- `encrypted_by_user_id`: required, cascade delete.
- `key_version`: required integer, minimum `1`.
- `createRule`: authenticated group admin and authenticated encryptor.
- `viewRule`: recipient or group admin.
- `updateRule`: locked.
- `deleteRule`: locked.

Existing unique index preserved:

```sql
UNIQUE(conversation_id, user_id, key_version)
```

### `messages`

Applied live:

- Physical delete locked.
- Sender may update only `is_deleted_for_everyone=true`.
- Active group members may update pin state.
- Ciphertext, IV, sender, conversation, message type, reply fields, expiry,
  deletion metadata, and star metadata are guarded from member updates.

### `conversations`

Applied live:

- Delete restricted to the conversation creator.

## Live backups

Backups were created before live metadata changes:

- `/opt/pocketbase/pb_data/data.db.20261013-group-hardening-pre`
- `/opt/pocketbase/pb_hooks.20261013-group-hardening-pre/`

Observed SHA-256 values:

```text
1d666d6a062e6d1b44c170c62cb66ad641699ffa7fa3e230b922398b8a4f8e24  data.db.20261013-group-hardening-pre
1c5f51451160a711ba07ff4e7828a1878d4b1ccf03203d32364297132413d31f  pb_hooks.20261013-group-hardening-pre/group_invite_notify.pb.js
```

## Verification performed

### Local static analysis

Command:

```bash
/home/chaitanyadhotre/flutter/bin/flutter analyze --no-pub
```

Result:

- zero errors;
- warnings/info diagnostics remain, predominantly pre-existing deprecations,
  async-context warnings, and unrelated lint findings.

### Targeted tests

Command:

```bash
/home/chaitanyadhotre/flutter/bin/flutter test \
  test/group_visibility_test.dart \
  test/key_gap_test.dart \
  test/offline/send_fetch_char_test.dart \
  test/offline/decrypt_pass_test.dart \
  test/offline/always_commit_test.dart
```

Result:

- all targeted tests passed after the optimistic-enqueue regression was fixed;
- an earlier run exposed the regression caused by making current-key fetch
  synchronous on the optimistic path; the fast local-key path corrected it.

### Live invariant checks

Current live checks returned:

- active members missing their group max-version key: `0`;
- duplicate `(conversation_id,user_id,key_version)` tuples: `0`;
- invalid/null group-key contract fields: `0`;
- admin `group_keys` list access: HTTP `200`;
- member own-key list access: HTTP `200`;
- member key update attempt: HTTP `403`;
- member injected-key attempt: no row created.

## Limitations and unresolved risks

### Historical-key loss before this repair

The old client deleted historical key rows during rotation. That data is not
cryptographically reconstructible from message ciphertext alone.

Observed example:

- group: `4chan` (`hnj3vfuhjka7edo`);
- current retained key versions: `16`, `17`;
- messages exist from July;
- older key envelopes are absent.

Required recovery source:

- a database backup containing the old `group_keys` rows;
- or a device that still holds the old group keys in secure storage.

### Rotation is not server-atomic

The server stores encrypted envelopes but cannot prove that envelopes created
by a client all wrap the same random group key. A client can still fail after
some envelopes are written.

Current mitigation:

- all envelopes are prepared before writes;
- create collisions are detected;
- conflicting rotations retry at a later version;
- missing member keys abort before the first write;
- the live `group_keys` update/delete surface is locked.

Required full solution:

- a dedicated server-assisted atomic publication protocol;
- membership snapshot/version precondition;
- one transaction inserting every envelope for the next version;
- client migration from per-row rotation creates to that endpoint.

The server must continue treating encrypted envelopes as opaque. It must never
generate or inspect plaintext group keys.

### Membership deletion and rotation remain separate operations

Deleting a member and rotating the key are separate client/server actions. If
the client loses connectivity after membership deletion but before successful
rotation, the old member may retain an old key until the rotation succeeds.

Required full solution:

- server-side membership state with a pending-revocation epoch;
- message-send blocking while rotation is pending;
- atomic client acknowledgement after all current-member envelopes exist.

### Server-side history cutoff is not enabled

PocketBase `messages` list/view rules still authorize active conversation
members, not `created >= joined_at`.

Reason:

- the previous server-side back-reference cutoff expression evaluated incorrectly
  in PocketBase and erased history for old members;
- the client cutoff plus E2E key possession remains the current boundary.

Required future solution:

- a tested server-side membership-epoch/message-visibility model;
- live probes for old members, new members, rejoiners, and removed members;
- no deployment based only on a back-reference rule experiment.

### Group creation rollback is best effort

Client rollback now attempts to delete the creator-owned conversation and local
Drift aggregate. If the creator loses connectivity after partial creation,
the server may still retain orphan rows until a cleanup job or manual repair.

### Public-key rotation of the distributing admin

Historical envelopes encrypted under an admin's old public key may become
undecryptable if that admin reinstalls and loses the old private key. The
server cannot repair those envelopes without the old private key.

### Pagination behavior

Normal chat open still fetches the newest page first. Older history loads via
the existing pagination path. Full-history sync fetches the entire available
history.

This is intentional for performance. “All history immediately on open” would
require a separate product decision and bounded-history policy.

### Validation gap

Flutter warnings/infos remain. They did not block analysis or targeted tests,
but the repository is not lint-clean.

### No production deployment commit

The local changes and this document are uncommitted. Review the working tree
before committing. Do not stage unrelated existing files.

## Recommended next actions

1. Test two-device scenarios:
   - member app killed before rotation;
   - secure/cache clear before reopen;
   - join during admin offline period;
   - remove member while the removed device is offline;
   - leave and rejoin with the same account;
   - concurrent admin rotations.
2. Add a real server-side atomic key-publication endpoint.
3. Add rotation-pending message blocking.
4. Restore historical keys from backup where required.
5. Decide whether to implement a tested server-side history-visibility model.
6. Run the full Flutter test suite on a machine with the target Android/Flutter
   toolchain before release.
