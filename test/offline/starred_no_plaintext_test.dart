/// Security wave 1, audit §8.1: starring a message must never upload its
/// decrypted body, and the starred list must take bodies from the device
/// (bodyCache / messages table), never from the server record.
///
/// Drives the REAL repository against a MockClient that records every
/// PocketBase request.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';

import 'char_harness.dart';

const _secret = 'meet at 9, bring the keys';
const _serverPlaintext = 'SERVER-SIDE PLAINTEXT';

Map<String, dynamic> _starRecord(String id, String messageId) => {
      'id': id,
      'collectionId': 'c_star',
      'collectionName': 'starred_messages',
      'created': '2026-01-02 00:00:00.000Z',
      'updated': '2026-01-02 00:00:00.000Z',
      'user_id': 'u_test',
      'message_id': messageId,
      'conversation_id': 'g1',
      'sender_id': 'u_test',
      'message_preview': _serverPlaintext,
    };

Future<void> _seedLocal(
  CharHarness h,
  String localId,
  String serverId, {
  bool starred = false,
}) =>
    h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: localId,
      conversationId: 'g1',
      senderId: 'u_test',
      type: 'text',
      encryptedBody: 'ciphertext-b64',
      iv: '',
      serverId: Value(serverId),
      isStarred: Value(starred),
      decryptState: const Value('ready'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ));

void main() {
  setUp(bodyCache.clear);
  tearDown(bodyCache.clear);

  test('toggleStar uploads no message body (no message_preview field)',
      () async {
    final posted = <String>[];
    final client = MockClient((req) async {
      if (req.method == 'POST' && req.url.path.contains('starred_messages')) {
        posted.add(req.body);
        return http.Response(jsonEncode(_starRecord('st1', 'srv1')), 200);
      }
      return http.Response('{}', 404);
    });
    final h = charHarness(clientFactory: () => client);
    addTearDown(h.close);
    await seedConversationAndKey(h);
    await _seedLocal(h, 'loc1', 'srv1');
    bodyCache.put('loc1', _secret);

    await buildRepo(h).toggleStar('loc1');
    // The PB create is fire-and-forget; wait for it to land.
    for (var i = 0; i < 100 && posted.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(posted, hasLength(1), reason: 'star must still sync to PB');
    final body = jsonDecode(posted.single) as Map<String, dynamic>;
    expect(body.containsKey('message_preview'), isFalse);
    expect(posted.single.contains(_secret), isFalse,
        reason: 'decrypted plaintext must never leave the device');
    expect(body['message_id'], 'srv1');
  });

  test('getStarredMessages ignores server preview: local body or placeholder',
      () async {
    final client = MockClient((req) async {
      if (req.method == 'GET' && req.url.path.contains('starred_messages')) {
        return http.Response(
          jsonEncode({
            'page': 1,
            'perPage': 200,
            'totalItems': 2,
            'totalPages': 1,
            'items': [
              _starRecord('st1', 'srv1'),
              _starRecord('st2', 'srv_not_local'),
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    final h = charHarness(clientFactory: () => client);
    addTearDown(h.close);
    await seedConversationAndKey(h);
    await _seedLocal(h, 'loc1', 'srv1', starred: true);
    bodyCache.put('loc1', _secret);

    final out = await buildRepo(h).getStarredMessages('g1');

    expect(out, hasLength(2));
    final local = out.firstWhere((m) => m.serverId == 'srv1');
    expect(local.localId, 'loc1',
        reason: 'local id lets the card resolve the body on device');
    expect(local.decryptedBody, _secret);
    final remote = out.firstWhere((m) => m.serverId == 'srv_not_local');
    expect(remote.decryptedBody, isNull,
        reason: 'not local → placeholder, never the server copy');
    expect(out.any((m) => m.decryptedBody == _serverPlaintext), isFalse);
  });

  test('getStarredMessages offline lists the local starred rows', () async {
    final client = MockClient(
      (req) async => throw http.ClientException('network down'),
    );
    final h = charHarness(clientFactory: () => client);
    addTearDown(h.close);
    await seedConversationAndKey(h);
    await _seedLocal(h, 'loc1', 'srv1', starred: true);
    await _seedLocal(h, 'loc2', 'srv2');
    bodyCache.put('loc1', _secret);

    final out = await buildRepo(h).getStarredMessages('g1');

    expect(out.map((m) => m.localId), ['loc1']);
    expect(out.single.decryptedBody, _secret);
    expect(out.single.isStarred, isTrue);
  });
}
