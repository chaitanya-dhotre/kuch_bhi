# Offline-first — handoff notes (AS-BUILT)

## Task 1

Phase 0 characterization harness + read/send/fetch char tests + custom-id
verification. Files: `test/offline/{char_harness,read_paths_char_test,send_fetch_char_test}.dart`,
`lib/core/network/pocketbase_client.dart` (test seam only),
`docs/offline-phase0-verification.md`.

### Harness API (consumed by tasks 2–12)

```dart
// test/offline/char_harness.dart
CharHarness charHarness({http.Client Function()? clientFactory});
// CharHarness fields: .db (AppDatabase), .pbClient (PocketBaseClient),
//                     .storage (FakeSecureStorage), .encryption (EncryptionService)
// CharHarness.close() → closes the Drift DB (use addTearDown(h.close))

Future<void> seedConversationAndKey(
  CharHarness h, {
  bool withKey = true,
  List<int> key = fixtureGroupKey,   // const 32-byte key, bytes 1..32
});
// Seeds: conversation g1 (type group, createdById u_test),
//        member m1 (u_test, role member), optional group_key_g1 = base64(key).
// Timestamps: fixed DateTime.utc(2026,1,1) — MUST stay in the past of the
// canned record stamp (group cutoff isGroupRowVisible hides earlier rows).

MessageRepositoryImpl buildRepo(CharHarness h);
// Real MessageRepositoryImpl(pbClient, db, storage, encryption,
// MediaUploadService(pbClient, encryption)). Constructor schedules a 500ms
// SSE reconnect + connectivity listener — harness preps handle both.

const List<int> fixtureGroupKey; // 32 bytes [1..32] — NOT [1,2,3,4] (see below)
```

`charHarness()` side effects (all needed — do not strip):
- saves a structurally valid fake JWT in `pb.authStore` —
  `sessionStillValid(..., authValid: _pb.authStore.isValid)` gates the cold
  fetch's cache-write; without it the fetch aborts pre-cache.
- `_prepareTestRuntime()`: mocks connectivity_plus EventChannel
  `dev.fluttercommunity.plus/connectivity_status` (repo ctor listens to it)
  and sets `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true`.

### FakeSecureStorage overrides that actually worked

Overridden (all non-final in `SecureStorageService`): `read`, `write`,
`delete` (tombstone `_overrides[key] = null`), `getCurrentUserId`,
`getAuthToken`, `getPbAuthStore`, `getPrivateKey`, `getLocalPublicKey`.
`put(key, value)` / `removeKey(key)` helpers seed/tombstone the map.

**NOT overridden — later DM/session-path tests MUST extend the fake or
they hit the real `FlutterSecureStorage` platform channel →
MissingPluginException:** `saveAuthToken`, `deleteAuthToken`,
`saveCurrentUserId`, `savePbAuthStore`, `deletePbAuthStore`,
`savePrivateKey`, `saveLocalPublicKey`, `getLegacyPrivateKey`,
`getLegacyLocalPublicKey`, `saveContactEncryptionKey`,
`getContactEncryptionKey`, `readAll`, `clearAllContactKeys`,
`clearAllConversationKeys`, `clearAll`, `clearSession`, `deleteKeyPair`.
(The brief's fake omitted `write`/`delete` too — added after the first
RED: the repo calls both on the group-key path.)

### Field-name / value corrections vs brief (tests pinned to REALITY)

1. **Key fixture `[1,2,3,4]` → 32-byte `fixtureGroupKey`**: `_isoEncrypt`
   uses `AesGcm.with256bits()` and `_isoDecryptBatch` returns all-null for
   `keyBytes.length != 32` (encryption_service.dart:79). 4-byte key can
   neither encrypt nor decrypt.
2. **Fake JWT in authStore** (see above).
3. **Seed timestamps → fixed past date** (see above).
4. **read_paths search test**: `q='a'` hits BOTH 'alpha' and 'beta'
   (expected 1 → actual 2). Null-body row still skipped, no crash.
