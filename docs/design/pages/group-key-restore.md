# Group keys: fast first download (spec, rev 1)

Status: **spec PASS 2026-11-12, all defaults (D1 A, D2 no, D3 not now, D4 not needed).** Follow-up to
`docs/design/pages/history-sync.md` (S1 + S4, built, uncommitted). Device
run 1 of that build (M52, release, mobile data) restored 26 chats / 648
messages in 79 s; six group chats with 1–8 messages each took 5.4–12.2 s
apiece, about 46 s of the 79 s, while making only 3 sync requests each.
Nothing visible changes except the wait. No live server change and no
server read are needed for this build.

## Why it is slow (code read, 2026-11-12)

Group history is opened with a list of every group key version this user
was ever given. `syncAllHistory` gets it per chat through
`_getConvKeyCandidates` (`message_repository_impl.dart:3382` → `:6215-6231`)
→ `getOrFetchGroupKeyCandidates` (`encryption_service.dart:610-734`). On a
fresh install nothing is cached, so it takes the network path, a **walk**:

| Cost | Count | Where |
|---|---|---|
| `group_keys` list, mine only, newest first, with the wrapper's whole user record expanded | **1 request per walk** (not per version) | `encryption_service.dart:647-653` |
| Transport key lookup: a secure-storage read (platform channel) | **per version** | `decryptGroupKey` `:371` → `getOrDeriveConversationKey` `:250` |
| First time per wrapper key: 2 more storage reads, ECDH + HKDF in an isolate, 1 storage write (the `[Enc] Deriving key for conv: <id>_gk` line) | per distinct wrapper public key | `:255-274` |
| AES-GCM attempt in its own `compute()` isolate | **1 isolate hop per version** | `:375` → `decryptMessage` `:305` → `decryptBatch` `:318-324` |
| Version that opens: 1–2 secure-storage writes, repeated on **every** walk even when the slot already holds that key; 1 more base write after the loop | per good version, per walk | `:677-689`, `:703-706` |
| Version that fails: one `Skipping undecryptable group key version` line, nothing remembered | per bad version, per walk | `:691-693` |
| No version opens → `MissingKeyException` → the sync **walks again twice**, sleeping 400 + 800 ms | 3 walks + 1.2 s per such group | `syncAllHistory` `:3380-3390`; `_getConvKeyCandidates` `:6226-6227` wraps every error as `MissingKeyException`, so a server answer of "nothing opens" looks the same as a dropped connection |

So a version costs **no request**, but one isolate hop and at least one
secure-storage read, every walk. Secure storage is the slow part on these
phones: the comment at `encryption_service.dart:413-415` records per-chat
platform-channel reads costing the M52 ~30 s per warm prefetch, which is why
the group-key slots were moved into memory (C, 2026-10-14). The transport
key cache was not moved and is still read once per version.

A group where nothing opens pays 3 requests, 3 × N hops and reads, and
1.2 s of sleep, and its messages still land `key_missing`. 94 skip lines on
the M52 over six groups (69 on the Redmi) is about 16 per group: consistent
with a few all-dead groups walked three times. The phones' log buffers had
rotated by the time of this read, so the per-group split is not known; the
build adds a timing line (G6) to measure it.

