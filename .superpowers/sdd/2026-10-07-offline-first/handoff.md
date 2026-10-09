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

## Task 3

OutboxWorker — drain FSM, backoff, 4xx classes, FIFO, stale recovery,
pause, retryOp/discardOp. Files: `lib/infrastructure/offline/outbox_worker.dart`
(NEW), `message_repository_impl.dart` (sender + hooks), `message_repository.dart`
(interface), `outbox_dao.dart` + `messages_dao.dart` (additions),
`test/offline/outbox_worker_test.dart` 12/12; full suite **91 pass**;
analyze **0 errors** (88 legacy, unchanged).

### AS-BUILT API (consumed by tasks 4+)

```dart
// lib/infrastructure/offline/outbox_worker.dart
const int deferStatus = -1;               // nextAttempt "local defer" status
const String kOutboxPauseKey = 'outbox_pause';  // settingsDao key
const String kOutboxPauseAuth = 'auth';          // value written on 401

enum OpSendOutcome { sent, deferred }
typedef OpSender = Future<OpSendOutcome> Function(OutboxTableData op);

class TerminalOpError implements Exception { final int statusCode; }
class PauseAllOpError implements Exception {}
class OpSendException implements Exception {   // sender-thrown HTTP error
  final int statusCode; final String? retryAfterHeader;   // carries Retry-After
}

String terminalErrorClass(int status); // 400 bad_request · 403 forbidden ·
// 404 dead_link · 413 payload_too_large · else http_$status

DateTime? nextAttempt({
  required int httpStatus, required String? retryAfterHeader,
  required int attempts, required DateTime now,
  required DateTime Function() clock,   // brief-verbatim; scheduling uses `now`
  required Random random,
});
// {400,403,404,413} → throw TerminalOpError
// 401 → throw PauseAllOpError
// deferStatus(-1) → null  (stay queued, NO schedule change)
// 429 + parseable Retry-After ≥0 → now+secs (else falls through to backoff)
// else → now + min(300s, 5s·2^attempts) · (1 + random.nextDouble()·0.25)
//        (cap applies BEFORE jitter → max delay 375s; attempts≥6 ⇒ base 300s)
// Retryable failures record errorClass 'transient' (label choice — brief
// pinned only the status classes).

class OutboxWorker {
  OutboxWorker({
    required OutboxDao outbox, required MessagesDao messages,
    required SettingsDao settings, required OpSender send,
    DateTime Function()? now, Random? random,
  }); // ctor: connectivity listener (moved) + stale-sending recovery kick
  Future<void> get ready;          // stale-recovery future (tests await it)
  Future<void> drain();            // serialized; concurrent callers coalesce
                                   // into ONE extra pass (await ⇒ post-write)
  void kick();                     // fire-and-forget drain, errors logged
  void onConnectivityRestored();   // flag → clearRetryQueued + drain
  void onAuthPaused(bool paused);  // set/clear outbox_pause, NO drain
  void onAuthResumed();            // flag → clear pause + drain
  Future<void> retryOp(String opId);
  Future<void> discardOp(String opId); // dependsOn cascade, then drain
  void dispose();                  // cancels connectivity sub (tests)
}
```

### Drain pass (one pass, FIFO)

1. `await ready` → consume connectivity-reset flag (`clearRetryQueued`) and
   resume flag (clear pause) → bail if paused.
2. **Carry-in C1**: over `all()` — queued op whose message row has
   `serverId≠null && status ∈ {sent,delivered,read}` → `setState(sent,
   attempts:0)` (interim-linger completion; NEVER re-sends).
3. `due(now)` (queued & schedule elapsed, ordered `(conversationId, seq)`);
   group by conversation; per conversation walk `forConversation` in seq:
   `sent`→skip; **non-queued head (failedTerminal|sending) → break**;
   **not-due head → break** (backoff blocks FIFO); **dependsOn not `sent`
   → break** (spec §5.2 two-step); else process.
4. `_processOne`: `sending` → sender → outcome:
   - `sent` → ensure row `sent` (attempts 0) — real sender already acked;
   - `deferred` → back to `queued` ONLY if row still `sending`
     (sender-written verdicts — terminal, encrypt_failed — untouched);
   - throw → `_applyFailure` via `nextAttempt`; terminal ⇒
     `failedTerminal` + errorClass + message `failed` (only if still
     `pending`); 401 ⇒ row back to `queued` + `outbox_pause='auth'` +
     STOP the pass (attempts/nextAttemptAt/lastError untouched = queue
     untouched); else ⇒ `queued`, attempts+1, nextAttemptAt, lastError,
     errorClass `transient`.
   After each op: op removed → continue; op ≠ `sent` → break (blocks rest
   of conversation — covers terminal, backoff, defer).

### Kind sender (repo side)

`MessageRepositoryImpl.sendOutboxOp(op)` PUBLIC — worker's `send:` callback
(tests inject it too). `text_send` → `_sendTextOp` (the old `_drainOutbox`
body, adapted): inputs from op+message row; **create carries
`'id': op.opId`**; dup(id) → `resolveDuplicateSend` ownership (true ⇒
`sent`, false ⇒ collision verdict already written ⇒ `deferred`); other
ClientExceptions PROPAGATE to the worker; MissingKey ⇒ deferred (stays
pending); other encrypt errors ⇒ message `failed` + op `failedTerminal`
errorClass `encrypt_failed` + deferred; success ⇒ dual-truth txn {full
message stamp + outbox sent} then updateLastMessage + receipts.
`media_upload`/other kinds ⇒ `throw StateError` (see correction 6).
`_drainOutbox` DELETED — the only send path is the worker now.

### retryOp / discardOp (Task 4 banner)

- Interface: `Future<void> retryOp(String opId)`,
  `Future<void> discardOp(String opId)` added to `MessageRepository`
  (impl delegates to worker).
- `retryOp`: `clearRetry` (attempts/nextAttemptAt/lastError/errorClass →
  0/NULL — carry-in C2) → `queued` → message `failed`→`pending` → drain.
- `discardOp`: one `all()` read, transitive `dependsOn` collect → delete
  MESSAGE rows first, then op rows (kill-window leaves harmless orphan
  ops, never orphan messages that retryPendingMessages would re-send) →
  drain (next FIFO op flows immediately).

### Connectivity hook points (moved)

`Connectivity().onConnectivityChanged` listener body moved VERBATIM from
`_initConnectivityRetry` (repo ctor no longer calls it; method deleted;
connectivity_plus import dropped from repo). Only the action inside the
`if` changed, per brief: `onConnectivityRestored()` = `clearRetryQueued`
(attempts→0, schedule→NULL for every queued op) + immediate drain. A row
waiting a 4-min backoff sends on the event (test 4).