5. **fetchListClient hangs on `/api/realtime`** instead of returning 404:
   pocketbase SseClient retries 404s forever on 200–2000ms timers (would
   fire after the test ends). Other paths keep the brief's 404 body.
6. `unused_local_variable` on `final send = …` silenced with
   `// ignore:` (intentionally never awaited — pre-ack pin).

### Canned payload field names — verified against `_companionFromRecord`

Brief's payload was correct as-is: `id, collectionId, collectionName,
created, updated, fields, conversation_id, sender_id, type,
encrypted_body, iv, reply_to_id, reply_preview,
is_deleted_for_everyone, is_deleted_for_me, is_pinned, is_starred,
status, media_id`. No corrections needed. Envelope: page/perPage/
totalItems/totalPages/items matches `ResultList.fromJson`.

### Custom-id verification (Plan A gate)

**Verdict: PLAN_A_PASS (functional), with (b) evidence-substitution caveat.**
Doc: `docs/offline-phase0-verification.md`.

- (a) PASS — pocketbase 0.21.0 (pubspec.lock:1410): `create` forwards body
  opaquely (`base_crud_service.dart:160-176` → `client.dart:313`
  `request.body = jsonEncode(body)`); no id stripping anywhere in SDK.
- (b) `GET /api/collections/messages` with normal user token → **403**
  ("The authorized record is not allowed…"). Collections API is
  superuser-gated; superuser NOT attempted (absolute constraint). Intent
  closed for the tested format ONLY by (c): acceptance of 15-char
  `[a-z0-9]` ids proven (create 200 / dup 400 / fetch round-trip); other
  id formats were not tried and are not claimed.
- (c) PASS 3/3 with normal user auth only:
  1. create `id=chq0ct7x0char01` (15-char [a-z0-9]) → **HTTP 200**, id echoed;
  2. same id again → **HTTP 400**
     `{"data":{"id":{"code":"validation_not_unique","message":"Value must be unique."}},"message":"Failed to create record.","status":400}`
     ← this is the duplicate-shape offline id-collision code must match;
  3. GET by id → **HTTP 200**, `sender_id=teb3elavw531hwx`,
     `conversation_id=s0wewbc1u0oscea` round-trip.
- Cleanup: DELETE → 403 (deleteRule); PATCH
  `is_deleted_for_everyone=true` → 200 (tombstone hidden from all read
  paths). Throwaway row remains soft-deleted as evidence.

**STOP gate:** controller must accept (b)'s behavioral substitution before
Task 2 (brief's literal rule: schema paste with normal auth — impossible,
403).

### Fix round 1 deltas (read_paths re-pointed at production)

- `test/offline/read_paths_char_test.dart` now exercises ONLY production:
  (1) real `MessageBubble` (null body → renders `🔒 Encrypted`,
  message_bubble.dart `_TextBubble`); (2) real `HomeScreen` →
  `_ConversationTile` → `ChatTile` with a null-body last message (real
  `_bumpConversationForIncoming` writes preview `'New message'`,
  message_repository_impl.dart:2968); (3) real
  `repo.searchMessages(conversationId, query)` over seeded DB rows.
  Smoke-break (wrong placeholder assert) verified RED → reverted.
- `fetchListClient({EncryptResult? enc, required String conversationId})`
  — `enc` now OPTIONAL: omitted/`null` → empty `encrypted_body`/`iv`
  (decrypt yields null = null-body row). Existing callers unchanged.
- **Widget-test rule:** real async (`compute()` decrypt, DB I/O) inside
  `testWidgets` must be wrapped in `tester.runAsync(...)`; and any test
  that listens to drift streams must unmount (`pumpWidget(const
  SizedBox())`) + `pump(1ms)` before ending, else the testWidgets
  pending-timer invariant trips on drift's `markAsClosed` `Timer.run`
  (stream_queries.dart:154).

### Test results (Task 1 exit state)

- `flutter test test/offline/` → 6/6 (3 read-path + 3 send/fetch)
- `flutter test` (full) → **All tests passed (73)**
- `flutter analyze` → **0 errors** (88 legacy warnings/info, none in
  test/offline/ or pocketbase_client.dart)

## Task 2

Outbox core — table, FSM data layer, id generator, atomic enqueue,
interim ack. Commit subject `[Offline P1] Outbox table + FSM data
layer + atomic enqueue` (SHA omitted — a commit cannot contain its
own hash). Tests: `test/offline/outbox_core_test.dart`
6/6; full suite **79 pass**; analyze **0 errors** (88 legacy, unchanged).

### AS-BUILT API (consumed by tasks 3–12)

```dart
// lib/core/utils/op_id.dart
String generateOpId();          // 15-char [a-z0-9], Random.secure —
                                // becomes the PocketBase record id

