/// P8 — KEYLESS SEALED OUTBOX (user ruling: "The outbox exists so that a
/// kill never loses a send... §3 forbids durable plaintext, but not durable
/// sealed text. Wrap the pending body with a device-local key held in secure
/// storage, so the outbox row survives a kill without plaintext at rest.
/// Re-encrypt to the group key when it arrives.").
///
/// THE BUG (residual of C1 / commit 6ab2d50): encrypt-at-enqueue covers the
/// key-present send, but when the conversation group key does NOT resolve at
/// enqueue time nothing is sealed — the row keeps the interim `__pending__`
/// marker and the plaintext lives ONLY in process memory (`bodyCache`). A
/// force-stop then destroys the only copy: the drain reads a cache miss and
/// defers forever, so the send is LOST.
///
/// THE FIX: the keyless enqueue wraps the body with a DEVICE-LOCAL key held
/// in secure storage (§11: keys in secure storage) and writes that SEALED
/// ciphertext + iv into the ordinary `encrypted_body`/`iv` columns under a
/// new `decrypt_state = 'device_sealed'`. The drain re-resolves the group
/// key first: on arrival it re-encrypts to the GROUP key and flips the row
/// to `ready` before the server create (C1 discipline); display unwraps
/// lazily on read through the same `bodyCache`/`messageBodyProvider`
/// machinery. WRITE PATHS ONLY — the outbox FSM stays {queued, sending,
/// sent, failed_terminal}.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart' show PocketBase;
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/decrypt/decrypt_pass.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/outbox_table.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/infrastructure/repositories/auth_repository_impl.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/encryption_service.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

import 'char_harness.dart';

const _jsonHeaders = {'content-type': 'application/json'};

// ─────────────────────────────────────────────────────────────────────
// P8 vocabulary — mirrors the production names the fix must introduce.
// (These literals are duplicated here ONLY while the suite is RED; the
// implementation owns them and the test imports those symbols at GREEN.)
// ─────────────────────────────────────────────────────────────────────

/// The `decrypt_state` a keyless enqueue writes. Distinct from
/// `key_missing` (group key absent, nothing local) because the sealed row's
/// body IS present — decryptable, just under the DEVICE key.
const kDeviceSealedState = 'device_sealed';

/// Secure-storage slot holding the device-local outbox key (§11: keys in
/// secure storage). Session-scoped: wiped with the session.
const kDeviceKeySlot = 'device_outbox_key';

/// `key_id` prefix for a device-sealed row, so a raw reader can tell which
/// key wrapped the ciphertext without touching secure storage.
const kDeviceKeyIdPrefix = 'device:';

http.Response _err(int status) => http.Response(
      jsonEncode({'message': 'scripted $status', 'status': status}),
      status,
      headers: _jsonHeaders,
    );

Map<String, dynamic> _recordJson(String id) => {
      'id': id,
      'collectionId': 'messages',
      'collectionName': 'messages',
      'created': '2026-10-07T10:00:00.000Z',
      'updated': '2026-10-07T10:00:00.000Z',
      'fields': <String, dynamic>{},
      'conversation_id': 'g1',
      'sender_id': 'u_test',
      'type': 'text',
      'encrypted_body': '',
      'iv': '',
      'reply_to_id': '',
      'reply_preview': '',
      'is_deleted_for_everyone': false,
      'is_deleted_for_me': false,
      'is_pinned': false,
      'is_starred': false,
      'status': 'sent',
      'media_id': '',
    };

/// Scripted client: SSE hangs (T1 rule), the message create succeeds,
/// everything else 404s. [onCreate] lets a test count creates and inspect
/// the payload the production path sent.
http.Client Function() _clientFactory(
    http.Response Function(http.Request req, int nthCreate) onCreate) {
  var creates = 0;
  return () => MockClient((req) async {
        if (req.url.path.startsWith('/api/realtime')) {
          return Completer<http.Response>().future;
        }
        if (req.method == 'POST' &&
            req.url.path.contains('/collections/messages/records')) {
          creates++;
          return onCreate(req, creates);
        }
        return _err(404);
      });
}