### DAO additions

```dart
// outbox_dao.dart
Future<void> clearRetry(String opId);      // attempts=0, nextAttemptAt/
Future<void> clearRetryQueued();           // lastError/errorClass → NULL/0
Future<void> deleteOp(String opId);        //   — single / all queued
// messages_dao.dart
Future<void> deleteByLocalId(String localId); // discard cascade hard-delete
```

### Corrections vs brief (reality rule)

1. **`nextAttempt` `clock` param is unused** — brief-verbatim signature
   kept; scheduling uses `now` (fake-clock seam).
2. **Retry-After cannot reach the production sender**: pocketbase 0.21
   `client.dart` drops response headers when building `ClientException`
   (no headers field). The worker honors it via `OpSendException` (tested
   at worker level, brief case 3); the production path supplies `null` →
   backoff. A header-carrying transport seam is a follow-up if spec §6
   full compliance is required.
3. **errorClass labels** (brief pinned only status classes):
   `dead_link`/`forbidden` match outbox_table.dart's column comment;
   400→`bad_request`, 413→`payload_too_large`, retryable→`transient`,
   local crypto→`encrypt_failed`.
4. **attempts semantics**: worker passes `op.attempts+1` into
   `nextAttempt` (spec literal `attempts++, next = now + base·2^attempts`)
   → first failure base = 5s·2^1 = 10s. Cap BEFORE jitter (brief formula
   verbatim) ⇒ max delay 375s, floor 300s for attempts≥6.
5. **Connectivity action delta**: listener now drains the outbox instead
   of calling `retryPendingMessages()`. Outbox-enqueued sends covered;
   pre-outbox legacy pending rows no longer auto-retry on the connectivity
   event (still covered by `resyncOnResume` → retryPendingMessages, and
   retryMessage now ENQUEUES an op for them).
6. **`media_upload` production sender not moved** — progress.md ruling:
   outgoing enqueue wiring is out of plan scope; the existing media flow
   (`_uploadMediaMessage`) is create+upload interleaved with serverId
   dependency and has no standalone upload to move verbatim. Kinds other
   than `text_send` throw StateError → (if ever prematurely enqueued)
   transient backoff, never data loss. Drain-side dependency gating for
   two-step media is fully built + tested (brief case 8, seeded rows).
7. **`retryMessage` rerouted through the outbox** (was direct
   `_drainOutbox` call): finds the op by `ref` (via `forConversation`) and
   resets it, or ENQUEUES one for legacy opless rows, then drains — a
   direct send could race the worker's drain and double-create (different
   create ids). Side effect: retry now keeps the reply link (old code
   passed `replyToLocalId: null` — dropped replies on retry).
8. **Stale recovery is construction-time + `ready` future** (not part of
   drain): tests await `worker.ready` before asserting `sending→queued`.
9. **`sendMessage` reply params** (`replyToLocalId`/`replyPreview`) still
   enqueue into the message row; `_sendTextOp` reads them from there.
10. **Repo worker instance is exposed** as `MessageRepositoryImpl
    .outboxWorker` (tests construct their OWN worker with fake now/Random
    + `send: repo.sendOutboxOp`; the repo's worker serves production kicks
    — two listeners in tests are inert: the mocked EventChannel never
    emits).
11. **Discard does not touch conversation last-message preview** —
    if the discarded op's message was the last preview, the preview can
    go stale until the next sync (known gap, banner UX may want it).

### Fix round 1/5 — production unpause path (CRITICAL) + minors 2/7

AS-BUILT wiring location:

- **Seam:** `MessageRepositoryImpl.handleAuthStoreChange(String token)`
  (`message_repository_impl.dart`, right below the `_sessionEpoch` field;
  `@visibleForTesting`) → non-empty token ⇒ `outboxWorker.onAuthResumed()`.
- **Call site:** FIRST statement inside the `pb.authStore.onChange` listener
  (ctor, before the `shouldReconnectRealtime` same-session early-return) —
  every token save (login, refresh, rotation) releases the `401` pause;
  empty token (logout/clear) does NOT resume here (signOut wipe owns it).
- **Belt-and-braces:** `OutboxWorker._clearAuthPauseIfSet()` — a successful
  authenticated send clears a stale `outbox_pause='auth'` (only that value)
  written while the send was in flight (`_processOne` success branch).
- **Minor 2:** `_resetQueued`/`_resumeRequested` flags now clear only AFTER
  their awaited write succeeds (`_pass`) — a throw keeps the flag.
- **Minor 7:** `onAuthPaused` is now `Future<void>` (awaits the settings
  write — brief said `void`; review overrides). `onAuthResumed` stays `void`.
- **Tests:** `401 pause round-trips via authStore token save (production
  unpause path)` (full chain: real 401 → pause → `authStore.save` → listener
  → seam → resume → re-send 200 → sent) + `handleAuthStoreChange: empty
  token does NOT resume; non-empty does`. Suite **93 pass**, analyze **0
  errors** (88 legacy).

## Task 4

Terminal-failure UI — stuck-message banner + retry/discard. Commit
`[Offline P1] Terminal-failure banner — retry/discard UI` = `4878a59`
(own hash cannot appear in its body). Files: `lib/features/chat/providers/
outbox_status_provider.dart` (NEW), `lib/features/chat/widgets/
message_bubble.dart` (lookup + slot + `TerminalFailureBanner`),
`test/offline/terminal_banner_test.dart` (NEW, 8/8), gate 11 in
`test/grep_gates_test.dart`, hermetic override in
`test/message_bubble_sender_test.dart`. Full suite **102 pass**;
analyze **0 errors** (88 legacy, unchanged). Step 5 device proof =
**DEFERRED-DEVICE** (controller collects at batch checkpoint).

### AS-BUILT API (consumed by tasks 5+)

```dart
// lib/features/chat/providers/outbox_status_provider.dart
final outboxStatusProvider =
    StreamProvider.family<List<OutboxTableData>, String>(
        (ref, conversationId) {
  final db = ref.read(appDatabaseProvider);
  return (db.select(db.outboxTable)
        ..where((t) => t.conversationId.equals(conversationId)))
      .watch();
});
// Non-autoDispose family (mirrors messagesProvider): one shared drift
// watch per conversation, ever. AsyncError (DB open fail) → bubbles read
// `.value ?? const []` → no banner, never a crash.
// Row class is OutboxTableData (from app_database.dart), NOT OutboxRow.
```