// lib/data/local/database/tables/outbox_table.dart
enum OutboxState { queued, sending, sent, failedTerminal }
//  Stored via drift textEnum → EnumNameConverter → enum .name, so the
//  SQL value is 'failedTerminal' (spec prose writes failed_terminal —
//  same state, snake vs camel spelling). Default SQL 'queued'.
class OutboxTable {
  opId text PK · kind text · ref text · conversationId text · seq int ·
  state text default 'queued' (OutboxState) · attempts int default 0 ·
  nextAttemptAt dateTime? · createdAt dateTime · lastError text? ·
  errorClass text? · dependsOn text?
}

// lib/data/local/database/daos/outbox_dao.dart  (db.outboxDao)
Future<void>              enqueue(OutboxTableCompanion row); // joins caller txn
Future<OutboxTableData?>  byId(String opId);
Future<List<OutboxTableData>> due(DateTime now);   // queued & (nextAttemptAt
    // null | <= now), ORDER BY conversationId, seq
Future<void>              setState(String opId, OutboxState state,
                            {int? attempts, DateTime? nextAttemptAt,
                             String? lastError, String? errorClass});
                          // only provided optionals are written
Future<int>               nextSeq(String conversationId); // max+1, call INSIDE txn
Future<List<OutboxTableData>> all();               // ORDER BY conversationId, seq
Future<List<OutboxTableData>> forConversation(String id);

// lib/data/local/database/daos/messages_dao.dart
Future<int> countForConversation(String conversationId); // unfiltered count

// lib/infrastructure/repositories/message_repository_impl.dart
bool isDuplicateIdError(ClientException error);   // TOP-LEVEL function —
    // parser ENTRY POINT: true only for HTTP 400 + data.id.code ==
    // validation_not_unique (Task 1's pinned body). Any other field
    // (e.g. data.iv) → false → never counted delivered.
Future<void> handleDrainAck(String opId,
    {required String serverId, required String senderId,
     required String conversationId});
    // INTERIM: body = txn { message(ref→localId, WHERE sender+conv match)
    // .serverId/status=sent; outbox.setState(sent) } — absorbed by
    // IngestBoundary in Task 6 (boundary.commit(batch, source)).
Future<bool> resolveDuplicateSend({required String opId,
    required String senderId, required String conversationId});
    // Call ONLY after isDuplicateIdError. GET record by opId:
    //   ours → handleDrainAck (no re-create) → true
    //   404/403 or sender/conversation mismatch → setState(failedTerminal,
    //   errorClass: 'id_collision') → false (never retried, never success)
    //   other ClientException → rethrow (transient, not a verdict).
    // INTERIM: absorbed by IngestBoundary in Task 6.
