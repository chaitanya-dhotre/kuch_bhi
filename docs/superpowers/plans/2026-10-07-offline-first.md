# Offline-First Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the offline-first spine: single ingest boundary, outbox send FSM with idempotent client ids, media blob store, decrypt-on-read bodies with placeholders — app fully usable from Drift with zero network.

**Architecture:** Disjoint single-writer domains (IngestBoundary for network-sourced records, MediaBlobStore for blob rows/files), Drift table as durable send queue, ciphertext-only bodies with a body provider for lazy decrypt. Phases are behavior-preserving extractions until the Phase-4 cache flip; each task ships alone.

**Tech Stack:** Flutter, Riverpod, Drift (schemaVersion 6 → 10 across tasks), pocketbase 0.21 (`httpClientFactory` test seam), `connectivity_plus`, `package:http/testing` MockClient, `Isolate.run` for crypto.

**Spec:** `docs/superpowers/specs/2026-10-07-offline-first-design.md` (binding authority — policy tables live there; this plan implements them).

## Execution protocol (user law, 2026-10-07 — overrides defaults)

1. **Task 1 alone first** — it holds the custom-ID STOP gate; Plan B would redesign outbox+ingest, so NO later task starts until Task 1's result is seen.
2. **Strictly sequential** — never parallel; each subagent builds on the previous task's REAL code.
3. **Handoff note per task** — implementer records signatures/paths AS BUILT (not as planned) and commits them to `.superpowers/sdd/2026-10-07-offline-first/handoff.md`; the next implementer reads that file, not the plan's guesses.
4. **Reviewers get spec section + diff** — "matches spec" beats "looks fine"; name the spec § in every review dispatch.
5. **Weighted review:** FULL implementer+reviewer pass for Tasks **2, 3, 6, 7, 8** (data-loss/race risk); lighter review OK for Tasks **4, 10, 12**. Others: standard.
6. **Whole-branch review at the end** — cross-task problems (duplicated writer path, leftover bypass) show up only here.

## Global Constraints (from spec — verbatim values)

- No server/PocketBase changes. Custom-id = spec Plan A; if verification fails, STOP and report to user (Plan B is a redesign, not an inline fallback).
- Disjoint single-writer domains: only `IngestBoundary` writes network-sourced records; only `MediaBlobStore` writes blob rows + files; no third writer, no SSE fast path.
- No plaintext at rest: after Task 9 there is no `decrypted_body` column, no FTS/search index table, no persisted notification text. Search results ephemeral — never written to the body memcache.
- `op_id` = 15 random lowercase `[a-z0-9]` (PocketBase id alphabet/length). Duplicate-id on retry → fetch record, verify `sender_id` + `conversation_id` ours → success; foreign record → terminal error.
- Terminal error classes exactly `{400, 403, 404, 413}`. `401` → pause ENTIRE outbox until re-auth (never terminal). `429` → retryable, honor `Retry-After`. Everything transient → `queued` + exponential backoff with jitter, cap 5 minutes; `attempts` reset on connectivity-restored events.
- Per-conversation FIFO by `seq`; `failed_terminal` blocks later ops of THAT conversation until user retry/discard; discard cascades to ops with `depends_on` on the discarded op.
- Media: `kMediaCacheMaxBytes = 300 * 1024 * 1024` config constant, watermark 85%, deferred eviction only (app start / watermark — never on write path), protected = derived (`uploadPending ∨ starred ∨ pinned`), files app-private only, offline stays `queued`.
- Session-epoch guards on EVERY async writer — boundary commits, DecryptPass applies, janitor, blob downloads; results arriving after logout/account-switch are dropped, not applied. Logout wipe set per spec §11; decrypt cache also cleared on app backgrounding.
- Placeholder law: every body consumer handles "decryptable but not resident" through `messageBodyProvider` — never blanks, never spinner-blocks.
- Import gate enabled ONLY in Task 11; covers `package:http`, `Dio`, `package:pocketbase/`, `dart:io HttpClient/WebSocket/Socket`, `web_socket_channel`, `firebase_*`, `connectivity_plus` — nothing outside the sanctioned paths `lib/infrastructure/`, `lib/services/`, `lib/core/network/`, `lib/main.dart`, `lib/firebase_options.dart` (carve-outs ledgered — UI/data/domain/core stay network-free).
- `flutter analyze` 0 errors + `flutter test` green after every task; no commit until user PASS; commit messages end `Co-Authored-By: Claude Code <noreply@anthropic.com>`.
- Extractions are behavior-preserving; every behavior change ships in its own commit (guard 5).

## Review Focus (spec-implied failure modes → owning task's test)

1. Kill between message-row and outbox-row writes → ghost message or lost send — Task 2 rollback test (injected failure mid-transaction asserts neither row survives).
2. Three delivery paths (drain-ack, SSE echo, timeout-retry) → duplicate bubbles — Task 2/6 idempotency test with MockClient (create → dup-id → ownership check → single row).
3. Async worker results applied after logout/account-switch → cross-account DB writes — Task 8 epoch test (bump epoch, deliver results, assert dropped) and Task 6 boundary epoch test.
4. Offline vs dead-link confusion: a dead URL must not silently re-queue forever, and a reconnect must not wait out a 5-minute backoff — Task 3 tests (404→terminal persists; connectivity event resets attempts and drains).
5. LRU eviction deletes the only copy of an un-uploaded outgoing file — Task 5 eviction test (protected predicate skips `uploadPending ∨ starred ∨ pinned`).
6. Fast scroll / resume floods decrypt work, and search typing races a scan — Task 8 coalescing test (N provider reads → ≤2 batch jobs) and Task 9 debounce/cancel test.
7. SSE gap + pull fetch double-apply or skip messages — Task 6 cursor test (same batch committed twice leaves one row set, cursor monotonic).

---

### Task 1: Phase 0 — characterization harness + read-path tests + custom-id verification

**Files:**
- Modify: `lib/core/network/pocketbase_client.dart` (add `@visibleForTesting` constructor)
- Create: `test/offline/char_harness.dart`
- Create: `test/offline/read_paths_char_test.dart`
- Create: `test/offline/send_fetch_char_test.dart`
- Test doc: `docs/offline-phase0-verification.md` (custom-id results)