/// A structurally valid JWT — the file-backed kill proof builds its OWN
/// harness, and `sessionStillValid(...)` needs a parseable future `exp`
/// (same shape as char_harness's private `_fakeJwt`).
String _fakeJwt() {
  String enc(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m)));
  return '${enc(const <String, Object>{'alg': 'HS256', 'typ': 'JWT'}).toString()}.'
      '${enc(const <String, Object>{'exp': 4102444800}).toString()}.sig';
}

/// Every string value in every table — the sealed_preview_test sweep.
/// Proves no durable plaintext anywhere (spec §3).
Future<Set<String>> _allTextValues(AppDatabase db) async {
  final tables = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").get();
  final out = <String>{};
  for (final t in tables) {
    final name = t.read<String>('name');
    final rows = await db.customSelect('SELECT * FROM "$name"').get();
    for (final r in rows) {
      for (final v in r.data.values) {
        if (v is String) out.add(v);
      }
    }
  }
  return out;
}

/// THE KILL PROOF harness: a REAL FILE, reopenable. `charHarness()` is
/// built and discarded first for its one-time test-runtime prep
/// (connectivity channel mock + drift multi-instance warning suppression).
///
/// Deliberately SHAPE-COMPATIBLE with `CharHarness` (same `db`, `pbClient`,
/// `storage`, `encryption` field names) so [buildRepo] and the shared
/// seed helper can be reused verbatim — the kill proof must run the SAME
/// production code, not a re-implementation of it.
class FileHarness {
  FileHarness._(this.dir, this.db, this.pbClient, this.storage, this.encryption);
  final Directory dir;
  final AppDatabase db;
  final PocketBaseClient pbClient;
  final FakeSecureStorage storage;
  final EncryptionService encryption;

