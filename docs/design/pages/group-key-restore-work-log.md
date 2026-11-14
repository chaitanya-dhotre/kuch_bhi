# Group keys: fast first download (G1–G6): implementation work log

Date: 2026-11-12.
Scope: `docs/design/pages/group-key-restore.md` (spec PASS 2026-11-12, all defaults: D1 A no
retry when the server answered, D2 no dead-version memo, D3 no single-flight, D4 no live read).
Follow-up to history-sync S1 + S4 (`history-sync-work-log.md`, uncommitted in this checkout).
Built by Claude. No live PocketBase read or write.

## Status

| Step | Result |
|---|---|
| Spec | user PASS 2026-11-12, all defaults |
| Implementation | DONE 2026-11-12, G1–G6 |
| Gates | baseline `flutter test` **1263/1263** (taken first; includes the uncommitted history-sync and mascot work in this checkout) → after **1272/1272** (+9, all in `test/offline/group_key_restore_test.dart`). First full run with the spec's G4 had 48 failures in 12 send/outbox files; fixed by the G4 narrowing below, then the whole suite was green · the 5 listed existing files green · `flutter analyze` 0 errors, no issue in the new test file; the two warnings in the touched lib files (`message_repository_impl.dart:3869` admin check, `encryption_service.dart:447` cast in `_loadGroupKeyMem`) were already there · gate 3 mutation-checked (re-adding the sleep-and-retry on `NoGroupKeyException` fails it) |
| Device check | not run. List below, for the user, M52 + Redmi on mobile data |
| Commit | none. After the user's device PASS and only when the user says: one commit with `group-key-restore.md`, this log, `.trail/learnings/2026-11-12-group-chats-are-slow-on-first-chaitanya.md`, the two code files and the three test files. The repository file also holds the uncommitted history-sync S1 + S4 build; commit order with it is the user's call. |

## What changed

`lib/services/encryption_service.dart`

- **G1** `NoGroupKeyException extends MissingKeyException`: thrown at the end of the network
  path of `getOrFetchGroupKeyCandidates` when the server answered and no version opened. Every
  existing `on MissingKeyException` catch still catches it.
- **G4** the network path starts with: no cached key **and** `_readKeyPair()` null →
  `MissingKeyException('no device key pair (restore pending)')` before any request.
  Deviation from the spec (narrower): the spec's version checked the key pair alone. That broke
  48 existing tests in 12 files (outbox, media, album, sticker, cancel sends): a cached group
  key, no key pair, and a `group_keys` request that fails. Today that request failure falls
  back to the cache; skipping the request turned it into a throw, which is not the "same outcome
  as today" the spec promises. With the cache condition, every case with a cache behaves exactly
  as before, and the case G4 is for (fresh install, restore pending: nothing cached yet) skips
  the walk as specified. The check sits inside the `try`, so the existing
  rethrow-on-`MissingKeyException` rule applies.
- **G5** the `group_keys` list sends
  `fields: key_version,encrypted_key,expand.encrypted_by_user_id.public_key` (constant
  `EncryptionService.groupKeyFields`). `expand` stays (PocketBase needs it to expand).
- **G2** rows are grouped by the wrapper's public key (empty key or an `encrypted_key` that is
  not `iv:ciphertext` → skipped, as before). Per wrapper: one `getOrDeriveConversationKey
  ('${conv}_gk', pub)` and one `decryptBatch`. Results are read back in server order, so
  `newestKey`, the base slot, the merge with cached candidates, `requireCurrent` and
  `onGroupKeysRefreshed` are unchanged. A wrapper whose transport key fails is skipped with one
  line (was one line per version).
  Deviation from the spec's wording ("record ids as item ids"): item ids are list indexes,
  because the G5 `fields` value leaves the record id out of the response.
- **G3** `_putSlotIfChanged(conv, slot, value)`: writes a versioned or base slot only when the
  memory map does not already hold that value; the write-through order (disk, then memory) is
  the same as before. The base write after the loop now goes through it too (it always repeated
  the in-loop write).