Also seen in run 1, before the restore finished:
`[Msg] group-key prefetch failed … no decryptable group key`. Prefetch
(`prefetchGroupKeys` `message_repository_impl.dart:925-963`, started by
`_syncConversationsBackground` `:809-820` on any conversation or member
event) walks every group while the device key pair is still missing. Every
version then fails inside `getOrDeriveConversationKey` (`:255-258`, "no
device key pair"), is caught as a skipped version, and the walk ends with
the same "no decryptable group key". Requests and storage reads for nothing,
competing with the restore.

### Why most versions do not open

The server list is already filtered to `user_id = me` (`:650`), so every
row was wrapped **for this user** while they were a member: there are no
"versions from before I joined" in it. A row is wrapped with
ECDH(wrapper's private key, my public key at that time)
(`encryptGroupKeyForMember` `:348-359`, rotation `:3980-3993` reads each
member's public key live from the server). It is unwrapped with
ECDH(my private key now, the wrapper's public key **now**, from the expand)
(`:661-669`). A row stays dead when either side's key pair changed after it
was wrapped:

1. **My key changed.** Before the K1 fix (`850fe34`, 2026-10-29) every sign-in
   on a fresh install made and published a new key pair before the restore;
   any rotation in that window wrapped for the temporary key, and the restore
   then put the old one back (`restorePrivateKey` `:937-949`).
2. **The wrapper's key changed** the same way (reinstall before K1, the
   regenerate-on-mismatch during an account switch), or the wrapper's phone
   held a different key pair from the one on the server when it rotated (two
   phones on one account). Then every row that phone wrapped is dead for
   everyone.

The test accounts have done both many times; friends' accounts went through
the K1-era sign-ins too. Rotations come often (each join `:601-627`, each
key-gap reconcile on an admin's resume `:4466-4519`, each leave or removal),
so dead versions pile up. Which of the two causes applies per row cannot be
told from the client: the row stores the wrapper's user id, not the public
keys used. The fix below does not depend on it. A read-only server check
(D4) can confirm it.

Dead rows can never open again unless the same key pair comes back, so
walking them is pure cost.

## Behaviour (what the user sees)

| # | Case | After this build |
|---|---|---|
| G-B1 | Restore after sign-in | Same screens and steps; group chats take about as long as a DM. |
| G-B2 | Group history | Exactly the messages the old code could open open; the ones it could not stay locked (same placeholder). |
| G-B3 | Sending in a group | Unchanged: still refuses to send unless the newest server version opens (`requireCurrent`, `:695-699`). |
| G-B4 | Before the recovery key is entered | No group-key requests at all. |
| G-B5 | Offline or a request fails | Same as today: cached keys answer, a cold group retries, rows still land. |

Target (shared with history-sync, measured in the device check): **restore
to Home under 60 s on the Redmi over mobile data**; on the M52 each group
chat under 2 s and the run 1 restore (79 s) about 35–45 s (estimate:
46 s of group time minus ~5 requests per chat at mobile-data latency).

## Changes

### G1: one walk per group when the server has answered

1. New `class NoGroupKeyException extends MissingKeyException`, thrown at
   `encryption_service.dart:723` instead of the plain one: the server
   answered and no version opened. Only thrown when the device key pair
   exists (G4 guarantees it).
2. `_getConvKeyCandidates` (`:6224-6228`) lets a `MissingKeyException`
   (and so this subtype) through unwrapped; other errors are wrapped as today.
3. `syncAllHistory`'s retry loop (`:3380-3390`) stops at once on
   `NoGroupKeyException`: no second walk, no sleep. A dropped connection or
   a missing DM peer key still gets the 3 tries (the reason that loop exists).

### G2: one isolate hop per wrapper key, not per version

In the network path of `getOrFetchGroupKeyCandidates` (`:644-694`):

1. Group the rows by the wrapper's public key (rows with an empty one are
   skipped, as today `:663`).
2. Per group: `getOrDeriveConversationKey('${convId}_gk', pub)` **once**
   (one storage read, or one derive the first time), then **one**
   `decryptBatch(transportKey, rows)` with the record ids as item ids
   (the batch call already exists, `:318`).
3. Results go back in server order (newest version first), so
   `newestKey`, `cachedCurrent`, the merge with cached candidates,
   `requireCurrent` and `onGroupKeysRefreshed` behave exactly as today.
4. The per-version skip line becomes one summary line (G6).

A failed AES-GCM tag inside a batch costs microseconds, so dead versions
become free without remembering them (D2).

### G3: write a key slot only when it changed

Before each `group_key_<conv>_<version>` and base-slot write (`:677-689`,
`:703-706`), compare with the memory map (`_memGroupKeys`, already loaded by
`_readLocalCandidates` at entry). Same value → no storage write. Today every
background revalidation (each chat open, `:503-520`) rewrites every good
version.

### G4: no walk without the device key pair

At the top of the network path (`:644`), if `_readKeyPair()` is null, throw
`MissingKeyException('no device key pair (restore pending)')` before any
request. Same outcome as today (today the walk ends in the same exception,
and `:725` rethrows it even with a cache), minus the request and the per-row
reads. Covers prefetch, the decrypt pass and background revalidation in one
place.

### G5: ask only for the fields used

The list request (`:647-653`) adds
`fields: 'key_version,encrypted_key,expand.encrypted_by_user_id.public_key'`.
Today the expand returns the wrapper's whole user record per row. Smaller
response on mobile data, and less of other people's account data on the
phone.

### G6: timing line

One `debugPrint` per walk, no ids and no key material:
`[Enc] group keys versions=16 opened=3 hops=2 ms=140`. Replaces the per-row
skip lines. The `[Sync] chat` line stays as is.

## Decisions (defaults in bold)

| # | Question | Options |
|---|---|---|
| D1 | Retry rule for a group whose versions all fail while online (G1). | **A: no retry, rows land `key_missing`, a later key growth re-runs them (`decrypt_pass.dart:104-128`)** · B: keep 3 tries |
| D2 | Remember dead versions between walks? | **No: G2 makes them nearly free** · in-memory skip set per process · stored skip set (survives restarts, more code, must be cleared when a key pair changes) |
| D3 | Share one in-flight walk per group between sync, prefetch and the decrypt pass? | **Not now**: G4 removes the overlap run 1 showed; add only if the G6 line shows two walks of one group at once · yes, a per-group future map |
| D4 | Confirm why versions are dead with a read-only server check (the test account's `group_keys` rows in the six groups: version, wrapper, created, compared with known key changes)? | **Not needed for this build**; ask separately if you want the cause proven · yes, before the build (needs your yes for the live read) |

## Found while specifying (not built here)

- **Dead versions are permanent, and so are the messages under them.** A
  message sent under a version that does not open for this user never
  decrypts on this account. Cleaning dead rows, or storing the wrapper's and
  member's public-key fingerprint on each row so a phone can tell instantly,
  is a live server change and its own spec.
- **Rotate-on-join before the restore** (`message_repository_impl.dart:619-625`):
  run 1 logged `auto-rotate on join failed: … no device key pair`. The
  rotation reads members, versions and every member's user record
  (`:3956-3984`) before failing at the first wrap; it writes nothing, and the
  key-gap reconcile (`:4377`) covers the joiner later. A key-pair check first
  would save those requests.
- `_rotateGroupKeyNow` clears `contact_key_${convId}_gk` (`:4036`), but the
  transport key is cached as `contact_key_${convId}_gk_<public key>`
  (`encryption_service.dart:249`, `:354`): the line writes an unused slot and
  clears nothing.
- History ingest tries each good group key in its own isolate hop per
  message (`message_repository_impl.dart:5383-5388`). Cheap for these small
  groups; a big group with many good versions pays messages × versions hops.
  That is history-sync S2 (batch decrypt).

## Must not undo

- Send path: `requireCurrent` still refuses to send under a stale key
  (`group_key_local_first_test.dart` B).
- Local-first display path: a cached group answers without the network and
  still revalidates in the background (A, C there).
- Key growth re-runs the rows the old set could not open (D there,
  `decrypt_pass.dart:104-128`).
- Memory map write-through rules (`encryption_service.dart:417-425`,
  `key_memory_cache_test.dart`).
- K1: decrypt paths never create a key pair (`_readKeyPair`, `:195-197`).
- History rows land even when no key opens (history-sync H5, Task 7).

## Test gates

New (group-key tests next to `test/offline/group_key_local_first_test.dart`,
its `keyClient` MockClient and `FakeSecureStorage` from `char_harness.dart`;
add a write counter to the fake if it has none, and a `@visibleForTesting`
hop counter on the service like `DecryptPass.isolateCalls`):

1. G2: 16 rows from 2 wrapper keys, 3 of them wrapped with the right keys →
   **1** `group_keys` request, **2** decrypt hops, **≤ 2** transport-key
   storage reads, candidates = the 3 keys newest first, versioned slots
   written for exactly those 3.
2. G3: a second walk with the same server answer → **0** storage writes; a
   new version appearing → exactly its slot (and the base) written.
3. G1: `syncAllHistory` with one group whose rows all fail → **1**
   `group_keys` request, no 400/800 ms wait (fake async), all rows land
   `key_missing`. Same group with the `group_keys` request failing (500 or a
   dropped connection) → still 3 tries.
4. G4: no device key pair → **0** `group_keys` requests from
   `getOrFetchGroupKeyCandidates` and from `prefetchGroupKeys`; the throw is
   a `MissingKeyException`, not `NoGroupKeyException`.
5. G5: the request carries the `fields` value; a response with only those
   fields still opens the keys.
6. `requireCurrent: true` with the newest version dead and an older one good
   → still throws (regression pin).

Existing, must stay green: `test/offline/group_key_local_first_test.dart`,
`test/offline/key_memory_cache_test.dart`,
`test/offline/idempotent_ingest_test.dart`,
`test/offline/history_sync_test.dart`, `test/auth/restore_overlay_test.dart`.
Full `flutter test` green against the baseline taken at build start;
`flutter analyze` 0 errors.

## Device check list (you do every sign-in)

Test account pair from two-device testing, never your real chats. Release
or profile build so `[Sync]` and `[Enc] group keys` lines show
(`adb logcat | grep -E "\[Sync\]|group keys"`).

1. M52 on **mobile data**, clear app data, sign in, restore (same account
   as run 1). Each group chat's `[Sync] chat` line under 2 s; total well
   under run 1's 79 s. Note the `[Enc] group keys` lines (versions, opened).
2. Redmi on **mobile data**, same steps: restore to Home **under 60 s**.
3. Before entering the recovery key, wait 30 s on that screen: no
   `group keys` line appears until after Restore.
4. Open each of the six groups: the same messages open as before this build
   (compare with the other phone or a screenshot from run 1); none newly
   locked.
5. Send a message in two groups from each phone: the other phone reads it.
6. In one test group, remove the other phone's account and add it back:
   new messages read on both phones.
7. Airplane mode mid-restore, then back on: history still lands, no crash.

## Out of scope

Server cleanup of dead rows, a fingerprint column, any live server read or
change; history-sync S2, S3, S5; the restore screen's design.
