# Task 8 report — DecryptPass + messageBodyProvider + body cache

**Status: DONE.** RED 5/5 (right reason) → GREEN 5/5 → full suite **119 pass**
(114 + 5) → `flutter analyze` **0 errors, 88 issues (= legacy baseline)**.
Commit subject: `[Offline P4] DecryptPass + messageBodyProvider — lazy,
coalesced, epoch-guarded` (own hash cannot appear in its body).

## Files

| # | File | Change |
|---|------|--------|
| 1 | `lib/core/decrypt/decrypt_pass.dart` | NEW — `DecryptPass` orchestrator + top-level `_decryptBatch` worker (inline + `Isolate.run` lanes) |
| 2 | `lib/core/decrypt/body_cache.dart` | NEW — `BodyCache` LRU (500, move-to-end get/put) + global `bodyCache` |
| 3 | `lib/features/chat/providers/message_body_provider.dart` | NEW — `decryptPassProvider`, `BodyCoalescer` (50ms), `bodyCoalescerProvider`, `messageBodyProvider` |
| 4 | `lib/app.dart` | `bodyCache.clear()` on `inactive`/`paused` (backgrounding, spec §3/amendment 6) |
| 5 | `lib/infrastructure/repositories/message_repository_impl.dart` | `late final DecryptPass decryptPass` built in ctor (`epoch: () => _sessionEpoch` — T5/T6 pattern); `bodyCache.clear()` beside `_sessionEpoch++` (logout/account-switch wipe path) |
| 6 | `test/offline/decrypt_pass_test.dart` | NEW — the 5 named brief tests |