- **G6** one `[Enc] group keys versions= opened= hops= ms=` line per walk (no ids, no key
  material), printed before the `requireCurrent` check. `opened` counts versions that opened,
  `hops` the decrypt batches. The per-version skip line is gone.
- `@visibleForTesting int groupKeyHops`: decrypt hops spent by walks (the hop counter the spec
  asks for, like `DecryptPass.isolateCalls`).
- `decryptGroupKey` deleted: the walk was its only caller.

`lib/infrastructure/repositories/message_repository_impl.dart` (two small hunks, nothing else
touched)

- **G1** `_getConvKeyCandidates`: `on MissingKeyException { rethrow; }` before the wrapping
  catch, so `NoGroupKeyException` reaches the caller unwrapped; other errors are wrapped as
  before.
- **G1** `syncAllHistory` key loop: `on NoGroupKeyException { break; }` before the
  `MissingKeyException` retry. A dropped connection, a 500, a missing DM peer key and G4's
  no-key-pair throw still get the 3 tries with 400 + 800 ms.

## Tests

New `test/offline/group_key_restore_test.dart` (charHarness + a MockClient server; every
`group_keys` row in the fixture is the G5 fields-only shape):

1. Gate 1 (G2): 16 rows v16..v1, wrappers alternate me / another key, v14 / v9 / v3 open →
   **1** request, **2** hops, **≤ 2** transport-key reads, candidates `[v14, v9, v3]`,
   versioned slots written for exactly those 3, base = v14.
2. Gate 2 (G3): a second walk with the same answer → **0** storage writes; a new v17 → writes
   exactly `group_key_g1_17` and `group_key_g1`.
3. Gate 3 (G1): `syncAllHistory` with a cold group whose 4 rows are all dead → **1**
   `group_keys` request, sync under 1.2 s, 3 messages land `key_missing`. Same group with
   `group_keys` answering 500 → **3** requests, rows still land.
   Deviation: no fake async. The 400 / 800 ms sleeps sit between walks, so 1 request proves no
   sleep; fake async does not drive the `compute()` isolates the sync uses.
4. Gate 4 (G4): no device key pair → `getOrFetchGroupKeyCandidates` throws a
   `MissingKeyException` that is not a `NoGroupKeyException`, **0** requests;
   `prefetchGroupKeys` on a cold group → **0** requests. Plus a pin for the narrowing: no key
   pair, a cached key, `group_keys` answering 500, `requireCurrent: true` → the cached key.
5. Gate 5 (G5): the request's `fields` query value; the fields-only answer opens 3 keys.
6. Gate 6: `requireCurrent: true` with v16 dead and v14 good → throws (also through
   `getOrFetchGroupKey`).

`test/offline/char_harness.dart`: `FakeSecureStorage` gains `writes` (keys written through
`write` / `saveContactEncryptionKey`, not the test-only `put`) and `contactKeyReads`.

`test/offline/group_key_local_first_test.dart`: D1-negative now creates the device key pair
first (`getPublicKeyBase64()`). It expected a `group_keys` request from a cold group in a harness
that never had a key pair; G4 stops that walk before the request, which is the change. Its
assertions are unchanged.

## Device check list (user, every sign-in)

Test account pair from two-device testing, never your real chats. Release or profile build so
`[Sync]` and `[Enc] group keys` lines show (`adb logcat | grep -E "\[Sync\]|group keys"`).

1. M52 on **mobile data**, clear app data, sign in, restore (same account as run 1). Each group
   chat's `[Sync] chat` line under 2 s; total well under run 1's 79 s. Note the
   `[Enc] group keys` lines (versions, opened).
2. Redmi on **mobile data**, same steps: restore to Home **under 60 s**.
3. Before entering the recovery key, wait 30 s on that screen: no `group keys` line appears
   until after Restore.
4. Open each of the six groups: the same messages open as before this build (compare with the
   other phone or a screenshot from run 1); none newly locked.
5. Send a message in two groups from each phone: the other phone reads it.
6. In one test group, remove the other phone's account and add it back: new messages read on
   both phones.
7. Airplane mode mid-restore, then back on: history still lands, no crash.
