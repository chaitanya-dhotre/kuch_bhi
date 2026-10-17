/// FINAL FIX PASS — C1 encryption-at-enqueue (spec §5.2) + I1 production-txn pin.
///
/// Kill/bg durability of an OUTBOUND message. Ledgered defect (T2 forward
/// carry, matrix R2 device-proven): `sendMessage` stored the `__pending__`
/// marker plus plaintext ONLY in the in-memory body cache, so backgrounding
/// (`bodyCache.clear()`, lib/app.dart:69) or a process kill destroyed the only
/// copy → drain read `bodyCache.get == null` → `OpSendOutcome.deferred`
/// forever → permanent non-delivery.
///
/// Fix (spec §5.2 "Enqueue atomicity: message/blob row + outbox row and the
/// body encryption happen in one Drift transaction"): when the conversation
/// key resolves at enqueue, the row is written with REAL ciphertext + iv
/// inside the same transaction; the cache put remains for display only.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/decrypt/device_key_store.dart';
import 'package:kuch_bhi/data/local/database/tables/outbox_table.dart';
import 'package:kuch_bhi/infrastructure/offline/outbox_worker.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import 'char_harness.dart';

const _jsonHeaders = {'content-type': 'application/json'};

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

/// Scripted client: SSE hangs (T1 rule), message create succeeds, everything
/// else 404s. The create handler is [onCreate] so a test can count creates
/// and inspect the payload the production path sent.
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