  Future<void> close() async {
    await db.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

Future<FileHarness> _fileHarness(
    http.Client Function()? clientFactory) async {
  final prep = charHarness(); // one-time runtime prep only
  await prep.close();

  final dir = await Directory.systemTemp.createTemp('p8_kill');
  final db = AppDatabase.forExecutor(NativeDatabase(File('${dir.path}/k.sqlite')));
  final pb = PocketBase('http://pocketbase.test',
      httpClientFactory: clientFactory ?? http.Client.new);
  pb.authStore.save(_fakeJwt(), null);
  final pbClient = PocketBaseClient.forTest(pb);
  final storage = FakeSecureStorage();
  final encryption = EncryptionService(storage, pbClient);
  return FileHarness._(dir, db, pbClient, storage, encryption);
}

/// Reopens the SAME FILE with a fresh AppDatabase + fresh encryption
/// service, sharing the same secure-storage fake (the device key is
/// durable — that is the whole point). This is "a new process start".
Future<FileHarness> _reopen(FileHarness old) async {
  await old.db.close();
  final db = AppDatabase.forExecutor(NativeDatabase(File('${old.dir.path}/k.sqlite')));
  final pb = PocketBase('http://pocketbase.test', httpClientFactory: http.Client.new);
  pb.authStore.save(_fakeJwt(), null);
  final pbClient = PocketBaseClient.forTest(pb);
  final encryption = EncryptionService(old.storage, pbClient);
  return FileHarness._(old.dir, db, pbClient, old.storage, encryption);
}

/// [seedConversationAndKey] over a file-backed harness — the shared helper
/// only takes a `CharHarness`, and the kill proof must seed the SAME way
/// production does (verbatim copy of its two upserts). Keyless only: this
/// is the only state the kill proof needs.
Future<void> _seedFileConversation(AppDatabase db) async {
  final at = DateTime.utc(2026, 1, 1);
  await db.conversationsDao.upsertConversation(
    ConversationsTableCompanion.insert(
      id: 'g1',
      type: 'group',
      createdById: 'u_test',
      createdAt: at,
      updatedAt: at,
    ),
  );
  await db.conversationsDao.upsertMember(
    ConversationMembersTableCompanion.insert(
      id: 'm1',
      conversationId: 'g1',
      userId: 'u_test',
      joinedAt: at,
    ),
  );
}

/// [buildRepo] over a file-backed harness.
MessageRepositoryImpl _fileRepo(FileHarness h) => MessageRepositoryImpl(
      pbClient: h.pbClient,
      db: h.db,
      storage: h.storage,
      encryption: h.encryption,
      mediaUploadService: MediaUploadService(h.pbClient, h.encryption),
    );

void main() {
  setUp(bodyCache.clear);

  // ── P8.1 keyless enqueue writes SEALED ciphertext, not `__pending__` ──
  test('P8.1: keyless enqueue seals the body under the device key — '
      'row is never `__pending__`, never plaintext, key lives in secure '
      'storage', () async {
    final h = charHarness(clientFactory: _clientFactory((req, nth) =>
        http.Response(jsonEncode(_recordJson('k$nth')), 200,
            headers: _jsonHeaders)));
    addTearDown(h.close);
    // NO group key at enqueue time — the keyless scenario.
    await seedConversationAndKey(h, withKey: false);
    final repo = buildRepo(h);
    await repo.outboxWorker.onAuthPaused(true); // park the drain kick

    await repo.sendMessage(conversationId: 'g1', plaintext: 'seal me now');

    final row = (await h.db.messagesDao.watchMessages('g1').first).single;
    expect(row.decryptState, kDeviceSealedState,
        reason: 'P8: the keyless enqueue marks the row device-sealed — the '
            'distinguishing decrypt_state that says "sealed under the '
            'device-local key"');
    expect(row.encryptedBody, isNot('__pending__'),
        reason: 'THE BUG: a keyless enqueue must never keep the interim '
            'marker — that is what made the plaintext memory-only');
    expect(row.encryptedBody, isNotEmpty);
    expect(row.iv, isNotEmpty);

    // Spec §3 sweep: no plaintext, and no interim marker, anywhere durable.
    final values = await _allTextValues(h.db);
    expect(values.where((v) => v.contains('seal me now')), isEmpty,
        reason: 'spec §3 — the body may never appear in any Drift column');
    expect(values.where((v) => v == '__pending__'), isEmpty,
        reason: 'spec §3 — the interim marker IS the bug shape; a keyless '
            'row must not carry it');

    // The device key lives in the EXISTING secure-storage mechanism (§11).
    final secure = await h.storage.readAll();
    expect(secure.containsKey(kDeviceKeySlot), isTrue,
        reason: 'the device-local key must be stored in secure storage — '
            'the app\'s own mechanism, no new dependency');
    expect(secure[kDeviceKeySlot], isNotEmpty);

    // key_id is self-describing: it names the device key, not a group key.
    expect(row.keyId, isNotNull);
    expect(row.keyId, startsWith(kDeviceKeyIdPrefix),
        reason: 'key_id carries the device: prefix so a raw reader can tell '
            'which key wrapped the row');
    expect(row.keyId, isNot(DecryptPass.fingerprintOf(fixtureGroupKey)));
  });

  // ── P8.2 KILL SURVIVAL (the user's exact case, over a real file) ───────
  test('P8.2: keyless enqueue → REAL process death (file closed) → '
      'relaunch (new AppDatabase, same file) → row still sealed, '
      'provider path unwraps it to the plaintext', () async {
    final h = await _fileHarness(_clientFactory((req, nth) =>
        http.Response(jsonEncode(_recordJson('k$nth')), 200,
            headers: _jsonHeaders)));
    addTearDown(h.close);
    await _seedFileConversation(h.db);
    final repo = _fileRepo(h);
    await repo.outboxWorker.onAuthPaused(true); // the kick never runs
    await repo.sendMessage(conversationId: 'g1', plaintext: 'kill survivor');

    final localId =
        (await h.db.messagesDao.watchMessages('g1').first).single.localId;
    expect(
        (await h.db.messagesDao.getMessageByLocalId(localId))!.decryptState,
        kDeviceSealedState);

    // ── PROCESS DEATH: every in-memory copy goes, the DB file stays ──
    bodyCache.clear();

    // ── RELAUNCH: a NEW AppDatabase instance over the SAME FILE ──
    final up = await _reopen(h);
    addTearDown(up.close);
    final revived = (await up.db.messagesDao.getMessageByLocalId(localId))!;
    expect(revived.decryptState, kDeviceSealedState,
        reason: 'kill-survival: the row keeps its sealed ciphertext');
    expect(revived.encryptedBody, isNot('__pending__'));
    expect(revived.encryptedBody, isNotEmpty);
    expect(revived.iv, isNotEmpty,
        reason: 'the iv survives with the ciphertext — nothing rewrote it');

    // No plaintext at rest after the relaunch either (spec §3).
    final values = await _allTextValues(up.db);
    expect(values.where((v) => v.contains('kill survivor')), isEmpty);

    // Display resolves through the EXISTING provider path: a cold cache
    // misses, the coalescer runs a DecryptPass, the device key unwraps the
    // body, the bubble renders the plaintext. No FSM field was touched.
    //
    // The relaunch builds a NEW repository over the REOPENED db — the old
    // one's DecryptPass still holds the closed handle, which is exactly the
    // "new process" shape (nothing survives a kill).
    final revivedRepo = _fileRepo(up);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(up.db),
      messageRepositoryProvider.overrideWithValue(revivedRepo),
    ]);
    addTearDown(container.dispose);
    expect(bodyCache.get(localId), isNull, reason: 'memory really was cold');
    final displayed =
        await container.read(messageBodyProvider(localId).future);
    expect(displayed, 'kill survivor',
        reason: 'P8: after kill+relaunch the row RENDERS — unwrapped on '
            'read, never lost, never blank');
    expect((await up.db.messagesDao.getMessageByLocalId(localId))!
        .decryptState, kDeviceSealedState,
        reason: 'the read is unwrap-only: the row stays sealed at rest '
            '(the group key has not arrived, so it cannot be ready)');
    expect(bodyCache.get(localId), 'kill survivor');
  });

