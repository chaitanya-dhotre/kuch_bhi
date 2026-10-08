import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:kuch_bhi/core/utils/op_id.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/outbox_table.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:pocketbase/pocketbase.dart' show ClientException;

import 'char_harness.dart';

const _jsonHeaders = {'content-type': 'application/json'};

/// The EXACT duplicate-create error shape PocketBase returns, pinned by
/// Task 1 against the live server (docs/offline-phase0-verification.md §(c)2):
/// `{"data":{"<field>":{"code":"validation_not_unique",...}}, ...,"status":400}`.
String _dupBody(String field) => jsonEncode({
      'data': {
        field: {'code': 'validation_not_unique', 'message': 'Value must be unique.'},
      },
      'message': 'Failed to create record.',
      'status': 400,
    });

Map<String, dynamic> _recordJson({
  required String id,
  required String senderId,
  required String conversationId,
}) =>
    {
      'id': id,
      'collectionId': 'messages',
      'collectionName': 'messages',
      'created': '2026-10-07T10:00:00.000Z',
      'updated': '2026-10-07T10:00:00.000Z',
      'fields': <String, dynamic>{},
      'conversation_id': conversationId,
      'sender_id': senderId,
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

String _listEnvelope(Map<String, dynamic> record) => jsonEncode({
      'page': 1,
      'perPage': 40,
      'totalItems': 1,
      'totalPages': 1,
      'items': [record],
    });

String _emptyList() => jsonEncode({
      'page': 1,
      'perPage': 40,
      'totalItems': 0,
      'totalPages': 0,
      'items': <dynamic>[],
    });

http.Response _notFound() => http.Response(
      jsonEncode({
        'data': <String, dynamic>{},
        'message': 'Not found.',
        'status': 404,
      }),
      404,
      headers: _jsonHeaders,
    );

/// Seeds one message row + its queued outbox op in a single transaction —
/// the local state a completed `sendMessage` enqueue produces.
Future<void> _seedOp(
  AppDatabase db, {
  required String localId,
  required String opId,
  required int seq,
}) =>
    db.transaction(() async {
      await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId: localId,
        conversationId: 'g1',
        senderId: 'u_test',
        type: 'text',
        encryptedBody: 'x',
        iv: '',
        // T9: no plaintext column — decrypt_state defaults 'ready' so the
        // row stays visible / out of the repair query (same protection the
        // old decryptedBody seed gave: never a getUndecryptableRows
        // candidate that would DELETE group_key_g1 mid-test).
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      await db.outboxDao.enqueue(OutboxTableCompanion.insert(
        opId: opId,
        kind: 'text_send',
        ref: localId,
        conversationId: 'g1',
        seq: seq,
        createdAt: DateTime.now(),
      ));
    });

/// Drives a real pocketbase `create` against the scripted client and
/// returns the thrown [ClientException] (real SDK error surface).
Future<ClientException> _createThrows(CharHarness h) async {
  try {
    await h.pbClient.pb.collection('messages').create(body: {
      'conversation_id': 'g1',
      'sender_id': 'u_test',
      'type': 'text',
      'encrypted_body': 'x',
      'iv': 'y',
    });
  } on ClientException catch (e) {
    return e;
  }
  fail('expected scripted create to throw ClientException');
}

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
          type: 'text', encryptedBody: 'x', iv: '',
          createdAt: DateTime.now(), updatedAt: DateTime.now(),
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

    // ignore: unused_local_variable — intentionally never awaited
    final send = repo.sendMessage(conversationId: 'g1', plaintext: 'queued msg');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final rows = await h.db.messagesDao.watchMessages('g1').first;
    expect(rows, hasLength(1));
    expect(rows.first.status, 'pending');
    expect(bodyCache.get(rows.first.localId), 'queued msg',
        reason: 'T9: own-sent plaintext lives in the session cache '
            '(enqueue put — spec §5.1), not a DB column');
    expect((await h.db.outboxDao.all()).map((r) => r.kind), ['text_send'],
        reason: 'outbox row exists before any network I/O');
    // `send` intentionally never awaited
  });

  test('duplicate-id counts as success ONLY when the error field is id', () async {
    // Scripted create retry: PB returns 400 validation_not_unique on FIELD id
    // → treated as already-sent (then ownership GET verifies, below).
    var dupField = 'id';
    final h = charHarness(clientFactory: () => MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future; // SSE hangs (Task 1 rule)
      }
      if (req.method == 'POST' &&
          req.url.path.contains('/collections/messages/records')) {
        return http.Response(_dupBody(dupField), 400, headers: _jsonHeaders);
      }
      if (req.method == 'GET' &&
          req.url.path.contains('/collections/messages/records/')) {
        // Ownership GET: the record at this id is ours.
        return http.Response(
          jsonEncode(_recordJson(
            id: req.url.path.split('/').last,
            senderId: 'u_test',
            conversationId: 'g1',
          )),
          200,
          headers: _jsonHeaders,
        );
      }
      return _notFound();
    }));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);

    // ── FIELD id → dup → already-sent (ownership verified) ──────
    final opA = generateOpId();
    await _seedOp(h.db, localId: 'l_dup_id', opId: opA, seq: 1);
    final errId = await _createThrows(h);
    expect(isDuplicateIdError(errId), isTrue,
        reason: '400 validation_not_unique on FIELD id = duplicate send');
    expect(
      await repo.resolveDuplicateSend(
          opId: opA, senderId: 'u_test', conversationId: 'g1'),
      isTrue,
      reason: 'ownership GET confirms the record is ours → success',
    );
    expect((await h.db.outboxDao.byId(opA))!.state, OutboxState.sent);
    final acked = await h.db.messagesDao.getMessageByLocalId('l_dup_id');
    expect(acked!.status, 'sent');
    expect(acked.serverId, opA);
    expect(await h.db.messagesDao.countForConversation('g1'), 1,
        reason: 'already-sent must not re-create a second local row');

    // ── FIELD iv → NOT a duplicate send → NOT success ───────────
    // Scripted 400 validation_not_unique on a DIFFERENT field (e.g. 'iv'):
    // an unrelated unique-constraint failure must never count as delivered.
    dupField = 'iv';
    final opB = generateOpId();
    await _seedOp(h.db, localId: 'l_dup_iv', opId: opB, seq: 2);
    final errIv = await _createThrows(h);
    expect(isDuplicateIdError(errIv), isFalse,
        reason: 'unique-constraint failure on a non-id field is not success');
    // Dup path not taken → nothing acked, op left for the error-class
    // mapping (Task 3) to queue/fail — it can never be silently 'sent'.
    expect((await h.db.outboxDao.byId(opB))!.state, OutboxState.queued);
    final notAcked = await h.db.messagesDao.getMessageByLocalId('l_dup_iv');
    expect(notAcked!.serverId, isNull);
    expect(notAcked.status, 'pending');
    expect(await h.db.messagesDao.countForConversation('g1'), 2,
        reason: 'still exactly one row per message — no ghost re-create');
  });

  test('triple delivery: drain-ack + SSE echo + timeout-retry → exactly one row', () async {
    // ═══ Paths 1+2: create→200→drain-ack, then server echo ═══
    var listServed = false;
    final echoLanded = Completer<void>();
    late final String echoId;
    final h1 = charHarness(clientFactory: () => MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future; // SSE hangs (Task 1 rule)
      }
      final path = req.url.path;
      if (req.method == 'POST' &&
          path.contains('/collections/messages/records')) {
        // 1) create with id=opId → 200
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(_recordJson(
            id: body['id'] as String,
            senderId: 'u_test',
            conversationId: 'g1',
          )),
          200,
          headers: _jsonHeaders,
        );
      }
      if (req.method == 'GET' && path.endsWith('/records')) {
        if (!listServed) {
          // 2) echo: the fetch returns the SAME record id back.
          // (_listEnvelope already json-encodes.)
          listServed = true;
          return http.Response(
            _listEnvelope(_recordJson(
              id: echoId,
              senderId: 'u_test',
              conversationId: 'g1',
            )),
            200,
            headers: _jsonHeaders,
          );
        }
        // Follow-up sync request ⇒ the cache batch already committed.
        if (!echoLanded.isCompleted) echoLanded.complete();
        return http.Response(_emptyList(), 200, headers: _jsonHeaders);
      }
      if (!listServed) return _notFound();
      // Any other request after the echo list ⇒ batch already committed.
      if (!echoLanded.isCompleted) echoLanded.complete();
      return _notFound();
    }));
    echoId = generateOpId();
    addTearDown(h1.close);
    await seedConversationAndKey(h1);
    final repo1 = buildRepo(h1);
    await _seedOp(h1.db, localId: 'l_echo', opId: echoId, seq: 1);

    // 1) create with id=opId → 200 → ack path
    final created = await h1.pbClient.pb.collection('messages').create(body: {
      'id': echoId,
      'conversation_id': 'g1',
      'sender_id': 'u_test',
      'type': 'text',
      'encrypted_body': '',
      'iv': '',
    });
    expect(created.id, echoId,
        reason: 'client-generated 15-char op id accepted as server record id');
    await repo1.handleDrainAck(
      echoId,
      serverId: created.id,
      senderId: 'u_test',
      conversationId: 'g1',
    );
    var rows = await h1.db.messagesDao.watchMessages('g1').first;
    expect(rows, hasLength(1));
    expect(rows.first.status, 'sent');
    expect((await h1.db.outboxDao.byId(echoId))!.state, OutboxState.sent);

    // 2) SSE/fetch echo of the same record id → idempotent cache write.
    final warm = await repo1.watchMessages('g1').first;
    expect(warm, hasLength(1), reason: 'warm open serves the acked row');
    await echoLanded.future; // cache batch for the echo has committed
    rows = await h1.db.messagesDao.watchMessages('g1').first;
    expect(rows, hasLength(1),
        reason: 'echo of the same record id must not create a second row');
    expect(rows.first.serverId, echoId);

    // ═══ Path 3a: timeout-retry → dup(id) → ownership OURS → success ═══
    Future<MessageRepositoryImpl> harnessWith({
      required String ownership, // 'ours' | '404' | 'foreign'
    }) async {
      final h = charHarness(clientFactory: () => MockClient((req) async {
        if (req.url.path.startsWith('/api/realtime')) {
          return Completer<http.Response>().future;
        }
        final path = req.url.path;
        if (req.method == 'POST' &&
            path.contains('/collections/messages/records')) {
          // Timeout-retry: the record already reached the server.
          return http.Response(_dupBody('id'), 400, headers: _jsonHeaders);
        }
        if (req.method == 'GET' &&
            path.contains('/collections/messages/records/')) {
          final id = path.split('/').last;
          if (ownership == '404' || ownership == '403') return _notFound();
          return http.Response(
            jsonEncode(_recordJson(
              id: id,
              senderId: ownership == 'ours' ? 'u_test' : 'u_foreign',
              conversationId: 'g1',
            )),
            200,
            headers: _jsonHeaders,
          );
        }
        return _notFound();
      }));
      addTearDown(h.close);
      await seedConversationAndKey(h);
      return buildRepo(h);
    }

    // 3a) ownership record with OUR sender_id+conversation_id → success,
    //     no re-create.
    final repoA = await harnessWith(ownership: 'ours');
    // The harness DAO is reachable via repoA.db — reseed through the repo's db.
    final opOwn = generateOpId();
    await _seedOp(repoA.db, localId: 'l_own', opId: opOwn, seq: 1);
    final errA = await _createThrowsFor(repoA);
    expect(isDuplicateIdError(errA), isTrue);
    expect(
      await repoA.resolveDuplicateSend(
          opId: opOwn, senderId: 'u_test', conversationId: 'g1'),
      isTrue,
      reason: 'ownership verified → already-sent (never a second create)',
    );
    expect((await repoA.db.outboxDao.byId(opOwn))!.state, OutboxState.sent);
    final rowsA = await repoA.db.messagesDao.watchMessages('g1').first;
    expect(rowsA, hasLength(1));
    expect(rowsA.first.status, 'sent');
    expect(await repoA.db.messagesDao.countForConversation('g1'), 1);

    // 3b) ownership GET 404 (foreign record hidden by view rule) →
    //     failedTerminal + errorClass 'id_collision' — never retried,
    //     never counted as success.
    final repoB = await harnessWith(ownership: '404');
    final op404 = generateOpId();
    await _seedOp(repoB.db, localId: 'l_404', opId: op404, seq: 1);
    final errB = await _createThrowsFor(repoB);
    expect(isDuplicateIdError(errB), isTrue);
    expect(
      await repoB.resolveDuplicateSend(
          opId: op404, senderId: 'u_test', conversationId: 'g1'),
      isFalse,
      reason: '404 ownership GET = foreign/hidden record, NOT success',
    );
    final opRowB = await repoB.db.outboxDao.byId(op404);
    expect(opRowB!.state, OutboxState.failedTerminal);
    expect(opRowB.errorClass, 'id_collision');
    expect(opRowB.lastError, isNotNull);
    final rowsB = await repoB.db.messagesDao.watchMessages('g1').first;
    expect(rowsB, hasLength(1));
    expect(rowsB.first.status, 'pending');
    expect(rowsB.first.serverId, isNull);
    expect(await repoB.db.messagesDao.countForConversation('g1'), 1);

    // 3c) record exists but sender_id/conversation mismatch → same terminal.
    final repoC = await harnessWith(ownership: 'foreign');
    final opForeign = generateOpId();
    await _seedOp(repoC.db, localId: 'l_foreign', opId: opForeign, seq: 1);
    final errC = await _createThrowsFor(repoC);
    expect(isDuplicateIdError(errC), isTrue);
    expect(
      await repoC.resolveDuplicateSend(
          opId: opForeign, senderId: 'u_test', conversationId: 'g1'),
      isFalse,
      reason: 'mismatched ownership = foreign record, NOT success',
    );
    final opRowC = await repoC.db.outboxDao.byId(opForeign);
    expect(opRowC!.state, OutboxState.failedTerminal);
    expect(opRowC.errorClass, 'id_collision');
    final rowsC = await repoC.db.messagesDao.watchMessages('g1').first;
    expect(rowsC, hasLength(1));
    expect(rowsC.first.serverId, isNull);
    expect(await repoC.db.messagesDao.countForConversation('g1'), 1);
  });

  test('FakeSecureStorage: non-overridden members fail loudly (never real storage)', () {
    final h = charHarness();
    addTearDown(h.close);
    // saveAuthToken is one of the 17 members the fake does NOT override —
    // it must hit noSuchMethod with UnimplementedError, not the
    // FlutterSecureStorage platform channel (MissingPluginException).
    expect(
      () => h.storage.saveAuthToken('x'),
      throwsA(isA<UnimplementedError>()
          .having((e) => e.message, 'message', contains('FakeSecureStorage'))),
    );
  });
}

/// Like [_createThrows] but against a repo-built harness (repo carries the db).
Future<ClientException> _createThrowsFor(MessageRepositoryImpl repo) async {
  try {
    await repo.pbClient.pb.collection('messages').create(body: {
      'conversation_id': 'g1',
      'sender_id': 'u_test',
      'type': 'text',
      'encrypted_body': 'x',
      'iv': 'y',
    });
  } on ClientException catch (e) {
    return e;
  }
  fail('expected scripted create to throw ClientException');
}