### Bubble wiring points (message_bubble.dart)

- Lookup: in `MessageBubble.build` after the system-bubble early-return —
  `ref.watch(outboxStatusProvider(message.conversationId)).value ?? []`,
  find `row.ref == message.localId && row.state == OutboxState.failedTerminal`.
  NOT gated on `message.status` — `_markIdCollision` leaves the message
  `pending` (only the op goes failedTerminal), so a status gate would hide
  the `id_collision` class from the spec's "must be VISIBLE" rule.
- Slot: last child of the bubble Column (after ReactionBar), widget
  **`TerminalFailureBanner`** (public, same file), key
  **`ValueKey('terminal-banner-${message.localId}')`** at the call site.
- Banner: `Container` margin matches bubble insets (L64/R12 mine) ·
  `color: context.t.error.withValues(alpha: 0.08)` ·
  `borderRadius: WarmPopTokens.radiusSm` · title `'Failed to send'`
  (w600/13, t.error) · error-class line = raw `errorClass` string (e.g.
  `dead_link`) · TextButtons `Retry`/`Discard` (foregroundColor t.error,
  min 36px tall). System fonts, no new colors — grep gate 11 bans
  `Color(0x` / `Colors.*` in provider + bubble files.
- Actions (REAL repo, tested against a mocktail-free fake):
  `onRetry → ref.read(messageRepositoryProvider).retryOp(terminalOp.opId)`;
  `onDiscard → …discardOp(terminalOp.opId)` (Task 3 cascade). No confirm
  dialog (brief taps Discard directly).

### Corrections vs brief (reality rule)

1. Brief's "seeded in DB, provider overridden by Stream.value" split into
   TWO tests: widget tests override the family with `Stream.value([...])`
   (brief snippet), plus one provider-body test that seeds a real
   `AppDatabase.test()` and asserts `outboxStatusProvider('c1').future`
   filters by conversation (both seams covered).
2. `message_bubble_sender_test.dart` edited (+7 lines): bubble now always
   watches the outbox stream → bare ProviderScope constructed a 2nd
   production AppDatabase across its two testWidgets → drift's
   "multiple databases" WARNING spam. Fix = feed
   `outboxStatusProvider.overrideWith(… Stream.value(const []))` (hermetic,
   provider body never runs). Suite output pristine again; precedent:
   char_harness sets `dontWarnAboutMultipleDatabases`.
3. Banner widget is PUBLIC (`TerminalFailureBanner`) so tests can locate
   it and future screens can reuse it; the localId key stays at the
   MessageBubble call site.
4. Family is non-autoDispose (brief silent): matches `messagesProvider`
   lifecycle; one drift outbox watch per conversation ever-opened.

## Task 5

MediaBlobStore — requestBlob entry, blob FSM, startup janitor, deferred
eviction. TDD: 5 named tests RED (`UnimplementedError` at the 4 entry
points) → GREEN. Full suite **107 pass**; analyze **0 errors** (88
legacy, unchanged — the `baseUrl` deprecation info MOVED with the moved
code, net neutral). Files: `lib/data/local/database/tables/
media_blob_table.dart` (NEW), `daos/media_blob_dao.dart` (+.g.dart, NEW),
`lib/infrastructure/media/media_blob_store.dart` (NEW),
`app_database.dart` (schemaVersion 8), `app_constants.dart` (constants),
`chat_provider.dart` (provider re-point),
`message_repository_impl.dart` (store construction + re-point),
`media_upload_service.dart` (getDecryptedMedia MOVED out),
`test/offline/media_blob_store_test.dart` (NEW, 5/5).
NOTE: this commit also carries handoff's uncommitted **Task 4** section
(+75 lines) — Task 4's commit didn't include it.

### AS-BUILT API (consumed by tasks 6+)

```dart
// lib/data/local/database/tables/media_blob_table.dart
enum BlobState { queued, downloading, ready, failed, evicted } // textEnum → .name
class MediaBlobTable {
  blobId PK · messageId · remoteRef? · expectedSize? · expectedHash? ·
  localPath? · bytes(default 0) · lastAccess · state(default queued) ·
  errorClass? · uploadPending(default false)
  // NO protected column (spec §5.3) — protection derived at eviction time.
}

// lib/data/local/database/daos/media_blob_dao.dart  (db.mediaBlobDao)
Future<void> insert(Insertable<MediaBlobTableData> row); // insertOrIgnore —
    // concurrent first-request race safe
Future<MediaBlobTableData?> byId(String blobId);
Future<void> setState(String blobId, BlobState state,
    {String? errorClass, String? remoteRef, String? localPath,
     int? bytes, DateTime? lastAccess});   // only-provided writes (OutboxDao pattern)
Future<void> resetDownloadingToQueued();   // janitor
Future<List<MediaBlobTableData>> byState(BlobState state);
Future<List<MediaBlobTableData>> readyLru();      // ready ORDER BY last_access ASC
Future<int> readyTotalBytes();                    // SUM(bytes) WHERE ready

// lib/infrastructure/media/media_blob_store.dart
String mediaBlobId(String serverId, {required bool thumb});
    // '<serverId>_f' | '<serverId>_t' — same identity as the legacy
    // media_clear prefix '<serverId>_<f|t>_' + fileName
class MediaBlobStore {
  MediaBlobStore({
    required MediaBlobDao dao, required MessagesDao messages,
    required PocketBaseClient pbClient, required EncryptionService encryption,
    required Future<List<int>> Function(String convId) resolveKey,
    Future<Directory> Function()? cacheDir,  // default getTemporaryDirectory
    http.Client? httpClient,                 // default http.Client()
  }); // ctor KICKS janitor+evict (spec §9 app start) + connectivity listener
  late final Future<void> ready;   // maintenance completion (await in tests)
  Future<LocalMediaFile?> requestBlob(String blobId, String reason); // SINGLE entry
  Future<void> janitor();
  Future<void> evictIfNeeded();
  Future<void> onConnectivityRestored(); // drains queued; awaitable (test seam)
  void dispose();                        // cancel conn sub + close OWNED client
}
// Files (app-private, moved convention): <cacheDir>/media_clear/
//   ready     : '<serverId>_<f|t>_<name>'  (byte-identical legacy prefix rule)
//   in-flight : '<blobId>.part'            (janitor deletes orphans)
```

Constants (`lib/core/constants/app_constants.dart`, top-level):
`const int kMediaCacheMaxBytes = 300 * 1024 * 1024;`
`const double kMediaCacheWatermark = 0.85;`

### requestBlob switch + pipeline