void main() {
  setUp(bodyCache.clear);

  // ── C1 Test A (device R2 equivalent, unit level) ────────────────────────
  test('C1-A: enqueue writes real ciphertext → bg/kill cannot lose the message',
      () async {
    Map<String, dynamic>? createBody;
    final h = charHarness(clientFactory: _clientFactory((req, nth) {
      createBody = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode(_recordJson(createBody!['id'] as String)), 200,
          headers: _jsonHeaders);
    }));
    addTearDown(h.close);
    await seedConversationAndKey(h); // fixture group key resolves
    final repo = buildRepo(h);

    // Enqueue while the key IS available.
    //
    // The production `sendMessage` ends with an un-awaited worker kick. A
    // real process kill is exactly "that drain never runs", so it is parked
    // through the PRODUCTION auth-pause hook before the send and released
    // later on a freshly built worker via the production resume hook — the
    // drain under test is then a genuine fresh-start pass.
    await repo.outboxWorker.onAuthPaused(true);
    await repo.sendMessage(conversationId: 'g1', plaintext: 'survive me');

    final row = (await h.db.messagesDao.watchMessages('g1').first).single;
    // Spec §5.2: the row carries REAL ciphertext, never the interim marker.
    expect(row.encryptedBody, isNot('__pending__'),
        reason: 'spec §5.2 encryption-at-enqueue: ciphertext lands in the '
            'enqueue transaction while the key resolves');
    expect(row.encryptedBody, isNotEmpty);
    expect(row.iv, isNotEmpty);
    // Display contract (spec §5.1) — the cache put REMAINS for the bubble.
    expect(bodyCache.get(row.localId), 'survive me');

    // ── Simulated backgrounding (lib/app.dart:69) + process death ──
    // Every in-memory copy of the body is gone; the worker is rebuilt like
    // a fresh process start against the SAME Drift file.
    bodyCache.clear();
    repo.outboxWorker.dispose(); // the old process's worker is gone
    final worker = OutboxWorker(
      outbox: h.db.outboxDao,
      messages: h.db.messagesDao,
      settings: h.db.settingsDao,
      send: repo.sendOutboxOp,
    );
    addTearDown(worker.dispose);

    // Reconnect drain: no cache, no memory — ciphertext only.
    worker.onAuthResumed();
    await worker.drain();

    final op = (await h.db.outboxDao.all()).single;
    expect(op.state, OutboxState.sent,
        reason: 'R2 defect: no permanent defer once ciphertext is durable');
    final after = (await h.db.messagesDao.getMessageByLocalId(row.localId))!;
    expect(after.status, 'sent', reason: 'message delivered');
    expect(after.serverId, isNotNull);
    expect(createBody, isNotNull, reason: 'the server create ran');
    expect(createBody!['encrypted_body'], after.encryptedBody,
        reason: 'create carried the row ciphertext (no re-encrypt divergence)');
    expect(await h.db.messagesDao.countForConversation('g1'), 1,
        reason: 'exactly one bubble — no ghost re-create');
  });

  // ── C1 Test B (keyless enqueue → first encrypt persists BEFORE create) ──
  test('C1-B: keyless enqueue persists ciphertext to the row BEFORE create',
      () async {
    final creates = <Map<String, dynamic>>[];
    final h = charHarness(clientFactory: _clientFactory((req, nth) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      creates.add(body);
      return http.Response(jsonEncode(_recordJson(body['id'] as String)), 200,
          headers: _jsonHeaders);
    }));
    addTearDown(h.close);
    // NO key at enqueue time.
    await seedConversationAndKey(h, withKey: false);
    var repo = buildRepo(h);
    // Park the production kick (sendMessage ends with an un-awaited drain):
    // this scenario is "kill before the first drain".
    await repo.outboxWorker.onAuthPaused(true);

    await repo.sendMessage(conversationId: 'g1', plaintext: 'late key');

    final row = (await h.db.messagesDao.watchMessages('g1').first).single;
    expect(row.encryptedBody, isNot('__pending__'),
        reason: 'P8 (user ruling): a keyless enqueue seals the body under '
            'the DEVICE-LOCAL key, so the row never carries the interim '
            'marker — plaintext-only-in-memory was the kill-losing shape');
    expect(row.encryptedBody, isNotEmpty);
    expect(row.decryptState, kDeviceSealedState,
        reason: 'P8: the row declares which key wraps it (device, not group)');

    // Key arrives (peer sync / group-key fetch) BEFORE the drain. C:
    // write-through API — a raw storage.put after the memory load is
    // invisible to reads.
    await h.encryption.saveGroupKey('g1', fixtureGroupKey);

    // A fresh process (relaunch) — the worker is rebuilt. The sealed row
    // unwraps through the DEVICE key (secure storage survives the process),
    // so no session cache is needed. What this test pins is the PROMOTION
    // step: the group-key ciphertext must reach the ROW before the create,
    // so a death right after it cannot leave a device-sealed row behind.
    repo.outboxWorker.dispose();
    repo = buildRepo(h);
    repo.outboxWorker.onAuthResumed(); // release the parked pause
    await repo.outboxWorker.drain();

    expect(creates, hasLength(1), reason: 'the create ran');
    final after = (await h.db.messagesDao.getMessageByLocalId(row.localId))!;
    expect(after.status, 'sent');
    expect(after.encryptedBody, isNot('__pending__'),
        reason: 'ciphertext persisted to the row by the first successful '
            'encrypt — AFTER this point memory holds nothing exclusive');
    expect(after.iv, isNotEmpty);
    // The create payload carried ciphertext, not the marker.
    expect(creates.single['encrypted_body'], isNot('__pending__'));
    expect(creates.single['encrypted_body'], isNotEmpty);
    expect(creates.single['iv'], isNotEmpty);

    // After the first encrypt the cache holds nothing exclusive: clear it and
    // drain again from a fresh process. The op is already `sent`, so no new
    // create happens — the pin is that the ROW owns the ciphertext from the
    // persist onward (the pre-C1 code had no such point at all).
    bodyCache.clear();
    await repo.outboxWorker.drain();
    expect(creates, hasLength(1),
        reason: 'already-sent op is never re-created (no dup bubble)');
    expect(
        (await h.db.messagesDao.getMessageByLocalId(row.localId))!
            .encryptedBody,
        isNot('__pending__'),
        reason: 'the durable copy lives in the row, not in memory');
  });

  // ── C1 Test C (kill AFTER first-encrypt persist, BEFORE ack) ────────────
  test('C1-C: kill after ciphertext persist, before ack → fresh drain sends once',
      () async {
    final creates = <Map<String, dynamic>>[];
    Map<String, dynamic>? lastBody;
    final h = charHarness(clientFactory: _clientFactory((req, nth) {
      lastBody = jsonDecode(req.body) as Map<String, dynamic>;
      creates.add(lastBody!);
      return http.Response(jsonEncode(_recordJson(lastBody!['id'] as String)),
          200, headers: _jsonHeaders);
    }));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    var repo = buildRepo(h);

    // Park the production kick: the scenario is "kill BEFORE the ack txn",
    // so the enqueue must be the only thing this process does.
    await repo.outboxWorker.onAuthPaused(true);
    await repo.sendMessage(conversationId: 'g1', plaintext: 'kill window');
    final localId =
        (await h.db.messagesDao.watchMessages('g1').first).single.localId;

    // Pre-persist state: ciphertext is already durable in the row.
    final before =
        (await h.db.messagesDao.getMessageByLocalId(localId))!;
    expect(before.encryptedBody, isNot('__pending__'));

    // Simulate process death BEFORE the ack txn: wipe the cache and rebuild
    // the worker/repo (the op row is still `queued`).
    bodyCache.clear();
    expect((await h.db.outboxDao.all()).single.state, OutboxState.queued);
    repo.outboxWorker.dispose();
    repo = buildRepo(h);
    repo.outboxWorker.onAuthResumed();

    await repo.outboxWorker.drain();

    expect(creates, hasLength(1), reason: 'sends exactly once — no dup');
    final after = (await h.db.messagesDao.getMessageByLocalId(localId))!;
    expect(after.status, 'sent');
    expect(after.serverId, isNotNull);
    expect((await h.db.outboxDao.all()).single.state, OutboxState.sent);
    expect(await h.db.messagesDao.countForConversation('g1'), 1);
  });

  // ── I1: production-path enqueue-txn pin ────────────────────────────────
  //
  // RF1's atomicity proof writes BOTH rows inside a TEST-authored
  // transaction — that proves Drift rolls back, not that the PRODUCTION
  // enqueue is one transaction. This arms a seam fired inside the real
  // `sendMessage` txn (just before the outbox write) to THROW, then asserts
  // rollback through the actual code path.
  test('I1: PRODUCTION enqueue txn rolls back both rows when it throws', () async {
    final h = charHarness(clientFactory: _clientFactory((req, nth) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode(_recordJson(body['id'] as String)), 200,
          headers: _jsonHeaders);
    }));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);

    Object? thrown;
    try {
      MessageRepositoryImpl.debugBeforeOutboxEnqueue = () {
        throw StateError('simulated kill window (production txn)');
      };
      await repo.sendMessage(conversationId: 'g1', plaintext: 'rollback me');
    } catch (e) {
      thrown = e;
    } finally {
      MessageRepositoryImpl.debugBeforeOutboxEnqueue = null;
    }

    expect(thrown, isA<StateError>(),
        reason: 'the in-txn throw must propagate out of sendMessage');
    expect(await h.db.messagesDao.countForConversation('g1'), 0,
        reason: 'I1: the REAL enqueue txn rolled the message row back');
    expect(await h.db.outboxDao.all(), isEmpty,
        reason: 'I1: no ghost op — the outbox row never survived');

    // The pin that makes this a PRODUCTION proof: the throw is armed while
    // the repository is driving its own transaction. Nothing was written,
    // so a subsequent drain finds no work — the same invariant RF1 pinned
    // at the DAO level, now proven through `repo.sendMessage(...)`.
    await repo.outboxWorker.drain();
    expect(await h.db.messagesDao.countForConversation('g1'), 0,
        reason: 'no drain resurrected a rolled-back message');
    expect(await h.db.outboxDao.all(), isEmpty,
        reason: 'no drain created an op from a rolled-back enqueue');
  });
}