**Interfaces:**
- Produces (consumed by every later task's tests): `PocketBaseClient.forTest(PocketBase pb)`, `charHarness()` returning `(PocketBaseClient, AppDatabase, FakeSecureStorage, EncryptionService)` seeded with one conversation + one member + a DM key.
- Consumes: `AppDatabase.test()` (existing), `EncryptionService(SecureStorageService, PocketBaseClient)` plain ctor, `PocketBase(url, httpClientFactory: …)` test seam.

- [ ] **Step 1: Add the test constructor**

In `pocketbase_client.dart`, after `PocketBaseClient._(this._pb);`:

```dart
  /// Test seam: inject a PocketBase built with a MockClient
  /// (pocketbase's httpClientFactory exists "primarily for unit tests").
  @visibleForTesting
  PocketBaseClient.forTest(this._pb);
```
(`import 'package:flutter/foundation.dart';` if absent.)

- [ ] **Step 2: Write the harness** — `test/offline/char_harness.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/secure_storage/secure_storage_service.dart';
import 'package:kuch_bhi/services/encryption_service.dart';

/// Secure storage whose reads return fixture values (no platform channel).
/// `read` is the raw key-value entry EncryptionService uses for group keys
/// (`group_key_<convId>`) — seeded via [secrets].
class FakeSecureStorage extends SecureStorageService {
  FakeSecureStorage({this.userId = 'u_test', this.secrets = const {}});
  final String userId;
  final Map<String, String> secrets;
  final _overrides = <String, String?>{};
  @override Future<String?> read({required String key}) async =>
      _overrides.containsKey(key) ? _overrides[key] : secrets[key];
  void put(String key, String value) => _overrides[key] = value;
  void removeKey(String key) => _overrides[key] = null;
  @override Future<String?> getCurrentUserId() async => userId;
  @override Future<String?> getAuthToken() async => 'test-token';
  @override Future<String?> getPbAuthStore() async =>
      '{"token":"test-token","model":{"id":"$userId"}}';
  @override Future<String?> getPrivateKey() async => null; // DM path unused in tests
  @override Future<String?> getLocalPublicKey() async => null;
}

class CharHarness {
  CharHarness(this.db, this.pbClient, this.storage, this.encryption);
  final AppDatabase db;
  final PocketBaseClient pbClient;
  final FakeSecureStorage storage;
  final EncryptionService encryption;
  Future<void> close() => db.close();
}

/// Builds a harness whose PocketBase answers with [handler] for every HTTP call.
CharHarness charHarness({http.Client Function()? clientFactory}) {
  final pb = PocketBase('http://pocketbase.test',
      httpClientFactory: clientFactory ?? http.Client.new);
  final client = PocketBaseClient.forTest(pb);
  final storage = FakeSecureStorage();
  final db = AppDatabase.test();
  return CharHarness(db, client, storage, EncryptionService(storage, client));
}

/// Seeds the fixture every offline test shares: group conversation `g1`,
/// member row for the fake session user, (optionally) a cached group key.
/// Conversation + member live in Drift; the key lives in secure storage under
/// `group_key_g1` (see EncryptionService.getOrFetchGroupKey cache path).
Future<void> seedConversationAndKey(CharHarness h,
    {bool withKey = true, List<int> key = const [1, 2, 3, 4]}) async {
  final now = DateTime.now();
  await h.db.conversationsDao.upsertConversation(
    ConversationsTableCompanion.insert(
      id: 'g1', type: 'group', createdById: 'u_test',
      createdAt: now, updatedAt: now,
    ),
  );
  await h.db.conversationsDao.upsertMember(
    ConversationMembersTableCompanion.insert(
      id: 'm1', conversationId: 'g1', userId: 'u_test', joinedAt: now,
    ),
  );
  if (withKey) {
    h.storage.put('group_key_g1', base64.encode(key));
  }
}

/// The REAL repository wired to the harness — every offline test shares it
/// (add imports: message_repository_impl.dart, media_upload_service.dart).
MessageRepositoryImpl buildRepo(CharHarness h) => MessageRepositoryImpl(
      pbClient:           h.pbClient,
      db:                 h.db,
      storage:            h.storage,
      encryption:         h.encryption,
      mediaUploadService: MediaUploadService(h.pbClient, h.encryption),
    );
```

(`FakeSecureStorage extends SecureStorageService` — subclass overrides are the fake; if any getter is `final`, ledger the ruling and override via a test subclass of the underlying `FlutterSecureStorage` storage field instead. File imports: `dart:convert`, `package:kuch_bhi/data/local/database/app_database.dart` for the `*TableCompanion` types, plus the four listed.)

- [ ] **Step 3: Read-path characterization tests** — `test/offline/read_paths_char_test.dart` (these pin EXACTLY what Task 9 changes; they must pass NOW and must be re-run after Task 9 — same expectations, because the placeholder law says these surfaces behave the same with `decrypt_state != ready` as they do today with `decryptedBody == null`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/entities/message.dart';

Message msg({String? body}) => Message(
      localId: 'l1', conversationId: 'c1', senderId: 'u2',
      type: 'text', decryptedBody: body, status: 'sent',
      createdAt: DateTime(2026, 10, 7),
    );

void main() {
  testWidgets('bubble with null body renders without throwing (placeholder law baseline)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: warmPopLight(),
      home: Scaffold(body: ListView(children: [
        Text(msg(body: null).decryptedBody ?? '🔒'), // baseline: null-safe display path
      ])),
    ));
    expect(tester.takeException(), isNull);
  });

  test('conversation preview source tolerates null decryptedBody', () {
    final m = msg(body: null);
    final preview = (m.decryptedBody ?? '').isEmpty ? '' : m.decryptedBody!;
    expect(preview, '', reason: 'today: empty, never throws — Task 9 keeps it non-throwing');
  });

  test('chat search filter over null-body rows does not throw', () {
    final rows = [msg(body: 'alpha'), msg(body: null), msg(body: 'beta')];
    final q = 'a';
    final hits = rows
        .where((m) => (m.decryptedBody ?? '').contains(q))
        .toList();
    expect(hits.length, 1); // row with null body skipped, no crash
  });
}
```

- [ ] **Step 4: Write them — verify they pass NOW (they characterize current behavior)**

Run: `flutter test test/offline/read_paths_char_test.dart 2>&1 | tail -5`
Expected: PASS. (These are characterization tests: RED here means the harness contradicts reality — fix the test, not the app.)

- [ ] **Step 5: Send/fetch/SSE characterization tests** — `test/offline/send_fetch_char_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'char_harness.dart'; // buildRepo + seedConversationAndKey live here
```

Construct the repo via the harness helper `buildRepo(h)` (defined in
`char_harness.dart`, Step 2 — exact ctor call shared by every task):

Then the test file body (`void main() {` … three tests … `}`):

```dart
void main() {
test('char: send persists optimistic pending row before the network ack', () async {
  final h = charHarness(clientFactory: () => MockClient(
      (req) => Completer<http.Response>().future)); // never completes
  addTearDown(h.close);
  await seedConversationAndKey(h);
  final repo = buildRepo(h);

  final send = repo.sendMessage(conversationId: 'g1', plaintext: 'hello');
  await Future<void>.delayed(const Duration(milliseconds: 50)); // let enqueue land
  final rows = await h.db.messagesDao.watchMessages('g1').first;
  expect(rows, hasLength(1), reason: 'optimistic row exists pre-ack');
  expect(rows.first.status, 'pending');
  expect(rows.first.decryptedBody, 'hello'); // Task 9 drops this column by design
  // send is still pending on purpose — never awaited here
});

test('char: cold watchMessages with key fetches, decrypts and caches', () async {
  final pre = charHarness(); // throwaway: only to encrypt with the fixture key
  addTearDown(pre.close);
  final enc = await pre.encryption.encryptMessage('hello from server', [1, 2, 3, 4]);

  final h2 = charHarness(clientFactory: () => fetchListClient(enc: enc, conversationId: 'g1'));
  addTearDown(h2.close);
  await seedConversationAndKey(h2, withKey: true); // group_key_g1 = [1,2,3,4]
  final repo = buildRepo(h2);

  final rows = await repo.watchMessages('g1').first; // cold path awaits fetch
  expect(rows, isNotEmpty);
  expect(rows.first.decryptedBody, 'hello from server',
      reason: 'ciphertext decrypted at cache-write, row visible');
});

test('char: cold watchMessages with key MISSING skips cache (defect pinned — Task 7 flips)',
    () async {
  final pre = charHarness();
  addTearDown(pre.close);
  final enc = await pre.encryption.encryptMessage('lost key', [1, 2, 3, 4]);

  final h2 = charHarness(clientFactory: () => fetchListClient(enc: enc, conversationId: 'g1'));
  addTearDown(h2.close);
  await seedConversationAndKey(h2, withKey: false); // group_key_g1 absent
  final repo = buildRepo(h2);

  final rows = await repo.watchMessages('g1').first;
  expect(rows, isEmpty,
      reason: 'CHAR: pins the :2484 skip defect; Task 7 flips this expectation in its own commit');
});
}
```

`fetchListClient` helper (same file, above `main`) — a MockClient answering the ONLY URL the
cold path hits (`…/collections/messages/records`) with a PocketBase list envelope
whose single record carries the fields `_cacheMessagesBatch` reads (verified
minimum below — reconcile with `companionFromRecord` on first RED run and pin
what is real):

```dart
MockClient fetchListClient({required EncryptResult enc, required String conversationId}) =>
    MockClient((req) async {
      if (!req.url.path.contains('/collections/messages/records')) {
        return http.Response('{"message":"unhandled"}', 404);
      }
      return http.Response(
        jsonEncode({
          'page': 1, 'perPage': 40, 'totalItems': 1, 'totalPages': 1,
          'items': [{
            'id': 'srv1',
            'collectionId': 'messages', 'collectionName': 'messages',
            'created': '2026-10-07T10:00:00.000Z',
            'updated': '2026-10-07T10:00:00.000Z',
            'fields': {},
            'conversation_id': conversationId, 'sender_id': 'u_peer',
            'type': 'text', 'encrypted_body': enc.ciphertext, 'iv': enc.iv,
            'reply_to_id': '', 'reply_preview': '',
            'is_deleted_for_everyone': false, 'is_deleted_for_me': false,
            'is_pinned': false, 'is_starred': false,
            'status': 'sent', 'media_id': '',
          }],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
```
(`EncryptResult` + `encryptMessage(String plaintext, List<int> keyBytes)` are the
real signatures from `encryption_service.dart:249`.)

- [ ] **Step 6: Run the send/fetch tests**

Run: `flutter test test/offline/send_fetch_char_test.dart 2>&1 | tail -8`
Expected: PASS 3/3. If a test cannot pass because an internal (cursor field name, key row shape) differs, read the implementation and correct the TEST to pin actual behavior — characterization tests describe, they don't prescribe.

- [ ] **Step 7: Custom-id verification (Plan A gate)** — write `docs/offline-phase0-verification.md` recording:
  (a) `pocketbase` client 0.21 + server 0.37.5: client passes `id` through create body — cite pocketbase SDK source (create body is opaque JSON, no id stripping);
  (b) collection create rule: fetch `GET /api/collections/messages` with a normal auth token (app login session via existing test account — a read, no superuser) and paste the `createRule` + confirm no field-level `id` restriction; (c) one authenticated test create in a throwaway record with a 15-char `[a-z0-9]` id, then a second create with the SAME id expecting the duplicate error shape, then fetch-by-id verifying ownership fields.
  **If (b) or (c) fails: STOP. Report to user — do not start Task 2 (spec §16 Plan B is a redesign).**
  Running (b)/(c) may be done via a small `dart run` script using the app's own login (never the superuser password file — standing security rule).

- [ ] **Step 8: Full verification + PASS gate**

Run: `flutter analyze 2>&1 | grep -c "error •"` → `0`; `flutter test 2>&1 | tail -1` → `All tests passed`.
Present: verification doc + test list → **STOP for user PASS** → commit `test/offline/* + forTest seam + verification doc` as `[Offline P0] Characterization harness + custom-id verification`.

---

### Task 2: Outbox core — table, FSM, id generator, atomic enqueue, interim ack

**Files:**
- Create: `lib/data/local/database/tables/outbox_table.dart`
- Create: `lib/data/local/database/daos/outbox_dao.dart` (+ `.g.dart` via build_runner)
- Modify: `lib/data/local/database/app_database.dart` (register table, **schemaVersion 7**, migration `m.createTable(outbox)`)
- Create: `lib/core/utils/op_id.dart`
- Modify: `lib/infrastructure/repositories/message_repository_impl.dart` (`sendMessage` → enqueue-only; interim `handleDrainAck`)
- Modify: `test/offline/char_harness.dart` (FakeSecureStorage: fail loudly on unoverridden members)
- Test: `test/offline/outbox_core_test.dart`

**Interfaces:**
- Produces: `generateOpId() → String` (15-char `[a-z0-9]`); `OutboxState {queued, sending, sent, failedTerminal}`; `db.outboxDao.enqueue(...)` (insert inside the caller's shared txn); `messagesDao.countForConversation(String) → Future<int>` (new query helper, used by tests); `MessageRepositoryImpl.handleDrainAck(String opId, {required String serverId, required String senderId, required String conversationId})` (interim — Task 6 replaces its body with a boundary call).
- Consumes: Task 1 harness; existing `messagesDao` insert APIs; `EncryptionService.encryptMessage` path already inside current `sendMessage`.

- [ ] **Step 1: Failing tests** — `test/offline/outbox_core_test.dart`:

```dart
import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:kuch_bhi/core/utils/op_id.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'char_harness.dart';

void main() {
  test('generateOpId: 15 chars, lowercase [a-z0-9], unique over 10k', () {
    final ids = {for (var i = 0; i < 10000; i++) generateOpId()};
    expect(ids.length, 10000);
    for (final id in ids.take(100)) {
      expect(id.length, 15);
      expect(RegExp(r'^[a-z0-9]{15}$').hasMatch(id), isTrue);
    }
  });

  test('enqueue is atomic: failure after message write rolls back BOTH rows', () async {
    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    Object? thrown;
    try {
      await h.db.transaction(() async {
        await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
          localId: 'l_atomic', conversationId: 'g1', senderId: 'u_test',
          type: 'text', encryptedBody: 'x', createdAt: DateTime.now(),
        ));
        await h.db.outboxDao.enqueue(OutboxTableCompanion.insert(
          opId: generateOpId(), kind: 'text_send', ref: 'l_atomic',
          conversationId: 'g1', seq: 1, createdAt: DateTime.now(),
        ));
        throw StateError('simulated kill window');
      });
    } catch (e) { thrown = e; }
    expect(thrown, isNotNull);
    expect(await h.db.messagesDao.countForConversation('g1'), 0);
    expect(await h.db.outboxDao.all(), isEmpty,
        reason: 'ghost message / lost send impossible: txn rolls back both');
  });

  test('own-message enqueue is complete while network hangs (never a placeholder)', () async {
    final h = charHarness(clientFactory: () =>
        MockClient((req) => Completer<http.Response>().future)); // never answers
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h); // identical helper to Task 1

    final send = repo.sendMessage(conversationId: 'g1', plaintext: 'queued msg');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final rows = await h.db.messagesDao.watchMessages('g1').first;
    expect(rows, hasLength(1));
    expect(rows.first.status, 'pending');
    expect(rows.first.decryptedBody, 'queued msg');
    expect((await h.db.outboxDao.all()).map((r) => r.kind), ['text_send'],
        reason: 'outbox row exists before any network I/O');
    // `send` intentionally never awaited
  });
}
```

Carry-in tests (user PASS-gate conditions for Task 2 — add to the same file):

```dart
  test('duplicate-id counts as success ONLY when the error field is id', () async {
    // Scripted create retry: PB returns 400 validation_not_unique on FIELD id
    // → treated as already-sent (then ownership GET verifies, below).
    // Scripted 400 validation_not_unique on a DIFFERENT field (e.g. 'iv')
    // → NOT success; op stays failed/queued per error class — an unrelated
    // unique-constraint failure must never be counted as delivered.
  });

  test('triple delivery: drain-ack + SSE echo + timeout-retry → exactly one row', () async {
    // 1) create with id=opId → 200; ack path
    // 2) SSE echo of the same record id → idempotent upsert, no second row
    // 3) timeout-retry → 400 validation_not_unique(id) → ownership GET:
    //    a) record with our sender_id+conversation_id → success (no re-create)
    //    b) ownership GET 404 or 403 (foreign record / hidden by view rule)
    //       → outbox state failedTerminal, errorClass 'id_collision' —
    //       NEVER retried, NEVER counted as success
    //    c) record exists but sender_id/conversation mismatch → failedTerminal
    // All three paths end with exactly ONE local message row.
  });
```

- [ ] **Step 2: Run → verify RED** (op_id undefined, outboxDao undefined, countForConversation missing).

- [ ] **Step 3: Implement**
  - `lib/core/utils/op_id.dart`:
```dart
import 'dart:math';
/// 15-char client id in PocketBase's id alphabet — becomes the server record id.
final _rng = Random.secure();
const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
String generateOpId() =>
    List.generate(15, (_) => _alphabet[_rng.nextInt(_alphabet.length)]).join();
```
  - `outbox_table.dart`: columns `opId (PK text)`, `kind text`, `ref text`, `conversationId text`, `seq int`, `state text` (default `queued`), `attempts int default 0`, `nextAttemptAt dateTime nullable`, `createdAt dateTime`, `lastError text nullable`, `errorClass text nullable`, `dependsOn text nullable`.
  - `outbox_dao.dart`: `enqueue(txn-safe insert)`, `Future<OutboxRow?> byId`, `Future<List<OutboxRow>> due(DateTime now)`, `Future<void> setState(...)`, `Future<void> bumpSeq` (per-conversation max+1 helper `Future<int> nextSeq(String conversationId)`), `all()`, `forConversation(id)`.
  - DB: register, bump `schemaVersion` to 7, in `onUpgrade` `if (from < 7) await m.createTable(outbox);` — run `dart run build_runner build --delete-conflicting-outputs`.
  - `sendMessage` refactor: keep signature; body = encrypt (existing code) + single `db.transaction` { insert message row (status pending, decryptedBody = plaintext — kept until Task 9 per spec interim) + `outboxDao.enqueue(kind: text_send, ref: localId, seq: nextSeq, state: queued)` } + kick `OutboxWorker` drain hook if constructed (Task 3 owns worker — here: call the existing connectivity retry method as the interim drain kick, renamed `_drainOutbox` stub that performs the OLD network send moved verbatim from sendMessage — behavior-preserving, guard 5).
  - `handleDrainAck(opId, {serverId, senderId, conversationId})`: txn { update message `serverId/status=sent` + `outboxDao.setState(opId, sent)` } with duplicate-id safety left to Task 6 boundary (interim comment: `// INTERIM: absorbed by IngestBoundary in Task 6`).
  - **Duplicate-error parsing (carry-in):** on create-retry 400 `validation_not_unique`, inspect the error body and proceed as already-sent ONLY when the offending field is `id` (PB error body carries the field name under `data.*`); any other field → not-success (map via error class, not the dup path).
  - **Ownership GET failure (carry-in):** after a confirmed id-dup, GET the record by id; `404`/`403` (view rule hides foreign records) or sender/conversation mismatch → `outbox.setState(opId, failedTerminal, errorClass: 'id_collision', lastError: …)` — terminal, never retried.
  - **FakeSecureStorage hardening (carry-in):** add `@override dynamic noSuchMethod(Invocation i) => throw UnimplementedError('FakeSecureStorage.${i.memberName} — override before use (handoff.md lists all 17)');` so ANY non-overridden member fails loudly instead of hitting real storage — no defaults, no flaky tests.

- [ ] **Step 4: GREEN** — `flutter test test/offline/outbox_core_test.dart` → PASS; full suite green; analyze 0.

- [ ] **Step 5: Behavior-change split:** this task's commit message says exactly what changed behavior (network send moved behind drain stub) vs extracted.

- [ ] **Step 6: STOP for PASS** → commit `[Offline P1] Outbox table + FSM data layer + atomic enqueue`.

---

### Task 3: OutboxWorker — drain, backoff, error classes, FIFO, stale recovery

**Files:**
- Create: `lib/infrastructure/offline/outbox_worker.dart`
- Modify: `message_repository_impl.dart` (drain stub → delegates to worker; `_initConnectivityRetry` → worker hooks)
- Test: `test/offline/outbox_worker_test.dart`

**Interfaces:**
- Produces: `OutboxWorker({required OutboxDao outbox, required MessageRepository repo-ish sender callback, DateTime Function() now, Random random, …})` with `Future<void> drain()`, `void onConnectivityRestored()`, `void onAuthPaused(bool)`, `void onAuthResumed()`; repo gains `Future<void> retryOp(String opId)`, `Future<void> discardOp(String opId)` (cascade via `dependsOn`); pause persisted via `settingsDao` key `outbox_pause`.
- Consumes: Task 2 table/dao/`handleDrainAck`; `Connectivity().onConnectivityChanged` (existing `_initConnectivityRetry` lines 505-510 move here).

- [ ] **Step 1: Failing tests** (`fake now` + seeded rows; MockClient scripted responses):

1. `404 on send → failedTerminal persists; NOT re-queued by later drains`.
2. `401 on send → EVERY queued op paused (settingsDao outbox_pause='auth'); queue untouched; onAuthResumed() → drains again`.
3. `429 with Retry-After: 7 → nextAttemptAt >= now+7s (fake clock); without header → exponential backoff with jitter within [base·2^n, base·2^n·1.25]; cap 5 min`.
4. `connectivity restored → attempts reset to 0 and immediate drain (a row waiting 4 min backoff sends now)`.
5. `FIFO: op seq2 stays queued while seq1 is failedTerminal (same conversation); other conversation drains; discardOp(seq1) cascades: dependent message_send op with dependsOn=seq1 also queued→removed, and its message row deleted`.
6. `stale sending: rows in sending state at worker construction → reset to queued (kill-mid-queue)`.
7. `jitter uses injected Random (same seed → same delay — determinism)`.
8. `two-step media: message_send with dependsOn=<media_upload op> stays queued while that op is queued/sending; drains only after upload op reaches sent (spec §5.2 dependency)`.

- [ ] **Step 2: RED** run → fail (class missing).

- [ ] **Step 3: Implement** the FSM as a pure function for testability:
```dart
/// Returns null = stay queued with no schedule change; else nextAttemptAt.
DateTime? nextAttempt({
  required int httpStatus, required String? retryAfterHeader,
  required int attempts, required DateTime now,
  required DateTime Function() clock, required Random random,
}) { … } // encodes spec §6: {400,403,404,413} → throw TerminalOpError (caller sets failedTerminal);
// 401 → PauseAll; 429 → retryAfter ?? backoff; transient → backoff;
// backoff = min(300s, 5s * 2^attempts) * (1 + random.nextDouble()*0.25)
```
Worker loop: load due ops ordered by `(conversationId, seq)`; skip conversations whose head is `failedTerminal`; **skip ops whose `dependsOn` is not `sent`** (gates the two-step media flow: `media_upload` drains first, its dependent `message_send` waits); skip global pause; per op: mark `sending`, run the **kind sender** — `text_send` → the network-create code moved verbatim from old `sendMessage`; `media_upload` → `mediaUploadService.upload(...)` moved verbatim — map errors via `nextAttempt`, update states. Wire connectivity listener (moved from repo lines 505-510) → `onConnectivityRestored` (attempts=0 for all queued + immediate `drain()`).

- [ ] **Step 4: GREEN** — worker tests + full suite + analyze 0.

- [ ] **Step 5: STOP for PASS** → commit `[Offline P1] OutboxWorker — backoff, 4xx classes, FIFO, recovery`.

---

### Task 4: Terminal-failure UI — stuck-message banner + retry/discard

**Files:**
- Modify: `lib/features/chat/widgets/message_bubble.dart` (failed-op banner slot)
- Create: `lib/features/chat/providers/outbox_status_provider.dart` (`StreamProvider` over outbox rows for the open conversation)
- Test: `test/offline/terminal_banner_test.dart` + gate addition in `test/grep_gates_test.dart`

**Interfaces:**
- Produces: `outboxStatusProvider(ConversationId) → AsyncValue<List<OutboxRow>>`; bubble reads it for its `localId` and when `state == failedTerminal` renders the banner; banner actions call `repo.retryOp/discardOp`.
- Consumes: Task 3 `retryOp/discardOp`, Task 2 row shape.

- [ ] **Step 1: Failing widget test** — pump a chat list with one message whose op is `failedTerminal` (`errorClass: 'dead_link'`) seeded in DB, provider overridden by `Stream.value([...])`:
```dart
expect(find.text('Failed to send'), findsOneWidget);      // banner title
expect(find.text('Retry'), findsOneWidget);
expect(find.text('Discard'), findsOneWidget);
await tester.tap(find.text('Discard'));
// verify discardOp called on a fake repo (mocktail-free: implement MessageRepository fake)
```
- [ ] **Step 2: RED** → **Step 3: Implement** banner as a warm-pop inline strip (`t.error` @8% bg, `t.error` text, radius `WarmPopTokens.radiusSm`) inserted in the bubble's build when the outbox row for this message is `failedTerminal`; Discard → `discardOp` (deletes message row + cascade, Task 3); Retry → `retryOp`.
- [ ] **Step 4: GREEN** + full suite + analyze 0.
- [ ] **Step 5: Device proof** (emulator: seed a terminal op via debug hook or dead-endpoint conversation) → capture `off_terminal_banner.png` → **STOP for PASS** → commit `[Offline P1] Terminal-failure banner — retry/discard UI`.

---

### Task 5: MediaBlobStore — requestBlob, FSM, janitor, deferred eviction

**Files:**
- Create: `lib/data/local/database/tables/media_blob_table.dart` + `daos/media_blob_dao.dart` (+ build_runner)
- Create: `lib/infrastructure/media/media_blob_store.dart`
- Modify: `app_database.dart` (**schemaVersion 8**, `createTable(mediaBlob)` when `from < 8`)
- Modify: `lib/features/chat/providers/chat_provider.dart` media path → calls `requestBlob` (behavior-preserving wiring)
- Test: `test/offline/media_blob_store_test.dart`

**Interfaces:**
- Produces: `MediaBlobStore.requestBlob(String blobId, String reason)` (SINGLE entry), `Future<void> janitor()`, `Future<void> evictIfNeeded()`, config `const kMediaCacheMaxBytes = 300 * 1024 * 1024; const kMediaCacheWatermark = 0.85;` in `lib/core/constants/app_constants.dart`; states `{queued, downloading, ready, failed, evicted}` + `errorClass`.
- Consumes: repo's existing download+decrypt helpers (moved verbatim into the store — guard 5), `MediaRef`/`mediaFileProvider` consumers.

- [ ] **Step 1: Failing tests:**
1. `offline → requestBlob leaves state queued; onConnectivity → drains to downloading→ready` (MockClient bytes + fake hash).
2. `kill mid-download: stale downloading row + orphan temp file → janitor() resets to queued and deletes temp`.
3. `eviction: seed 301MB of ready blobs (bytes column arithmetic — no real files needed for the LRU pick test, plus one 1KB real file) → evictIfNeeded() deletes only LRU unprotected; protected = uploadPending OR starred(message) OR pinned(message) survive; total after ≤ kMediaCacheMaxBytes; state becomes evicted (metadata kept)`.
4. `dead URL → failed(dead_link); verify mismatch → failed(verify); decrypt fail → failed(decrypt) — none auto-retry`.
5. `ready means on-disk decrypted: file exists under app-private dir (test temp dir) and is NOT ciphertext (magic bytes check)`.

- [ ] **Step 2: RED** → **Step 3: Implement** store (states enum, single `requestBlob` switch, download→verify→decrypt pipeline, janitor, `evictIfNeeded` reading `bytes` column with `ORDER BY last_access` skipping the derived-protected predicate join).

- [ ] **Step 4: GREEN** + full suite + analyze 0.

- [ ] **Step 5: STOP for PASS** → commit `[Offline P2] MediaBlobStore — blob FSM, janitor, deferred eviction`.

---

### Task 6: IngestBoundary extraction — one entry, txn+cursor, tombstones

**Files:**
- Create: `lib/infrastructure/ingest/ingest_boundary.dart` (+ `ingest_batch.dart`)
- Modify: `message_repository_impl.dart` (SSE handler, fetch loop, interim `handleDrainAck` body → delegate to `boundary.commit(batch, source)`; DELETE the fast-path writes)
- Test: `test/offline/ingest_boundary_test.dart`

**Interfaces:**
- Produces: `enum IngestSource {sse, fetch, drainAck}`; `class IngestBatch {upserts: List<MessageUpsert>, tombstones: List<String>, cursorAdvance: CursorDelta?}`; `Future<void> commit(IngestBatch batch, IngestSource source)` — ONE transaction: message upserts (by server id) + cursor + outbox ack state + messages.status; session-epoch checked at entry and immediately before write; duplicate-id already resolved upstream (create path) so commit is idempotent upserts.
- Consumes: Task 2 `handleDrainAck` semantics, Task 1 char tests (they must STILL pass — extraction is behavior-preserving; test 3 `char: fetch … SKIPS cache` unchanged until Task 7).

- [ ] **Step 1: Failing tests:**
1. `same batch committed twice (SSE echo + fetch) → one row set, cursor monotonic (no skip/double-apply)`.
2. `tombstone in batch → row marked deleted; re-commit idempotent`.
3. `epoch bumped mid-commit (simulate: bump between entry-check and write via injected hook) → nothing written`.
4. `drainAck source updates outbox.state + messages.status in the SAME transaction (inject failure in status write → op stays queued)`.
5. **Regression:** re-run `test/offline/send_fetch_char_test.dart` — all three char tests must still pass verbatim.

- [ ] **Step 2: RED** → **Step 3: Implement** boundary; rewire the three call sites; the interim ack handler's body becomes `boundary.commit(batch, IngestSource.drainAck)` (handler signature kept until deleted in a later cleanup commit — behavior change noted).

- [ ] **Step 4: GREEN** — new tests + ALL Task 1 char tests + full suite + analyze 0.

- [ ] **Step 5: STOP for PASS** → commit `[Offline P3] IngestBoundary — single entry, cursor+ack in one txn (behavior-preserving)`.

---

### Task 7: Cache-policy flip — always commit ciphertext (the :2484 fix)

**Files:**
- Modify: `ingest_boundary.dart` (commit never consults keys; rows land with `decrypt_state='key_missing'` when key lookup throws)
- Modify: `app_database.dart` (**schemaVersion 9**: `addColumn(messages.decryptState)` default `'ready'` for legacy decrypted rows, `addColumn(messages.keyId)` nullable; `messages_table.dart` + regen)
- Modify: `message_repository_impl.dart` (delete the `MissingKeyException → skip cache + no cursor` block at the fetch path; cursor advances with the batch via boundary)
- Modify: Task 1 `test/offline/send_fetch_char_test.dart` **test 3 only** — expectation flips by design, comment cites Task 7
- Test: `test/offline/always_commit_test.dart`

**Interfaces:**
- Produces: rows committed under missing keys visible to readers with `decrypt_state='key_missing'`; legacy rows default `ready` (they carry `decryptedBody`).
- Consumes: Task 6 boundary, Task 1 harness.

- [ ] **Step 1: Failing test** — `always_commit_test`: fetch with NO key → **rows DO land** (count>0, `decrypt_state='key_missing'`, cursor advanced); re-fetch after key arrives → same rows upserted again WITHOUT duplicates (id-based upsert).

- [ ] **Step 2: RED** (current code skips) → **Step 3: Implement** boundary commit + migration + delete skip block; flip char test 3 expectation in the SAME commit (own commit: behavior change, guard 5).

- [ ] **Step 4: GREEN** — always_commit + flipped char test + full suite + analyze 0.

- [ ] **Step 5: Device proof** (open a group whose key is not yet ready — or debug-fail key fetch): chat shows rows as placeholders instead of an empty list → capture `off_key_delay_placeholders.png` → **STOP for PASS** → commit `[Offline P4] Always-commit ciphertext — fetch no longer skips on missing key`.

---

### Task 8: DecryptPass + messageBodyProvider + body cache

**Files:**
- Create: `lib/core/decrypt/decrypt_pass.dart` (batch orchestrator + `Isolate.run` crypto)
- Create: `lib/core/decrypt/body_cache.dart` (LRU, bounded 500 entries, `clear()`)
- Create: `lib/features/chat/providers/message_body_provider.dart`
- Modify: `app.dart` (lifecycle: `WidgetsBindingObserver` → `bodyCache.clear()` on background; logout wipe already covered by existing epoch path — call `bodyCache.clear()` there too)
- Test: `test/offline/decrypt_pass_test.dart`

**Interfaces:**
- Produces:
  - `DecryptPass({required AppDatabase db, required EncryptionService enc, required int Function() epoch})` — `Future<void> runFor(List<String> messageIds)`; crypto via `Isolate.run(() => _decryptBatch(items, keyMaterial))` (spec's SendPort transport realized as isolate RPC — results return async to main), apply step: `if (epochAtSchedule != epoch()) return;` then DB updates + `bodyCache.put` + provider invalidation. Batches ≤50 run inline on main; larger via isolate.
  - `messageBodyProvider(String messageId) → Future<String?>` — cache hit instant; miss joins a 50ms coalescing window, then `runFor(joinedIds)`; decrypt-time bad MAC → write `decrypt_state='failed'` (terminal) for that row.
  - `bodyCache` global with `clear()` wired to backgrounding + logout.
- Consumes: Task 7 `decrypt_state`/`key_id`, Task 1 `EncryptionService` harness.

- [ ] **Step 1: Failing tests:**
1. `provider coalescing: fire 40 reads in one frame → ≤2 runFor invocations (instrument via counting decorator)`.
2. `epoch drop: schedule runFor, bump epoch before isolate result lands (inject async gap with a completer), apply step dropped — DB still key_missing, cache empty`.
3. `bad MAC on lazy path → row decrypt_state='failed'; second runFor on same row does nothing (terminal).`
4. `backgrounding: bodyCache.clear() then re-read → provider re-decrypts and emits (AsyncValue completes).`
5. `search-style batch of 60 rows goes through isolate path (≥51) and lands all bodies` (proves both batch lanes).

- [ ] **Step 2: RED** → **Step 3: Implement** (keys resolved main-side from `EncryptionService`/conversation key lookup and passed as plain data into the isolate closure; worker returns `List<(id, plaintext, newState)>`; main applies with epoch re-check).

- [ ] **Step 4: GREEN** + full suite + analyze 0.

- [ ] **Step 5: STOP for PASS** → commit `[Offline P4] DecryptPass + messageBodyProvider — lazy, coalesced, epoch-guarded`.

---

### Task 9: Placeholder UI + drop `decrypted_body` + search debounce/cancel

**Files:**
- Modify: `message_bubble.dart`, chat tile preview source, `chat_screen.dart` search filter — all body reads → `ref.watch(messageBodyProvider(id))`
- Create: `lib/features/chat/widgets/message_body_text.dart` (the placeholder renderer: skeleton line + 🔒 hint while `AsyncValue.loading`, text when data)
- Modify: `messages_table.dart` + `app_database.dart` (**schemaVersion 10: drop `decryptedBody`**; decryptState/back-compat re-derivation not needed — provider handles)
- Modify: `chat_screen.dart` search (debounce 200ms, cancellable token per keystroke, filter over resolved bodies, results NEVER touch `bodyCache` beyond provider's own reads — search uses its own ephemeral map)
- Test: `test/offline/placeholder_ui_test.dart`, update Task 1 read-path tests' expectations to the SAME user-visible outcomes

**Interfaces:**
- Produces: `MessageBodyText({required String messageId, required String styleContext…})` widget; every consumer compiles only through the provider.
- Consumes: Task 8 provider; Task 1 read-path tests.

- [ ] **Step 1: Failing tests:**
1. `bubble with key_missing row renders placeholder (find.byKey(ValueKey('body-placeholder-<id>')), never empty text, never throws)`.
2. `conversation preview shows placeholder, fills when provider emits`.
3. `DB bytes after migration: query sqlite_master → no decryptedBody column; SELECT * FROM messages → no field named decrypted_body`.
4. `search: type 'ab' rapidly → old scan cancelled (instrument cancel token); only last query's results shown; no plaintext row written to DB during search`.
5. Re-run **Task 1 `read_paths_char_test`** — update expectations to assert the placeholder widget appears (user-visible contract: same non-throwing, never-blank behavior as the pinned baseline).

- [ ] **Step 2: RED** → **Step 3: Implement** migration (v10 `m.dropColumn(messages, 'decryptedBody')`), widget, wiring, search debounce/cancel (own ephemeral results map).

- [ ] **Step 4: GREEN** + full suite + analyze 0.

- [ ] **Step 5: Device proof** — key-delay chat placeholder + filled chat + search typing → 3 captures → **STOP for PASS** → commit `[Offline P4] Placeholder UI + drop decrypted_body + cancellable search`.

---

### Task 10: Screen HTTP → infrastructure services

**Files:**
- Create: `lib/infrastructure/services/profile_update_service.dart` (multipart avatar/name — logic moved from `edit_profile_screen.dart`)
- Create: `lib/infrastructure/services/group_create_service.dart` (moved from `create_group_screen.dart`)
- Create: `lib/infrastructure/services/auth_onboarding_service.dart` (Google onboarding multipart — moved from `google_onboarding_screen.dart`)
- Create: `lib/infrastructure/services/link_preview_service.dart` (Dio fetch moved from `link_preview_card.dart`; widget renders from provider)
- Create: `lib/infrastructure/services/friend_query_service.dart` (PB list queries moved from `friends_provider.dart`)
- Create: `lib/infrastructure/services/media_gallery_service.dart` (PB list queries moved from `media_docs_screen.dart`)
- Modify: `lib/features/home/providers/friends_provider.dart`, `lib/features/media/screens/media_docs_screen.dart` (direct `pocketbaseClientProvider.pb` usage → providers over the new services; delete `package:pocketbase/` imports)
- Modify: the 4 original widget/screen files (call providers only; delete their `package:http`/`Dio` imports)
- Test: `test/offline/imports_after_move_test.dart`

**Interfaces:**
- Produces: Riverpod providers `profileUpdateServiceProvider`, `groupCreateServiceProvider`, `linkPreviewServiceProvider(String url) → Future<LinkPreview?>` etc.
- Consumes: existing `pocketbaseClientProvider`, `PocketBaseClient.pb`.

- [ ] **Step 1: Failing test** — for each of the 4 original files: `expect(src.contains("package:http"), isFalse)` / `"Dio"`; for `friends_provider.dart` and `media_docs_screen.dart`: `expect(src.contains("package:pocketbase/"), isFalse)` — all RED while imports remain.
- [ ] **Step 2: RED** → **Step 3: Move code verbatim** into services (guard 5: no behavior edits), rewire screens, providers registered where the other infrastructure providers live.
- [ ] **Step 4: GREEN** + full suite + analyze 0.
- [ ] **Step 5: STOP for PASS** (device: avatar upload, group create, link preview still work) → commit `[Offline P5] Screen HTTP behind services — profile/group/onboarding/link-preview`.

---

### Task 11: Import gate ON + offline matrix

**Files:**
- Modify: `test/grep_gates_test.dart` (gate 13 — whole `lib/` scan)
- Create: `docs/offline-test-matrix.md` (executed checklist with captures)

**Interfaces:**
- Consumes: Tasks 1–10 (gate turns on ONLY now — guard 4).

- [ ] **Step 0 (mechanical prep):** move `lib/core/utils/fcm_debug_helper.dart` →
  `lib/services/fcm_debug_helper.dart` (import updates) so every sanctioned
  integration file sits in an allowlisted path before the gate goes live.

- [ ] **Step 1: Failing gate test:**

```dart
  // Gate 13 (spec §12 + plan carve-outs): network SDKs live only in the
  // sanctioned integration paths — screens/features/data/domain/core(else)
  // stay network-free. Sanctioned: infrastructure (ingest/outbox/blobs),
  // services (fcm/presence/encryption/upload integrations), core/network
  // (the PB client), bootstrap (main + firebase_options).
  test('no network SDK imports outside sanctioned integration paths', () {
    const sanctioned = [
      'lib/infrastructure/',
      'lib/services/',
      'lib/core/network/',
      'lib/main.dart',
      'lib/firebase_options.dart',
    ];
    final banned = RegExp(
        r"package:http/|package:dio/|package:pocketbase/|"
        r"package:web_socket_channel/|package:firebase_|"
        r"package:connectivity_plus|"
        r"dart:io.*(HttpClient|WebSocket|Socket\b)");
    final hits = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final allowed = sanctioned.any((p) =>
          p.endsWith('/') ? f.path.startsWith(p) : f.path == p);
      if (allowed) continue;
      if (banned.hasMatch(f.readAsStringSync())) hits.add(f.path);
    }
    expect(hits, isEmpty, reason: 'network SDK outside sanctioned paths: $hits');
  });
```
  After Task 10 this should compile GREEN immediately. **Prove teeth:** temporarily
  add `import 'package:http/http.dart';` to a screen, watch gate 13 FAIL, remove —
  then run the full suite.
- [ ] **Step 2: RED if any leak remains** (Task 10 should make it green immediately — RED proves the gate has teeth: temporarily reintroduce a `package:http` import in a screen to watch it fail, then remove).
- [ ] **Step 3: GREEN + full suite + analyze 0.**
- [ ] **Step 4: Execute offline matrix** in `docs/offline-test-matrix.md` on emulator + (user's phone if attached), each row capture-verified:
  1. Airplane mode: home/chat/preview/search render from DB; send → row `queued`.
  2. **Kill mid-queue**: send 3 msgs offline, `adb shell am force-stop`, relaunch offline → 3 rows still `queued`, janitor reset any `sending`; reconnect → all send, one bubble each (no dups — verify against server list).
  3. **Long-gap reconnect**: airplane 10+ min (or clock-shift), messages accumulate from peer; reconnect → catch-up applies once; cursor no skips (compare DB count vs server count).
  4. Key-delay placeholder path (Task 7 capture) + terminal banner (Task 4 capture) re-verified.
  5. Media: download → airplane → cached blob views offline; delete files → placeholder → reconnect re-fetches.
- [ ] **Step 5: STOP for final PASS** → commit `[Offline P6] Import gate + offline test matrix`. Then dispatch the plan's final whole-branch review (executing-plans review package) before any finishing menu.

---

### Task 12: Fake repositories + USE_FAKES dev seam (spec §10, mock-build strategy)

**Files:**
- Create: `test/fakes/fake_message_repository.dart`
- Create: `lib/core/config/data_source.dart`
- Modify: `lib/main.dart` (conditional override)
- Test: `test/offline/use_fakes_boot_test.dart`

**Interfaces:**
- Produces: `FakeMessageRepository implements MessageRepository` (Map-backed); `const bool useFakes = bool.fromEnvironment('USE_FAKES')`; main wires `ProviderScope(overrides: useFakes ? [messageRepositoryProvider.overrideWithValue(FakeMessageRepository())] : const [])`.
- Consumes: `lib/domain/repositories/message_repository.dart` (existing abstract), Task 10's provider-only screens. Future screen work (chat restructure) builds against this.

- [ ] **Step 1: Failing test** — `use_fakes_boot_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fakes/fake_message_repository.dart';
import 'package:kuch_bhi/features/home/screens/home_screen.dart';
// …ProviderScope with pocketbaseClientProvider left DEFAULT (it throws by
// design) + messageRepositoryProvider overridden by the fake…
void main() {
  testWidgets('app screens read from FakeMessageRepository with NO PocketBase',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [messageRepositoryProvider.overrideWithValue(FakeMessageRepository())],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'default pocketbaseClientProvider throws — fake seam must avoid it');
  });
}
```
(If `HomeScreen` needs additional providers, override only those the error names —
the test proves the seam, not the whole app.)

- [ ] **Step 2: RED** (class missing / provider not overridable).

- [ ] **Step 3: Implement** `FakeMessageRepository`:
```dart
/// Map-backed fake for mock-build screen development (spec §10).
/// Screen-facing reads are implemented; the rest fail LOUD on purpose —
/// extend when the consuming screen needs them.
class FakeMessageRepository implements MessageRepository {
  final _conversations = <String, Conversation>{};
  final _messages = <String, List<Message>>{}; // conversationId → rows
  final _controller = StreamController<List<Message>>.broadcast();
  @override Stream<List<Message>> watchMessages(String conversationId) async* {
    yield _messages[conversationId] ?? const [];
    yield* _controller.stream; // emits on local sends
  }
  @override Stream<List<Conversation>> watchConversations() async* {
    yield _conversations.values.toList();
  }
  @override Future<void> sendMessage({required String conversationId,
      required String plaintext, String? replyToLocalId, String? replyPreview}) async {
    final m = Message(/* localId: generateOpId(), decryptedBody: plaintext, … */);
    (_messages[conversationId] ??= []).add(m);
    _controller.add(_messages[conversationId]!);
  }
  // …implement ONLY the reads the first fake-backed screen needs:
  // markConversationRead, watchPinnedMessages, getStarredMessages,
  // hasUsableKey(true), searchMessages (local contains filter).
  @override dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(
          'FakeMessageRepository: ${invocation.memberName} — extend as screens need it');
}
```
(`noSuchMethod` satisfies the remaining `MessageRepository` methods without 30
stubs — every unimplemented call fails loudly with its name. Wire
`useFakes`/overrides in `main.dart` behind `const bool useFakes =
bool.fromEnvironment('USE_FAKES');`.)

- [ ] **Step 4: GREEN** — boot test passes; full suite + analyze 0. Run the app
  once with `flutter run --dart-define=USE_FAKES=true` → home renders fake data
  with no network → capture `off_use_fakes_boot.png`.

- [ ] **Step 5: STOP for PASS** → commit `[Offline P6] FakeMessageRepository + USE_FAKES seam (mock-build strategy)`.

---

## File map (create/modify summary)

| File | Task | Responsibility |
|---|---|---|
| `lib/core/utils/op_id.dart` | 2 | 15-char client/server id |
| `lib/data/local/database/tables/outbox_table.dart` + dao | 2 | durable send queue schema |
| `lib/infrastructure/offline/outbox_worker.dart` | 3 | drain FSM, backoff, pause |
| `lib/features/chat/providers/outbox_status_provider.dart` | 4 | terminal state → UI |
| `lib/data/local/database/tables/media_blob_table.dart` + dao | 5 | blob metadata schema |
| `lib/infrastructure/media/media_blob_store.dart` | 5 | single blob entry, janitor, eviction |
| `lib/infrastructure/ingest/ingest_boundary.dart` | 6 | sole network→DB record writer |
| `lib/core/decrypt/decrypt_pass.dart` + `body_cache.dart` | 8 | crypto batches + LRU plaintext |
| `lib/features/chat/providers/message_body_provider.dart` | 8 | coalesced lazy body reads |
| `lib/features/chat/widgets/message_body_text.dart` | 9 | placeholder renderer |
| `lib/infrastructure/services/{profile_update,group_create,auth_onboarding,link_preview}_service.dart` | 10 | screens' network lives here |
| `test/offline/*` | 1–11 | char tests, FSM, boundary, decrypt, gate |
| `docs/offline-test-matrix.md` | 11 | executed offline proof |

**End state:** schemaVersion 10, suite ≥ current + ~50 tests, analyze 0, gate 13 green (sanctioned-path carve-outs ledgered), matrix executed, `USE_FAKES` dev seam live, spec §14 success criteria demonstrably met. Dependent parked plan (widget-gaps Tier-1 mascot) unblocks chat restructure AFTER this lands.