  // ── P8.3 drain with the group key ARRIVING after relaunch ─────────────
  test('P8.3: drain with the group key arriving re-encrypts to the group '
      'key (decrypt_state → ready, key_id = group fingerprint) and sends '
      'once; the ack preserves the state', () async {
    final creates = <Map<String, dynamic>>[];
    final h = charHarness(clientFactory: _clientFactory((req, nth) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      creates.add(body);
      return http.Response(jsonEncode(_recordJson(body['id'] as String)), 200,
          headers: _jsonHeaders);
    }));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: false);
    var repo = buildRepo(h);
    await repo.outboxWorker.onAuthPaused(true);
    await repo.sendMessage(
        conversationId: 'g1', plaintext: 'late group key');
    final localId =
        (await h.db.messagesDao.watchMessages('g1').first).single.localId;
    expect(
        (await h.db.messagesDao.getMessageByLocalId(localId))!.decryptState,
        kDeviceSealedState,
        reason: 'P8.3 premise: the row STARTS device-sealed, so the '
            'sealed → ready transition below is the one under test');

    // The group key arrives AFTER the launch (peer sync / group-key fetch).
    h.storage.put('group_key_g1', base64.encode(fixtureGroupKey));

    // Relaunch — a fresh worker drains against the sealed row.
    repo.outboxWorker.dispose();
    repo = buildRepo(h);
    repo.outboxWorker.onAuthResumed();
    await repo.outboxWorker.drain();