No other files touched. Char tests byte-stable (untouched). No schema change
(T7's `decrypt_state`/`key_id` columns consumed as-is).

## AS-BUILT signatures (handoff for T9 — verbatim)

```dart
// lib/core/decrypt/body_cache.dart
class BodyCache {
  BodyCache({this.maxEntries = 500});          // spec §8 bounded LRU
  final int maxEntries;
  String? get(String id);                      // hit → re-insert as MRU
  void put(String id, String body);            // evicts eldest past max
  void clear();                                // app background + logout wipe
  int get length;
}
final bodyCache = BodyCache();                 // app-wide global

// lib/core/decrypt/decrypt_pass.dart
class DecryptPass {
  DecryptPass({required AppDatabase db, required EncryptionService enc,
      required int Function() epoch});
  @visibleForTesting Future<void> Function()? beforeApply; // async gap seam
  void Function(List<String> appliedIds)? onApplied;       // provider invalidation
  @visibleForTesting int inlineCalls;          // lane counters (test 5)
  @visibleForTesting int isolateCalls;
  Future<void> runFor(List<String> messageIds);
}
// Worker (top-level, sendable in/out):
Future<List<Map<String, Object?>>> _decryptBatch(
    List<Map<String, Object?>> items, List<int> key, String fingerprint);
// outcome tuple = {'id', 'plain', 'state', 'fingerprint'}
//  state: 'ready' | 'failed' | 'key_missing' (keyId mismatch ⇒ requeue)

// lib/features/chat/providers/message_body_provider.dart
final Provider<DecryptPass> decryptPassProvider;  // annotation LOAD-BEARING
//   (reference loop messageBody → coalescer → decryptPass → messageBody;
//    un-annotated inference reports "circularity found during type inference")
final class BodyCoalescer {
  BodyCoalescer(Future<void> Function(List<String>) runFor,
      {Duration window = const Duration(milliseconds: 50)});
  Future<String?> request(String id);   // cache hit instant; miss joins window
  void dispose();
}
final Provider<BodyCoalescer> bodyCoalescerProvider;
final FutureProvider.autoDispose.family<String?, String> messageBodyProvider;
//   body: cache hit → text; else bodyCoalescer.request(id) → runFor → text|null

// Repo (message_repository_impl.dart)
late final DecryptPass decryptPass;   // ctor: epoch: () => _sessionEpoch
// logout/account-switch branch: _sessionEpoch++; bodyCache.clear();
```

### `runFor` row contract (AS-BUILT)

- load `messageIds` (chunked 500) → skip `decrypt_state='failed'` (terminal),
  skip empty / `__pending__` ciphertext (media captions, optimistic rows),
  group by conversation.
- key resolution MAIN-SIDE: group → `enc.getOrFetchGroupKey` (storage cache
  first, network fallback built in); DM → db-cached peer pubkey →
  `enc.getOrDeriveConversationKey`. Failure / key ≠ 32B ⇒ rows (re)marked
  `key_missing` (spec §5.1), no attempt.
- lane: total attempt items ≤50 → inline `await _decryptBatch(...)` on main;
  ≥51 → `Isolate.run(() => _decryptBatch(items, key, fp))` (per-conversation
  group; counters record the lane).
- apply (after optional `beforeApply` gap): **epoch re-checked before EVERY
  db write and before every `bodyCache.put`** (`_stillValid` = T5 style,
  silent drop + `[Decrypt] … dropped — session epoch changed`); writes:
  `ready` ⇒ `decrypt_state` + `key_id` (sha256(key) hex) + cache.put +
  collect; `failed` ⇒ state only; `key_missing` ⇒ state only (skipped when
  unchanged — no drift-stream churn on re-reads); then
  `onApplied(appliedIds)` (wired to `ref.invalidate(messageBodyProvider(id))`).
- Decrypted plaintext goes ONLY into `bodyCache` — `decrypted_body` column
  never written (spec §3 no-plaintext-at-rest; column dropped in T9).

## TDD evidence

**RED** (`flutter test test/offline/decrypt_pass_test.dart`) — 5/5 fail for
the right reason (missing implementations at the named entry points, not
typos; stub files only: `runFor`/provider bodies `throw UnimplementedError`,
`BodyCache` hollow shell):

```
00:00 +0 -1: provider coalescing: 40 reads in one frame → ≤2 runFor invocations (counting decorator seam) [E]
  UnimplementedError: messageBodyProvider — Task 8 in progress
00:00 +0 -2: epoch drop: … apply dropped (DB stays key_missing, cache empty) [E]
  UnimplementedError: DecryptPass.runFor — Task 8 in progress
00:00 +0 -3: bad MAC on lazy path → decrypt_state='failed'; … (terminal) [E]
  UnimplementedError: DecryptPass.runFor — Task 8 in progress
00:00 +0 -4: backgrounding: bodyCache.clear() then re-read … (AsyncValue completes) [E]
  UnimplementedError: messageBodyProvider — Task 8 in progress
00:00 +0 -5: search-style batch of 60 rows → isolate path (≥51) … [E]
  UnimplementedError: DecryptPass.runFor — Task 8 in progress
00:00 +0 -5: Some tests failed.
```

(Test file first needed a compile fix before RED could fire: harness field
is `h.encryption`, not `h.enc` — typo, corrected pre-RED; RED itself is the
UnimplementedError run above.)

**GREEN** (after implementing):

```
00:00 +0: provider coalescing: 40 reads in one frame → ≤2 runFor invocations (counting decorator seam)
00:00 +1: epoch drop: … apply dropped (DB stays key_missing, cache empty)
[Decrypt] apply m_ep dropped — session epoch changed
00:00 +2: bad MAC on lazy path → decrypt_state='failed'; … (terminal)
00:00 +3: backgrounding: bodyCache.clear() then re-read → provider re-decrypts and emits (AsyncValue completes)
00:00 +4: search-style batch of 60 rows → isolate path (≥51) lands all bodies; ≤50 batch takes the inline lane
00:00 +5: All tests passed!
```

**Full suite:** `00:07 +119: All tests passed!` (baseline 114 + 5).
**Analyze:** `88 issues found` — 0 errors, count == legacy baseline;
zero issues in the new/edited lines (repo-file hits are the pre-existing
`deprecated_member_use` infos).
**Pistine:** no warnings/stacktraces from the new test (only the expected
`[Decrypt] … dropped` debugPrint — matches the suite's existing debugPrint
norm; the guard log doubles as proof the epoch gate bit).

### Non-vacuousness of the 5 tests

1. coalescing — asserts `1 ≤ runFor ≤ 2` AND all 40 bodies == plaintext AND
   `bodyCache.length == 40` (a no-op implementation fails all three).
2. epoch drop — crypto demonstrably ran (`beforeApply` reached ⇒ async gap
   injected after crypto), then DB `key_missing` + cache empty; CONTROL
   re-run with stable epoch lands `ready` + `key_id` + body (drop was the
   guard, not a stub).
3. bad MAC — after `failed`, ciphertext REPLACED with valid fixture-key
   ciphertext; second runFor must still leave `failed` + empty cache (a
   broken terminal gate would flip it to `ready`).
4. backgrounding — counting decorator `calls: 1 → 2` across the clear
   (a memoized provider stays at 1 and fails).
5. lanes — `isolateCalls==1, inlineCalls==0` for 60 rows, all 60 bodies +
   `ready` + `key_id` non-null; then a ≤50 re-run pins `inlineCalls==1`
   (both lanes proven).

## Corrections vs brief (reality rule)

1. **`message_repository_impl.dart` added to the brief's file list.** Two
   brief-mandated behaviors only exist there: (a) "logout wipe … call
   `bodyCache.clear()` there too" — the existing epoch path IS the repo's
   `authStore.onChange` `_sessionEpoch++` branch; (b) the dispatch-mandated
   T5/T6 epoch seam (`epoch: () => _sessionEpoch`) requires construction
   where the private counter lives (mediaBlobStore/ingestBoundary
   precedent). Provider-side construction would have needed a fake epoch —
   an epoch-unchecked writer would fail review anyway.
2. **`key_id` value = `sha256(keyBytes)` hex.** Spec §5.1 pins the ROLE
   ("key/epoch reference so DecryptPass knows which key to await after
   rotation") but no encoding; plan silent. Chosen because it is the only
   locally computable reference that CHANGES on rotation (the consumer
   spec §8 names: key_id mismatch ⇒ requeue). `group_keys.key_version` is
   server-side and never cached locally — unusable as a local reference.
   Not invented beyond that: no prefix truncation, no composite keys.
3. **Epoch guard = epoch-equality only, no `authValid`.** The Produces
   signature is binding (`db`, `enc`, `epoch` — DecryptPass has no
   PocketBase handle). The B1 case `sessionStillValid`'s authValid adds is
   the logout/account-switch wipe — which bumps `_sessionEpoch`, so it is
   covered; token expiry without identity change does not wipe the DB.
   Guard style otherwise copies T5 `_stillValid` verbatim (capture at
   schedule, re-check before EVERY write, silent drop + debugPrint).
4. **`decrypted_body` NOT written by apply.** Spec §8: "DB state writes +
   body-cache population" — state = `decrypt_state`/`key_id`; plaintext
   goes only to `bodyCache` (§3 no-plaintext-at-rest; column dies in T9).
   Dispatch only said "populates key_id … do not invent" — nothing asks
   for body persistence.
5. **Row-contract extensions where the brief is silent** (spec-driven):
   `failed` skipped at load (test 3 needs it); empty/`__pending__`
   ciphertext skipped (media/optimistic rows would otherwise be
   terminal-failed by a decode miss); keyId-mismatch decrypt-miss ⇒
   `key_missing` not `failed` (spec §8 rotation rule — `failed` means
   "correct key, corrupt ciphertext"); keyless ⇒ `key_missing` write
   (spec §5.1 state semantics); no-op verdict writes skipped (a
   `ready`+same-fingerprint row needs no UPDATE — re-reads must not churn
   the drift stream).
6. **Lane observability** — brief test 5 must "prove both batch lanes":
   added `@visibleForTesting inlineCalls/isolateCalls` counters on
   DecryptPass (lane is otherwise unobservable from outside). Threshold
   `totalItems > 50` on the attempt set (rows actually being decrypted),
   not the requested id count.
7. **Async-gap seam named `beforeApply`** (`Future<void> Function()?`,
   `@visibleForTesting`) — the brief's "inject async gap with a
   completer"; runs after crypto returns, before the epoch-checked apply
   (IngestBoundary `onBeforeWrite` precedent, async variant).
8. **Test 4's "re-read"** = drop the subscription (autoDispose disposes),
   `bodyCache.clear()`, re-listen. Production analogue: bubble unmount /
   background teardown, then a fresh watch — matches spec §8 "cleared
   cache … re-decrypt on next provider read". `messageBodyProvider` is
   autoDispose (NOT `messagesProvider`'s keep-forever style): an
   unmounted bubble must drop its resolved plaintext instead of holding
   it in Riverpod state.
9. **Explicit `Provider<DecryptPass>` type annotation** on
   `decryptPassProvider` — required to break Dart's top-level inference
   cycle (decryptPass → messageBody → coalescer → decryptPass); commented
   in situ.

## Self-review

- Epoch guard present before EVERY db write and every cache put; test 2
  pins the drop + a stable-epoch control (non-vacuous both ways).
- Keys cross into `Isolate.run` as plain `List<int>` / `Map` data only
  (spec §8 isolate model); worker is a top-level function; worker never
  touches Drift/cache; main applies.
- Char tests byte-stable; no schema/build_runner; no changes to
  `encryption_service.dart`, DAOs, or T7 write sites; guard-5 (moved code)
  N/A — everything added is new.
- `flutter analyze`: 0 errors, 88 == baseline (new files contribute zero).
- No push. No superuser/PocketBase elevated auth. No FCM/`decrypted_body`
  drop/search work (all out of scope).

## Concerns / carry-forward

1. **T9 critical: optimistic own-sent rows.** `encryptedBody == '__pending__'`
   rows are skipped (correctly — undecryptable), and `decrypted_body` is
   never written by DecryptPass, so `messageBodyProvider` returns **null**
   for a pending own message. T9's "own sent messages are never
   placeholders" rule needs the enqueue path to `bodyCache.put` the
   plaintext at send time (spec §5.1 says exactly this: "the main isolate
   immediately decrypts it into the body cache") — NOT built here (send
   path is out of Task 8's file list; T2 ruling keeps plaintext
   `decryptedBody` until T9).
2. **Repair double-work (interim):** DecryptPass leaves `decrypted_body`
   NULL, so `_repairUndecrypted`'s `getUndecryptableRows` (body-null
   filter) keeps returning DecryptPass-processed `ready` rows and re-decrypts
   them into the column — converges, harmless, gone when T9 drops the
   column + migrates the filter (already ledgered by T7).
3. **Spec §8 batch triggers not wired** (after boundary commit /
   `groupKeyReadyProvider` key-arrival): plan Task 8's Produces lists only
   `runFor`/provider/cache; key-arrival healing rides the existing
   `_repairUndecrypted` + poll-fallback kicks; lazy provider covers reads.
   Flag for T11/T12 audit or a follow-up.
4. **`onApplied` invalidation path is not exercised by the 5 named tests**
   (they override `decryptPassProvider` with counting instances whose
   `onApplied` stays null; exact test count is pinned at 119). Wiring is
   compile-verified + defensively `alive`-guarded; worth one line in a
   T9/T11 test if review wants it behavior-pinned.
5. **DM key resolution is offline-only** in `_resolveKey` (db-cached peer
   pubkey — no server refetch), unlike repo `_getConvKey`'s rotation
   refetch. Rotation detection on DMs degrades to keyId-mismatch ⇒
   `key_missing` until a fetch-path refresh lands a new pubkey.
6. **FCM bg `decrypt_state='ready'` + null body default** — left DEFERRED
   per dispatch (recommended `Value('pending')` one-liner stays on the
   T11–12 ledger).
