/// 12.8 D6 (decision 12): `setStarred` writes every row on the phone first,
/// returns, then sends the server writes one at a time in the background:
/// star creates paced to at most 15 per 5 s, a 429 waits 5 s and retries up
/// to 3 times; unstar = list + delete per row, unpaced.
///
/// Drives the REAL repository against a MockClient; the pacing clock is the
/// repo's virtual clock seam (a sleep advances it, nothing really waits).
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import 'char_harness.dart';

const _secret = 'do not upload me';

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
    };

Future<void> _seed(
  CharHarness h,
  String localId, {
  String? serverId,
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

/// One recorded request: method, path, body and the virtual time it left.
typedef _Req = ({String method, String path, String body, DateTime at});

class _Server {
  _Server({this.refuse429 = 0});

  /// How many star creates answer 429 before the server accepts.
  int refuse429;
  final requests = <_Req>[];
  var now = DateTime.utc(2026, 1, 1);
  var _n = 0;

  late final client = MockClient((req) async {
    requests.add(
      (method: req.method, path: req.url.path, body: req.body, at: now),
    );
    if (!req.url.path.contains('starred_messages')) {
      return http.Response('{}', 404);
    }
    if (req.method == 'POST') {
      if (refuse429 > 0) {
        refuse429--;
        return http.Response(
          jsonEncode({'status': 429, 'message': 'Too Many Requests.'}),
          429,
        );
      }
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(_starRecord('st${_n++}', body['message_id'] as String)),
        200,
      );
    }
    if (req.method == 'GET') {
      final filter = req.url.queryParameters['filter'] ?? '';
      final id = RegExp(r'message_id="([^"]+)"').firstMatch(filter)?.group(1);
      return http.Response(
        jsonEncode({
          'page': 1,
          'perPage': 1,
          'totalItems': 1,
          'totalPages': 1,
          'items': [_starRecord('st_$id', id ?? '')],
        }),
        200,
      );
    }
    return http.Response('', 204);
  });

  List<_Req> get creates =>
      [for (final r in requests) if (r.method == 'POST') r];
}

Future<(CharHarness, MessageRepositoryImpl, _Server)> _setup(
  _Server server,
) async {
  final h = charHarness(clientFactory: () => server.client);
  addTearDown(h.close);
  await seedConversationAndKey(h);
  final repo = buildRepo(h)
    ..starClock = (() => server.now)
    ..starDelay = (d) async => server.now = server.now.add(d);
  return (h, repo, server);
}

void main() {
  setUp(bodyCache.clear);
  tearDown(bodyCache.clear);

  test('writes every row on the phone before returning, then the server',
      () async {
    final (h, repo, server) = await _setup(_Server());
    for (var i = 0; i < 3; i++) {
      await _seed(h, 'l$i', serverId: 's$i');
    }

    await repo.setStarred(['l0', 'l1', 'l2'], true);
    for (var i = 0; i < 3; i++) {
      final row = await h.db.messagesDao.getMessageByLocalId('l$i');
      expect(row!.isStarred, isTrue, reason: 'phone first, row l$i');
    }
    await repo.starSendsDone;
    expect(server.creates, hasLength(3));
  });

  test('30 stars: never more than 15 creates in any 5 s window', () async {
    final (h, repo, server) = await _setup(_Server());
    final ids = [for (var i = 0; i < 30; i++) 'l$i'];
    for (var i = 0; i < 30; i++) {
      await _seed(h, 'l$i', serverId: 's$i');
    }

    await repo.setStarred(ids, true);
    await repo.starSendsDone;

    final times = [for (final r in server.creates) r.at];
    expect(times, hasLength(30));
    for (final start in times) {
      final inWindow = times
          .where((t) =>
              !t.isBefore(start) &&
              t.isBefore(start.add(const Duration(seconds: 5))))
          .length;
      expect(inWindow, lessThanOrEqualTo(15), reason: 'window at $start');
    }
    expect(
      [for (final r in server.creates) jsonDecode(r.body)['message_id']],
      unorderedEquals([for (var i = 0; i < 30; i++) 's$i']),
      reason: 'each row once',
    );
  });

  test('a 429 waits 5 s and retries the same row', () async {
    final (h, repo, server) = await _setup(_Server(refuse429: 2));
    await _seed(h, 'l0', serverId: 's0');

    await repo.setStarred(['l0'], true);
    await repo.starSendsDone;

    final c = server.creates;
    expect(c, hasLength(3), reason: 'two refused + one accepted');
    expect(c[1].at.difference(c[0].at), const Duration(seconds: 5));
    expect(c[2].at.difference(c[1].at), const Duration(seconds: 5));
    for (final r in c) {
      expect(jsonDecode(r.body)['message_id'], 's0');
    }
  });

  test('gives up on a row after 3 retries and moves on', () async {
    final (h, repo, server) = await _setup(_Server(refuse429: 4));
    await _seed(h, 'l0', serverId: 's0');
    await _seed(h, 'l1', serverId: 's1');

    await repo.setStarred(['l0', 'l1'], true);
    await repo.starSendsDone;

    final ids = [
      for (final r in server.creates) jsonDecode(r.body)['message_id'],
    ];
    expect(ids, ['s0', 's0', 's0', 's0', 's1'],
        reason: '1 try + 3 retries for s0, then s1 goes through');
    final row = await h.db.messagesDao.getMessageByLocalId('l0');
    expect(row!.isStarred, isTrue, reason: 'the phone keeps the star');
  });

  test('unstar = list + delete per row, unpaced', () async {
    final (h, repo, server) = await _setup(_Server());
    final ids = [for (var i = 0; i < 20; i++) 'l$i'];
    for (var i = 0; i < 20; i++) {
      await _seed(h, 'l$i', serverId: 's$i', starred: true);
    }

    await repo.setStarred(ids, false);
    for (final id in ids) {
      final row = await h.db.messagesDao.getMessageByLocalId(id);
      expect(row!.isStarred, isFalse);
    }
    await repo.starSendsDone;

    final star = [
      for (final r in server.requests)
        if (r.path.contains('starred_messages')) r,
    ];
    expect(star.where((r) => r.method == 'GET'), hasLength(20));
    expect(star.where((r) => r.method == 'DELETE'), hasLength(20));
    expect(star.where((r) => r.method == 'POST'), isEmpty);
    expect(star.map((r) => r.at).toSet(), hasLength(1),
        reason: 'unstar never waits');
  });

  test('rows without a server id are phone-only; rows already in the '
      'target state are untouched', () async {
    final (h, repo, server) = await _setup(_Server());
    await _seed(h, 'unsent');
    await _seed(h, 'already', serverId: 's_already', starred: true);
    await _seed(h, 'plain', serverId: 's_plain');
    final before = await h.db.messagesDao.getMessageByLocalId('already');

    await repo.setStarred(['unsent', 'already', 'plain'], true);
    await repo.starSendsDone;

    expect((await h.db.messagesDao.getMessageByLocalId('unsent'))!.isStarred,
        isTrue);
    final after = await h.db.messagesDao.getMessageByLocalId('already');
    expect(after!.updatedAt, before!.updatedAt, reason: 'untouched');
    expect(
      [for (final r in server.creates) jsonDecode(r.body)['message_id']],
      ['s_plain'],
      reason: 'no request for the unsent row or the already-starred one',
    );
  });

  test('request bodies carry ids only, never the message text', () async {
    final (h, repo, server) = await _setup(_Server());
    await _seed(h, 'l0', serverId: 's0');
    bodyCache.put('l0', _secret);

    await repo.setStarred(['l0'], true);
    await repo.starSendsDone;

    final body = jsonDecode(server.creates.single.body) as Map<String, dynamic>;
    expect(body.keys.toSet(),
        {'user_id', 'message_id', 'conversation_id', 'sender_id'});
    expect(server.creates.single.body.contains(_secret), isFalse);
  });
}