row absent → insert queued (messageId = blobId minus `_f`/`_t` suffix) →
pipeline. `failed` → return null (TERMINAL — zero network, test 4 pins
fileHits unchanged). Anything else → coalesce via `_inflight[blobId]`
(concurrent callers share ONE pipeline) or start pipeline:
1. `downloading`.
2. fast path — prefix scan of mediaCache; hit → `ready` + touch
   lastAccess + zero network (moved body).
3. record lookup `message_media` by `message_id` (moved SDK call).
   **404 → queued** (upload race #18: record not landed yet — NOT
   dead_link; the provider's mediaArrived retry must still succeed).
4. download via injected `_httpClient` (moved `http.get` seam) →
   non-200 → classify: 404 `dead_link` · 401/403 `expired` · 5xx/other
   → queued.
5. write `<blobId>.part` → verify (expectedSize length, expectedHash =
   sha256-hex lowercase of DOWNLOADED bytes; null = unknown = pass) →
   mismatch `failed(verify)` + temp deleted.
6. decrypt: `iv` empty = legacy plaintext (moved); else message row →
   `resolveKey(conversationId)` (MissingKey → outer catch → queued) →
   `encryption.decryptBytes` → null `failed(decrypt)` (moved).
7. write final file (moved `writeAsBytes(clear, flush: true)`) → delete
   `.part` → `ready` (bytes/localPath/lastAccess/remoteRef) → watermark
   probe: if SUM > kMediaCacheMaxBytes·kMediaCacheWatermark →
   `unawaited(evictIfNeeded())` (NEVER awaited by the write path).
8. outer catch (moved `[Media] getDecryptedMedia error: $e` line) →
   queued — offline/network/unknown never produce a failed class.

### janitor / eviction triggers

- App start = ctor kick `janitor(); evictIfNeeded();` → exposed as
  `ready` (OutboxWorker stale-recovery precedent; no bootstrap edit —
  brief's file list has none). Janitor: `downloading → queued` + delete
  `<mediaCache>/*.part` (silent return when cacheDir unresolvable —
  keeps the buildRepo suite output pristine; dir resolution uses
  path_provider which has no test handler).
- `evictIfNeeded`: while SUM(ready bytes) > kMediaCacheMaxBytes → walk
  readyLru() (lastAccess ASC) → skip protected (`uploadPending` OR
  `message.isStarred` OR `message.isPinned`, computed per row AT eviction
  time via `messages.getMessageByServerId`) → delete file (row SKIPPED
  if delete fails — never lie with `evicted`) → state `evicted`, metadata
  (bytes/localPath/lastAccess/errorClass) kept.
- Watermark = post-write TRIGGER only; eviction TARGET = the max
  (matches brief test postcondition `total ≤ kMediaCacheMaxBytes`).

### Call-site rewires

- `mediaFileProvider` → `store.requestBlob(r.blobId, 'mediaFileProvider')`
  (both the initial fetch and the post-mediaArrived retry; wait/retry
  shape byte-identical). `MediaRef.blobId` getter added.
- `MessageRepositoryImpl.getDecryptedMedia` → `store.requestBlob(
  mediaBlobId(serverId, thumb: …), 'repo.getDecryptedMedia')`; its
  `MissingKeyException` catch kept (store swallows MissingKey into
  queued internally — belt and braces).
- Store is constructed INSIDE the repo ctor: `resolveKey: (convId) async
  => _getConvKey(convId, await _myId())`; exposed as
  `MessageRepositoryImpl.mediaBlobStore` (outboxWorker precedent —
  breaks the repo↔store DI cycle without touching `_getConvKey`).
- `MediaUploadService.getDecryptedMedia` DELETED (moved). `LocalMediaFile`
  + `getMediaExpiry`/`getVoiceExpiry` stay put.

### Corrections vs brief (reality rule)

1. **errorClass column ADDED** to media_blob_table — spec §5.3's column
   list omits it but §9 says `failed` carries `error_class` and the brief
   pins it in Produces; test 4 asserts the stored value.
2. **blobId format** (brief pins only the signature): `'<serverId>_f' |
   '<serverId>_t'`. messageId = suffix-stripped; conversationId for the
   key = `messages.getMessageByServerId` (a blob whose message row is
   missing queues — no production caller lacks the row: bubbles/starred
   render from message rows; caller-supplied conversationId became
   internal because requestBlob's signature is fixed).
3. **Moved-body seams (guard 5 ledger)**: (a) `http.get` →
   `_httpClient.get` (MockClient download seam — brief test 1 requires
   it); (b) `getTemporaryDirectory()` → `_cacheDir()` (test temp dirs;
   default = same function); (c) the moved big try/catch + its debugPrint
   line remain, but status/verify/decrypt failures branch BEFORE it —
   the swallow-all catch can no longer mint an error class; (d) NEW
   `.part` + verify stages between download and decrypt (janitor's
   contract); (e) decrypt branch gained the lazy resolveKey lookup (the
   moved code received `convKey` as a parameter). Fast-path scan,
   readFile, `.enc` strip, URL+auth headers, legacy iv-empty branch,
   `writeAsBytes(clear, flush)`, metadata construction: verbatim.
4. **Eviction semantics**: target = max (hard cap), watermark = trigger
   for scheduling the deferred pass. App-start passes run unconditionally.
5. **Own connectivity listener** (second subscription beside
   OutboxWorker's — separate domains; EventChannel mocked in harness,
   inert). `onConnectivityRestored()` returns `Future<void>` (brief
   silent) so test 1 can await the drain and observe downloading→ready.
6. **Spec §11 session-epoch abort for in-flight downloads NOT built** —
   no T5 test/brief step; flag for the logout/epoch task.
7. Test correction vs self: `lastAccess` DateTime equality must compare
   `millisecondsSinceEpoch` (drift returns local time, seed was UTC —
   Dart `==` also compares the `isUtc` flag).

### Fix round 1/5 — review I1 (epoch guards) + I2 (non-vacuous eviction test)

**I1 — spec §11 write gates (AS-BUILT wiring):**

```dart
// MediaBlobStore ctor — NEW required seam (repo ctor wires it):
required int Function() epoch,
// message_repository_impl.dart ctor, alongside resolveKey:
epoch: () => _sessionEpoch,   // the repo's live counter (bumped on logout)
```

- Gate helper `_stillValid(epochAtStart, what)` wraps the repo's
  `sessionStillValid` (core/utils/session_epoch.dart — Review C1
  precedent): `epochAtStart == _epoch() && pb.authStore.isValid`; on
  false → debugPrint + caller ABORTS (no throw). Epoch captured at each
  operation's entry: requestBlob, _runPipeline, janitor,
  onConnectivityRestored, evictIfNeeded.
- Guard sits IMMEDIATELY before EVERY dao write AND file write: row
  create; downloading/fast-path-ready/record-404/missing-file/queued/
  failed/ready transitions (helpers `_fail`/`_safeQueued` take
  epochAtStart and check internally); mediaCache dir create; `.part`
  write; cleartext final write; `_deleteQuietly(epochAtStart, …)` for
  every temp delete (pipeline + janitor); janitor's per-iteration temp
  sweep check; evict's file delete + `evicted` state (separate checks);
  connectivity drain re-checks before EACH requestBlob start.
- `row!` → null-safe bail (`row == null` after insert/re-read = wipe
  mid-request → return null).
- Test: `spec §11 epoch guard: pipeline, janitor and evict all drop
  writes after a session bump (no post-logout repopulation)` — mutable
  `epoch` holder via `_store(epoch: …)`; gated download bumped mid-flight
  (state stays downloading, NO file/.part), janitor bumped between entry
  capture and sweep (orphan survives), evict bumped during size probe
  (file + ready state survive). Mutation A (gate forced true) → test
  FAILS (proved non-vacuous), reverted.

**I2 — eviction test 3 resized (b/c now visited while over cap):**

- Seed order/bytes: E 0.5MiB uploadPending(t0, skip) → D 1KiB real
  file(t1, evict) → **B 100MiB starred(t2, SKIP while total 311.001MiB
  > cap)** → M 0.5MiB(t3, evict AFTER B skip) → **C 50MiB pinned(t4,
  SKIP while total 310.5MiB > cap)** → T 160MiB(t5, evict AFTER C skip
  → 150.5MiB ≤ cap). Final total = E+B+C = 150.5MiB.
- Positive post-skip eviction asserts (`mid_f`, `tail_f` evicted) make
  the loop's continuation past b/c load-bearing. Mutation B (join broken
  to uploadPending-only) → starred assert FAILS (`ready` vs `evicted`),
  reverted.
- Test name now says 311MB (controller-authorized resize; brief's 301MB
  figure replaced).

Suite after fix round: **108 pass** (6th epoch test added); analyze
**0 errors** (88 legacy). Ledger additions to correction 3: guard lines
inserted INSIDE the moved fast-path block (cache-dir create + fast-path
ready write) per I1's "every file/dao write" mandate.


## Task 6

IngestBoundary extraction — single entry, txn+cursor, tombstones. Commit
subject `[Offline P3] IngestBoundary — single entry, cursor+ack in one txn
(behavior-preserving)` (own hash cannot appear in its body). Files:
`lib/infrastructure/ingest/{ingest_batch,ingest_boundary}.dart` (NEW),
`message_repository_impl.dart` (SEVEN write sites rewired — reviewer
count: SSE pin/delete, drain-ack body, fetch batch, self-heal,
`_syncDeletedForMe`, `_syncStarredMessages`, `_cacheMsgInner`),
`test/offline/ingest_boundary_test.dart` (NEW, 4/4 — brief test 5 is the
char-test regression run). Full suite **112 pass**; analyze **0 errors**
(88 legacy, unchanged).

### AS-BUILT API (consumed by tasks 7+)

```dart
// lib/infrastructure/ingest/ingest_batch.dart
enum IngestSource { sse, fetch, drainAck }   // metadata only — identical
    // batches write identically regardless of source (test 1 pins this)
class MessageUpsert { const MessageUpsert(MessagesTableCompanion row); }
class CursorDelta { String conversationId; DateTime to; }  // server stamp;
    // written as UTC ISO (moved from _writeCursor)
class OutboxAck { String opId, serverId, senderId, conversationId; }
class IngestBatch {
  const IngestBatch({List<MessageUpsert> upserts = const [],
      List<String> tombstones = const [], CursorDelta? cursorAdvance,
      OutboxAck? ack});
}

// lib/infrastructure/ingest/ingest_boundary.dart
class IngestBoundary {
  IngestBoundary({required AppDatabase db, required int Function() epoch,
      required bool Function() authValid});
  @visibleForTesting void Function()? onBeforeWrite; // inside the txn:
      // after the drain-ack state flip, immediately before message-row +
      // cursor writes (brief tests 3/4 drive this hook)
  Future<void> commit(IngestBatch batch, IngestSource source);
  // epoch aborts throw _EpochAbort INSIDE the txn → full rollback →
  // caught, logged `[Ingest] …`, silent return. Other errors propagate
  // to callers' existing catch handling.
}
// Repo wiring: MessageRepositoryImpl.ingestBoundary (ctor, outboxWorker
// precedent) = IngestBoundary(db, epoch: () => _sessionEpoch,
// authValid: () => _pb.authStore.isValid).
```

### commit sequence (ONE Drift transaction — 3 phases, fix round 1/I2)

1. entry (outside txn): `sessionStillValid(epoch captured at commit
   entry, authValid)` — invalid ⇒ return, nothing written.
2. **Phase 1 — ack writes + cursor, ALL before the single re-check:**
   drainAck payload present ⇒ `outboxDao.byId(ack.opId)` INSIDE the txn
   (carry-in 1) ⇒ `setState(sent)` ⇒ drainAck message stamp — Task 2
   WHERE/SET byte-identical (`localId=op.ref & senderId &
   conversationId` → serverId/status `'sent'`/updatedAt) ⇒
   `_advanceCursor` (monotonic `write iff to.isAfter(current)` into
   `settings.sync_cursor_<convId>`, UTC ISO). Ledgered order (I2): the
   three dual-truth concerns sit pre-check so ONE abort covers them all.
3. **Phase 2 — `onBeforeWrite?.call()` ⇒ epoch re-check** ⇒ invalid ⇒
   `_EpochAbort` thrown inside the txn ⇒ EVERYTHING from phase 1 rolls
   back (state flip + stamp + cursor) ⇒ caught + logged, silent; phase 3
   never runs.
4. **Phase 3 — batch body:** upserts `deleteByServerIds` + one `db.batch`
   insert `DoUpdate(target: localId)` (fetch mechanics moved verbatim);
   tombstones `UPDATE messages SET is_deleted_for_everyone=1,
   updated_at=now WHERE server_id=?` (idempotent; unknown id = no-op).

### Call sites rewired (SEVEN write sites — reviewer enumeration)

1. **SSE handler** pin/delete fast-path write → `commit(batch, sse)`
   (the fast-path WRITE is gone, behavior kept — spec §4 "no SSE fast
   path"). SSE `_cacheMsg` call passes `source: sse`.
2. **`_cacheMsg`/`_cacheMsgInner`**: `_cacheMsg` gained
   `{IngestSource source = IngestSource.fetch}`; inner upsert →
   `commit(batch, source)`. loadMore / fetchAndCacheSingleMessage /
   history-sync call sites keep the default `fetch`.
3. **Fetch loop** (`_fetchAndCacheMessages`): `advance`/`newest` computed
   BEFORE the batch; `cursorAdvance` passed into `_cacheMessagesBatch`;
   `_writeCursor` DELETED (cursor rides the batch txn); post-commit
   `sessionStillValid` early-return kept (still gates the trailing sync
   passes).
4. **`_cacheMessagesBatch(records, key, myId, {CursorDelta? cursorAdvance})`**:
   delete+batch block → `commit`; self-heal per-row upserts → `commit`;
   its pre-commit session check KEPT (covers the decrypt window — a
   commit-time epoch capture would miss a mid-decrypt bump).
5. **`_syncDeletedForMe` / `_syncStarredMessages`** upserts →
   `commit(batch, fetch)`; companions completed with
   `replyToId`/`replyPreview`/`expiresAt` (see correction 4).
6. **`handleDrainAck`** body → `commit(IngestBatch(ack: …), drainAck)`;
   signature kept (later cleanup commit deletes it).
   `resolveDuplicateSend` + `isDuplicateIdError` untouched (carry-in 2 —
   create-side ownership checks; comments updated only).

### Corrections vs brief (reality rule)

1. **IngestBatch has a 4th field `ack: OutboxAck?`** — brief's sketch is
   3-field; the drain-ack message write cannot pre-resolve `op.ref`
   (the read must JOIN the txn — carry-in 1), so the payload rides the
   batch instead of being modeled as a pre-built MessageUpsert.
2. **Drain-ack in-txn order swapped** (Task 2: message→state; now
   state→message-stamp). Only observable under injected failure: it is
   what makes brief test 4 NON-vacuous (setState executes, failure lands
   at the status stage, rollback leaves op `queued` — without a txn the
   flip would persist as `sent`). The pair still lands or aborts
   together, which is all spec §5.1/§7 prescribes.
3. **Cursor is monotonic** (`write iff to > current`). Old `_writeCursor`
   overwrote unconditionally; production only ever advanced (incremental
   filter `created >= cursor`), so the guard bites only on the
   never-observed backward case — it pins test 1's "no skip".
4. **ONE write mechanic for all upserts = the fetch path's
   delete-then-insert** (SSE/fast-path/sync used `insertOnConflictUpdate`
   before). Ledgered deltas: (a) SSE/single path now deletes first —
   same final row (stable localId, preserved flags already in the
   companion) and it FIXES the FCM-placeholder serverId collision that
   previously threw out of the SSE handler; (b) `_sync*` companions had
   to gain `replyToId`/`replyPreview`/`expiresAt` — the old conflict
   update preserved those columns implicitly, a rebuild-from-companion
   would reset them to defaults (commented in situ).
5. **Epoch abort = rollback of the WHOLE commit**, including a drain-ack
   state flip issued before the re-check — stronger than "skip the later
   writes".
6. **drainAck and the SSE pin/delete fast-path GAIN epoch guards** they
   never had (spec §11); harmless in tests (epoch stable, harness JWT
   valid), a behavior delta only in the logout window (post-logout
   writes now drop instead of resurrecting wiped rows).
7. **Cursor timing vs self-heal/bump tail**: cursor now advances WITH the
   batch (spec §7), not after `_cacheMessagesBatch`'s heal + conversation
   bump — the old "rows landed, session died during heal ⇒ cursor held"
   window closes atomically. No skip either way (rows and cursor match).

### Concerns / NOT moved (ledger — writer-domain audit targets)

- **FCM background write** `fcm_service.dart:497 upsertMessageByServerId`
  still writes a network-sourced record outside the boundary (separate
  file + isolate; outside the brief's modify list). Flag for the spec §4
  two-gate / Task 11-12 audit.
- **`_updateMsgReceiptStatus` / `_repairUndecrypted`
  (`cacheDecryptedBody`)** mutate `messages.status`/decrypt columns from
  local passes — not ingest writes; receipt-driven status vs the §5.1
  dual-truth rule belongs to a status audit. Untouched.
- **Create-side writers untouched** (sanctioned, spec §5.1): sendMessage
  enqueue txn, `_sendTextOp` dual-truth txn, sendMediaMessage,
  delete/star/pin local toggles, `_emitSystemMessage`,
  `create_group_screen.dart` local system row.
- Conversation-list bumps (`_bumpConversationForIncoming`,
  `updateLastMessage`) stay repo-side: derived metadata, not
  network-sourced records (outside the brief's commit contract).

### Tests

`test/offline/ingest_boundary_test.dart` 4/4:
1. same batch committed twice (sse then fetch) → exactly 1 row; cursor
   advances once; an OLDER cursor delta cannot rewind it;
2. tombstone → row flagged deleted-for-everyone, never hard-deleted;
   re-commit (sse) idempotent — still 1 row;
3. `onBeforeWrite` bumps epoch mid-commit → 0 rows, no cursor (nothing
   written; commit returns silently);
4. drainAck: injected `StateError` at the status stage → op stays
   `queued`, no stamp (rollback proof); control commit → op `sent` +
   `serverId`/`status='sent'` stamped together, 1 row.
Test 5: `send_fetch_char_test.dart` **3/3 VERBATIM** (file untouched —
char test 3 `… SKIPS cache` still pinned for Task 7). Full offline dir
**44 pass**; full suite **112 pass**; analyze **0 errors** (88 legacy).

### Fix round 1/5 — review I1 + I2 + doc count

**I1 — SSE pin/delete companion wiped `expiresAt`:** the boundary's
delete-then-insert rebuilds the row from the companion, and the SSE
pin/delete companion carried 18/19 columns — a disappearing message lost
its expiry on any SSE pin/delete toggle. AS-BUILT fix:
`MessageRepositoryImpl.ssePinDeleteCompanion({existing, serverPinned,
serverDeleted})` (`@visibleForTesting`) — the handler now calls this
single builder, which carries ALL 19 columns incl.
`expiresAt: Value(existing.expiresAt)` (the handler's `existing` read was
already there). Test `I1: SSE pin/delete companion preserves expiresAt
through the boundary` drives the PRODUCTION builder (a test-side copy
would not bite); mutation check: drop the column → `Actual: <null>` FAIL,
restore → GREEN.

**I2 — t4 rollback proof made complete:** commit reordered to 3 phases
(see sequence above): ack read + `setState(sent)` + message stamp +
`_advanceCursor` all execute BEFORE the hook/re-check; upserts/tombstones
after. Revised t4 batch now carries BOTH `ack` and `cursorAdvance`;
post-failure asserts all three — op `queued`, message unstamped
(`serverId` null, `status` pending), cursor **NULL** — i.e. a sequential
(non-txn) implementation would persist all three and FAIL the test.
Control commit asserts all three land together (op `sent`, stamp,
cursor == delta). Entry-level epoch check untouched; spec §7's
"re-checked before write" preserved (phase-3 upserts sit behind the
re-check; phase-1 writes are protected by the same abort's rollback).

**Doc — call-site count:** intro said "three call sites" (the brief's
plan phrase); actual rewire = SEVEN write sites: SSE pin/delete, drain-ack
body, fetch batch, self-heal, `_syncDeletedForMe`, `_syncStarredMessages`,
`_cacheMsgInner`. Corrected in intro + section header.

Tests after fix round: `ingest_boundary_test.dart` **5/5** (4 brief +
I1); char 3/3 verbatim; full suite **113 pass**; analyze **0 errors**
(88 legacy, unchanged).

## Task 7

Cache-policy flip — always-commit ciphertext, the :2484 fix (spec §7).
Commit subject `[Offline P4] Always-commit ciphertext — fetch no longer
skips on missing key` (own hash cannot appear in its body). Files:
`tables/messages_table.dart` + `app_database.dart` (+`app_database.g.dart`,
build_runner), `daos/messages_dao.dart`, `ingest_boundary.dart` (doc only),
`message_repository_impl.dart`, `test/offline/send_fetch_char_test.dart`
(test 3 flip only), `test/offline/always_commit_test.dart` (NEW).
Full suite **114 pass**; analyze **0 errors** (88 legacy, unchanged).

### AS-BUILT (consumed by tasks 8-9)

**Schema v9** (`schemaVersion => 9`; `if (from < 9)` AFTER `from < 8`):

```dart
// messages_table.dart
TextColumn get decryptState => text().withDefault(const Constant('ready'))();
TextColumn get keyId        => text().nullable()();
```

- `decryptState` default `'ready'` ⇒ migration `m.addColumn` marks every
  legacy row decryptable (they carry `decryptedBody`) with NO backfill.
- `keyId` nullable, NOTHING writes it at Task 7 — `_companionFromRecord`
  carries `Value(existing?.keyId)` (preserve only). Populate = Task 8.
- Same-migration limitation as v1-v8: `AppDatabase.test()` exercises
  onCreate only; the 8→9 upgrade path runs first in production.

**decrypt_state write sites (spec §5.1 semantics, Task 7 scope):**

```dart
// message_repository_impl.dart (private method)
String _ingestDecryptState({required String? decrypted, required bool keyMissing});
// decrypt-at-write success ⇒ 'ready' · key lookup threw (no attempt)
//   ⇒ 'key_missing' · key present but ciphertext missed ⇒ 'pending'
// 'failed' (terminal bad MAC) is NEVER written here — Task 8's verdict.
```

1. `_companionFromRecord(..., {required String decryptState})` — now
   REQUIRES the state; call sites pass `_ingestDecryptState(...)`.
   Batch path: `keyMissing: key == null` per row. `_cacheMsgInner` (SSE/
   loadMore/single/history): same. Batch self-heal success ⇒ literal
   `'ready'`.
2. `messages_dao.cacheDecryptedBody` — now ALSO writes
   `decryptState='ready'` (key-arrival repair must not leave the state at
   `key_missing` beside a resident body). This is THE heal write for
   `_repairUndecrypted`.
3. Rebuild-from-existing companions CARRY the state (omission ⇒ column
   default `'ready'` would clobber a `key_missing` row through the
   boundary's delete-then-insert): `ssePinDeleteCompanion`,
   `_syncDeletedForMe`, `_syncStarredMessages` — each gained
   `decryptState: Value(row/existing.decryptState)` + `keyId: …`.
4. NOT touched (default applies): create-side optimistic/drain-stamp
   upserts (plaintext body ⇒ `'ready'` correct, spec §5.1 "own sent =
   ready"), system-row emits, local toggle upserts (insertOnConflictUpdate
   with the column ABSENT ⇒ preserved on conflict, default only on fresh
   insert of an existing row — impossible for a toggle).

**Fetch path (the delete):** `_fetchAndCacheMessages` — the
`if (key != null)` wrapper around the cache call is GONE. Key lookup
still try/caught; `key = null` now flows into `_cacheMessagesBatch(all,
key, myId, cursorAdvance: …)` unconditionally ⇒ rows + cursor land in
ONE boundary txn (Task 6 structure untouched; `IngestSource.fetch`).
Log line changed: `committing ciphertext` (was `skipping cache`).

**`_cacheMessagesBatch(records, List<int>? key, …)` — null-key behavior:**
- decrypt hop SKIPPED (`decrypted = const {}`) — no attempt ⇒ `failedDecrypts`
  stays empty ⇒ the key-invalidating self-heal does NOT run on a keyless
  fetch (there is no key to invalidate; `_getConvKey` would just throw).
- encrypted reply preview sealed as `'🔒'` without an attempt (same
  rendering as today's empty-key SSE path).
- conversation bump preview falls back to `'New message'` (same as SSE).

**Cursor behavior:** unchanged mechanics (Task 6 monotonic `_advanceCursor`
inside the txn) — only WHEN it advances changed: a keyless fetch now
advances it WITH its rows (spec §7). Consequence ledgered below (poll heal).

**`_cacheMsg`/`_cacheMsgInner`: `List<int>? key`** — SSE handler and
history-sync now pass the NULL key through instead of `key ?? const
<int>[]` (sentinel was indistinguishable from a real key). loadMore /
fetchAndCacheSingleMessage pass non-null keys (they throw-and-skip before
the call — unchanged). Null key ⇒ no decrypt attempt, no single-row
self-heal, state `key_missing`.

**`ingest_boundary.dart`:** doc-only — class doc gained the always-commit
bullet ("commit never consults keys… cursor included; key resolution is a
reader/repair concern — DecryptPass, Task 8"). Zero code change: the
boundary was already key-agnostic; state rides the companion.

### Char test 3 flip (same commit, tests 1-2 byte-untouched)

`send_fetch_char_test.dart` test 3: title → `'…key MISSING still caches
(always-commit — Task 7 flipped)'`. TWO assertions now:
1. `repo.watchMessages('g1').first` ⇒ **`isEmpty` KEPT** — reason string
   changed to cite Task 9: `isGroupRowVisible` (group_visibility.dart)
   still hides undecryptable non-media rows, so the repo READ stream stays
   empty at Task 7. The read path is Task 9's domain (plan: read-path char
   tests keep their expectations until then).
2. NEW: `h2.db.messagesDao.watchMessages('g1')` ⇒ `hasLength(1)`,
   `decryptState=='key_missing'`, `decryptedBody` null — the cache-layer
   flip (the defect was "skips CACHE", so the cache is what must bite).

### Downstream adaptations (in-scope per dispatch: policy owns them)

- **Poll fallback repair kick** (`_startPollFallback`, SSE-down branch):
  `await _repairUndecrypted(active)` added after each poll fetch. WHY:
  pre-flip a keyless fetch never wrote the cursor, so every 5s poll
  re-delivered the same window and healed it once the key landed; post-flip
  the cursor is past those rows, so the poll's implicit heal is GONE.
  Restores while-open key-arrival healing (one indexed query; no-op when
  no stuck rows). SSE-up-while-open behavior is UNCHANGED (it never healed
  there — pre-flip required a reopen too; reopen still heals via the
  `_messagesStream` repair call).
- **`cacheDecryptedBody` state flip** (above) — without it, a repaired
  row keeps `key_missing` beside its body until the next full re-cache.

### Corrections vs brief (reality rule)

1. **`ingest_boundary.dart` "modify" = DOC ONLY.** The brief's parenthetical
   ("commit never consults keys; rows land with decrypt_state='key_missing'
   when key lookup throws") describes repo-side behavior — the boundary
   receives fully-built companions and never sees keys (Task 6 contract).
   Forcing a code change there would have been fake work; the policy note
   landed as a class-doc bullet.
2. **Char test 3 does NOT flip to `rows isNotEmpty` at the repo stream.**
   `isGroupRowVisible` hides undecryptable group rows (design D1:
   "ciphertext must never reach a bubble"), so a repo-level flip would be
   UNREACHABLE without a read-path edit Task 9 owns. Flip = cache-layer
   assertion (DB stream) + kept-empty repo assertion with a Task 9 reason.
   ⇒ **Device proof (brief Step 5) would show an EMPTY list for a group
   with a missing key at Task 7** — the placeholder capture is only
   reachable after Task 9 (or on a DM, where null-body rows render 🔒).
   Step 5 was DEFERRED-DEVICE by controller anyway; this nuance is for
   the deferred run.
3. **`keyMissing` detect = `key == null`, not empty-key sentinel.** The
   old `key ?? const <int>[]` pattern made "lookup threw" unrepresentable
   downstream; nullable params make the state derivation honest.
4. **state for "key present, decrypt missed" = `'pending'`** (spec §7
   "rows commit as pending (or key_missing when the key lookup throws)"),
   NOT `'failed'` — terminal bad-MAC is Task 8's DecryptPass verdict.
   Media rows with empty ciphertext + key present also land `'pending'`
   (nothing attempted; `getUndecryptableRows` excludes media today —
   Task 8 input).
5. **Edge ledgered: body-present + `key_missing`.** A re-fetch with the
   key gone over an already-decrypted row preserves `decryptedBody`
   (`decrypted ?? existing?.decryptedBody`) but writes state
   `key_missing` (literal brief rule). Harmless at T7 (no state readers);
   Task 8 should treat state as authoritative, body column as interim.

### Concerns / carry-forward (ledger)

- **FCM bg insert lies about state (NEW symptom of the v9 default):**
  `fcm_service.dart:498 upsertMessageByServerId` writes a ciphertext-only
  row with NO decryptState ⇒ fresh insert defaults `'ready'` with null
  body (conflict path preserves — column absent from the companion).
  Not touched: FCM is outside this brief's files and already ledgered for
  the spec §4 two-gate / Tasks 11-12 audit. Recommended one-liner when
  that audit lands: `decryptState: Value('pending')` (committed, never
  attempted — bg isolate has no key material).
- **`getUndecryptableRows` filters `decryptedBody.isNull()`** — must
  migrate to `decrypt_state IN ('pending','key_missing')` when Task 9
  drops the column (works unchanged until then; includes key_missing rows
  today ⇒ repair heals them).
- **Remaining key-skip sites (NOT the :2484 defect, unchanged by design):**
  `loadMoreMessages` and `fetchAndCacheSingleMessage` still swallow
  `MissingKeyException` BEFORE caching (their whole loop is skipped);
  only the cold/warm `_fetchAndCacheMessages` path always-commits per the
  brief. Pagination/backfill never-loses-window is unchanged (no cursor
  advance there either).
- **T9 forward-carry (Task 2 ruling re-check):** outbound encryption point
  UNCHANGED — `sendMessage` still enqueues plaintext `decryptedBody`
  (spec interim), drain encrypts. Nothing in Task 7 touches send. What
  makes T9's column drop need care: (a) `cacheDecryptedBody` now writes
  body+state (drop = delete body half, keep state flip); (b)
  `getUndecryptableRows` filter (above); (c) `_companionFromRecord` still
  computes `decryptedBody` (T9 removes the field, keeps decryptState);
  (d) read-path surfaces keyed on `decryptedBody` (`isGroupRowVisible`,
  search, previews) — pre-existing T9 scope, unchanged here.

### Tests

`test/offline/always_commit_test.dart` 1/1 (TDD: RED proven — pre-fix
run failed `Expected: an object with length of <1> Actual: []` at the
cache assertion with log `key not ready during fetch — skipping cache`):
fetch with NO key ⇒ 1 row `key_missing`, ciphertext byte-identical,
cursor `sync_cursor_g1 == 2026-10-07T10:00:00Z` (newest server stamp);
key seeded ⇒ warm re-fetch ⇒ SAME 1 row (`serverId srv1`), state
`ready`, body decrypted — id-based upsert, no duplicates (predicate wait
on the drift stream; a missing re-fetch would time out, a duplicate would
make length 2 — non-vacuous both ways).
Char 3/3 (test 3 flipped, tests 1-2 byte-untouched); full offline dir
**46 pass**; full suite **114 pass**; analyze **0 errors** (88 legacy).

---

## Tasks 8-11 AS-BUILT — see task-{8,9,10,11}-report.md in this directory

(reports carry the AS-BUILT signatures; protocol reports-as-handoff amendment)