```

### sendMessage new flow

1. pre-work unchanged (`_myId`, `_assertCanSend`, localId, expiry).
2. **ONE `db.transaction`**: messagesDao.upsertMessage (same companion as
   before: encryptedBody `'__pending__'`, status pending,
   decryptedBody=plaintext — kept until Task 9) **+**
   `outboxDao.enqueue(kind: 'text_send', ref: localId, seq: nextSeq,
   opId: generateOpId(), state default queued)`.
3. AFTER the txn: fire-and-forget `_drainOutbox(...)` — the interim
   drain kick. Task 3 replaces this with OutboxWorker.drain().

`_drainOutbox` = `_uploadMessage` **renamed**, body byte-identical
(guard 5). `retryMessage` now calls `_drainOutbox` too (call-site rename
only). Encryption (`_getConvKey` + `encryptMessage`) runs INSIDE the
drain, i.e. after the txn — see correction 4.

### Corrections vs brief (reality rule)

1. **Row class is `OutboxTableData`, not `OutboxRow`** — drift names
   data classes `<TableClassName>Data` (same as MessagesTableData).
   All dao signatures use OutboxTableData.
2. **Enum column query API**: `t.state.equalsValue(OutboxState.queued)`
   (NOT `.equals(OutboxState.queued)`) — GeneratedColumnWithTypeConverter
   extends GeneratedColumn<S=String>, so `.equals` takes the SQL type;
   `equalsValue` maps the Dart value through EnumNameConverter.
3. **`bumpSeq` (brief bullet) shipped as `nextSeq(String)`** only —
   the parenthetical signature is what the brief's own test calls.
4. **"encrypt (existing code)" interpreted as: encryption stays inside
   the moved network send**, not hoisted into the enqueue txn. Reasons:
   (a) hoisting would edit the moved code or double-encrypt (the retry
   path still encrypts internally); (b) encrypt-before-insert would
   LOSE the message row on MissingKeyException (keyless offline send —
   old code inserts first, then keeps the row pending); (c) the brief's
   outbox schema has no payload column to hold ciphertext. Spec §5.2's
   "encrypt inside the txn" lands when the worker/payload path exists
   (Task 3/9) — flagged, not silently ignored.
5. **Interim drain kick = direct `_drainOutbox(...)` call**, not
   `retryPendingMessages()` — the pre-outbox sendMessage called the send
   directly; a retryPendingMessages kick would change timing and could
   fan out other pending rows. `_uploadMessage` renamed per the brief's
   "renamed `_drainOutbox`".
6. **FakeSecureStorage: `extends` → `implements`** is REQUIRED for the
   brief's noSuchMethod line to work — verified empirically: noSuchMethod
   forwarders only exist for UNimplemented members, so with `extends` the
   17 concrete base impls kept running (real FlutterSecureStorage).
   With `implements`, all 17 route to noSuchMethod → UnimplementedError
   with the brief's message. Full 8-member overrides unchanged.
7. **Brief test snippets didn't compile as written** —
   `MessagesTableCompanion.insert` requires `iv` AND `updatedAt`
   (non-null, no default). Added `iv: ''` / `updatedAt: DateTime.now()`
   to the atomic test and the `_seedOp` helper.
8. **Interim gap (intentional)**: the old network send does NOT
   transition outbox rows — after a successful interim send the outbox
   row stays `queued` (drain has no opId). Task 3's worker owns FSM
   transitions; Task 6 rewires acks through IngestBoundary. Tests drive
   handleDrainAck/resolveDuplicateSend directly (the interim entries).
9. **Triple-delivery test drives the REAL fetch echo**: warm
   `repo.watchMessages` → production `_fetchAndCacheMessages` →
   `_cacheMessagesBatch` (delete+reinsert keyed by serverId) — completion
   signaled by the first post-batch HTTP request. `_seedOp` sets
   decryptedBody because `isGroupRowVisible` hides null-body group rows
   AND undecryptable rows trigger the key-invalidating self-heal
   (deletes group_key_g1 mid-test).
10. **`handleDrainAck` filters the message update** by
    `localId=op.ref & senderId & conversationId` (uses the required
    params as ownership guards); op==null → only setState (no-op).
11. Migration `if (from < 7) m.createTable(outboxTable)`; `AppDatabase.test()`
    exercises onCreate only (same as v1–v6 — no upgrade-path test exists).