    expect(creates, hasLength(1), reason: 'the create ran exactly once');
    final after = (await h.db.messagesDao.getMessageByLocalId(localId))!;
    expect(after.status, 'sent');
    expect(after.decryptState, 'ready',
        reason: 'P8: re-encrypt to the GROUP key flips the row to ready');
    expect(after.keyId, DecryptPass.fingerprintOf(fixtureGroupKey),
        reason: 'P8: key_id now names the group key, not the device key');
    expect(after.serverId, isNotNull);
    // The server received GROUP-key ciphertext — the ruling's "re-encrypt
    // to the group key when it arrives".
    expect(creates.single['encrypted_body'], after.encryptedBody);
    final plain = await h.encryption.decryptMessage(
        creates.single['encrypted_body'] as String,
        creates.single['iv'] as String,
        fixtureGroupKey);
    expect(plain, 'late group key',
        reason: 'the server payload decrypts under the GROUP key');
    // Drain FSM untouched (write-paths-only constraint).
    expect((await h.db.outboxDao.all()).single.state, OutboxState.sent);
    expect(await h.db.messagesDao.countForConversation('g1'), 1,
        reason: 'exactly one bubble — no ghost re-create');
  });

  // ── P8.4 drain with the group key STILL absent ────────────────────────
  test('P8.4: drain with the group key still absent defers WITHOUT losing '
      'the send (FSM untouched), then sends once the key arrives', () async {
    final creates = <Map<String, dynamic>>[];
    final h = charHarness(clientFactory: _clientFactory((req, nth) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      creates.add(body);
      return http.Response(jsonEncode(_recordJson(body['id'] as String)), 200,
          headers: _jsonHeaders);
    }));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: false);
    var repo = buildRepo(h);
    await repo.outboxWorker.onAuthPaused(true);
    await repo.sendMessage(conversationId: 'g1', plaintext: 'still keyless');
    final localId =
        (await h.db.messagesDao.watchMessages('g1').first).single.localId;

    // Process death first (the case that used to lose the message), then a
    // relaunch that drains while the group key is STILL absent.
    bodyCache.clear();
    repo.outboxWorker.dispose();
    repo = buildRepo(h);
    repo.outboxWorker.onAuthResumed();
    await repo.outboxWorker.drain();

    expect(creates, isEmpty,
        reason: 'no key means no ciphertext to send — nothing may ship');
    final op = (await h.db.outboxDao.all()).single;
    expect(op.state, OutboxState.queued,
        reason: 'DEVIATION from a literal "send plaintext now" reading: the '
            'E2E server contract has no plaintext mode, so the op waits '
            'durably instead — never terminal, never lost');
    expect(op.attempts, 0,
        reason: 'local defer leaves the FSM bookkeeping exactly as today '
            '(worker: deferred restores queued, no attempts bump)');
    final sealed = (await h.db.messagesDao.getMessageByLocalId(localId))!;
    expect(sealed.decryptState, kDeviceSealedState,
        reason: 'the sealed row survives — the ruling\'s whole point');
    expect(sealed.status, 'pending', reason: 'not failed, not sent: queued');

    // The key arrives → the next drain sends, with the correct plaintext.
    h.storage.put('group_key_g1', base64.encode(fixtureGroupKey));
    await repo.outboxWorker.drain();

    expect(creates, hasLength(1),
        reason: 'THE BUG FIXED: the deferred op still DELIVERS once the key '
            'lands — nothing was ever lost');
    final after = (await h.db.messagesDao.getMessageByLocalId(localId))!;
    expect(after.status, 'sent');
    expect(after.decryptState, 'ready');
    final plain = await h.encryption.decryptMessage(
        creates.single['encrypted_body'] as String,
        creates.single['iv'] as String,
        fixtureGroupKey);
    expect(plain, 'still keyless',
        reason: 'the server got the correct body, re-encrypted under the '
            'group key');
    final values = await _allTextValues(h.db);
    expect(values.where((v) => v.contains('still keyless')), isEmpty,
        reason: 'spec §3 — the body stays sealed at rest after the send');
  });

  // ── P8.5 logout wipe: sealed row + device key both go with the session ──
  test('P8.5: logout wipes the sealed row AND the device key — no '
      'post-logout unwrap is possible', () async {
    final h = charHarness(clientFactory: _clientFactory((req, nth) =>
        http.Response(jsonEncode(_recordJson('k$nth')), 200,
            headers: _jsonHeaders)));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: false);
    final repo = buildRepo(h);
    await repo.outboxWorker.onAuthPaused(true);
    await repo.sendMessage(conversationId: 'g1', plaintext: 'wipe me');
    final localId =
        (await h.db.messagesDao.watchMessages('g1').first).single.localId;
    expect(
        (await h.db.messagesDao.getMessageByLocalId(localId))!.decryptState,
        kDeviceSealedState);
    expect((await h.storage.readAll()).containsKey(kDeviceKeySlot), isTrue);

    // The REAL production sign-out (auth_repository_impl.signOut):
    // clearSession() (secure storage) + every Drift table wiped.
    final auth = AuthRepositoryImpl(
        pbClient: h.pbClient, db: h.db, storage: h.storage);
    await auth.signOut();

    final secure = await h.storage.readAll();
    expect(secure.containsKey(kDeviceKeySlot), isFalse,
        reason: 'the device-local key must not outlive the session — with '
            'it, sealed ciphertext would stay unwrappable forever');
    expect(await h.db.messagesDao.getMessageByLocalId(localId), isNull,
        reason: '§11 logout wipe: the sealed outbox row goes with the '
            'session too (it is an outbox row, ciphertext or not)');
    expect(await h.db.outboxDao.all(), isEmpty, reason: 'outbox wiped');
    // No plaintext anywhere (never was, still is not).
    final values = await _allTextValues(h.db);
    expect(values.where((v) => v.contains('wipe me')), isEmpty);
  });
}
