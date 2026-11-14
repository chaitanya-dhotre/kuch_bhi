/// Rejoin spec (docs/design/pages/group-rejoin-history.md) gates 2–3: the
/// repo's chat stream, before the current join, shows only rows this
/// account's keys open (H1), and never anything to a brand-new joiner.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';

import 'char_harness.dart';

final _t0 = DateTime.utc(2026, 7, 1);
final _t1 = DateTime.utc(2026, 7, 2);
final _join = DateTime.utc(2026, 7, 3); // T2: current member row
final _t3 = DateTime.utc(2026, 7, 4);

/// Offline-ish server: every list is empty, realtime never answers.
final _server = MockClient((req) async {
  if (req.url.path.startsWith('/api/realtime')) {
    return Completer<http.Response>().future;
  }
  return http.Response(
      jsonEncode({
        'page': 1,
        'perPage': 200,
        'totalItems': 0,
        'totalPages': 1,
        'items': <Object>[],
      }),
      200,
      headers: {'content-type': 'application/json'});
});

Future<CharHarness> _harness() async {
  final h = charHarness(clientFactory: () => _server);
  addTearDown(h.close);
  await seedConversationAndKey(h);
  // Re-add: the member row now carries the re-add time.
  await h.db.conversationsDao.upsertMember(
    ConversationMembersTableCompanion.insert(
      id: 'm1',
      conversationId: 'g1',
      userId: 'u_test',
      joinedAt: _join,
    ),
  );
  return h;
}

Future<void> _row(CharHarness h, String id, DateTime at, String type,
        String state) =>
    h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'l_$id',
      serverId: Value(id),
      conversationId: 'g1',
      senderId: 'u_peer',
      type: type,
      encryptedBody: 'c',
      iv: 'i',
      status: const Value('delivered'),
      decryptState: Value(state),
      createdAt: at,
      updatedAt: at,
    ));

Future<List<String?>> _visible(CharHarness h) async =>
    (await buildRepo(h).watchMessages('g1').first)
        .map((m) => m.serverId)
        .toList();

void main() {
  test('gate 2: re-joiner sees first-stint rows that open, not gap rows',
      () async {
    final h = await _harness();
    await _row(h, 't0text', _t0, 'text', 'ready');
    await _row(h, 't0img', _t0.add(const Duration(minutes: 1)), 'image',
        'ready');
    await _row(h, 't1text', _t1, 'text', 'key_missing');
    await _row(h, 't1img', _t1, 'image', 'key_missing');
    await _row(h, 't1sys', _t1, 'system', 'key_missing');
    await _row(h, 't3text', _t3, 'text', 'ready');

    final ids = await _visible(h);
    expect(ids.toSet(), {'t0text', 't0img', 't3text'});
    // In time order, whichever direction the stream sorts.
    final asc = ['t0text', 't0img', 't3text'];
    expect(ids, anyOf(equals(asc), equals(asc.reversed.toList())));
  });

  test('gate 3: a new joiner sees nothing from before the join', () async {
    final h = await _harness();
    var i = 0;
    for (final state in ['key_missing', 'pending']) {
      for (final type in ['text', 'image', 'voice', 'system']) {
        await _row(h, 'pre${i++}', _t1, type, state);
      }
    }
    await _row(h, 'postText', _t3, 'text', 'ready');
    await _row(h, 'postImg', _t3, 'image', 'key_missing');
    await _row(h, 'postGap', _t3, 'text', 'key_missing');

    expect((await _visible(h)).toSet(), {'postText', 'postImg'},
        reason: 'pre-join all hidden; post-join rules unchanged');
  });

  test('join-bubble guard ignores the first stint\'s "X joined" line',
      () async {
    final h = await _harness();
    await _row(h, 'oldJoin', _t0, 'system', 'ready');
    // Sent by me, the re-joiner.
    await (h.db.update(h.db.messagesTable)
          ..where((t) => t.localId.equals('l_oldJoin')))
        .write(const MessagesTableCompanion(senderId: Value('u_test')));
    bodyCache.put('l_oldJoin', 'Avium joined the group');

    final dao = h.db.messagesDao;
    expect(await dao.findSystemMessage('g1', 'u_test', 'Avium joined the group'),
        isNotNull);
    expect(
        await dao.findSystemMessage('g1', 'u_test', 'Avium joined the group',
            since: _join),
        isNull,
        reason: 'a re-add must emit a new joined line');
  });
  // Device check 2026-11-14: "X left the group" never reached the others —
  // it was posted after the member row was gone, which the create rule
  // refuses. It must be emitted while still a member.
  test('leaveGroup emits "left" before deleting the member row', () async {
    late CharHarness h;
    var deleted = false;
    var leftLineAtDelete = false;
    final json = {'content-type': 'application/json'};
    final server = MockClient((req) async {
      final path = req.url.path;
      if (path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (req.method == 'DELETE' &&
          path.contains('/conversation_members/records/')) {
        leftLineAtDelete = await h.db.messagesDao
                .findSystemMessage('g1', 'u_test', 'u_test left the group') !=
            null;
        deleted = true;
        return http.Response('', 204);
      }
      // The member row exists until the delete; afterwards the group is
      // empty, so the key rotation returns at once.
      final items = path.endsWith('/conversation_members/records') && !deleted
          ? [
              {
                'id': 'm1',
                'collectionId': 'c',
                'collectionName': 'conversation_members',
                'created': '2026-07-05 10:00:00.000Z',
                'updated': '2026-07-05 10:00:00.000Z',
              }
            ]
          : <Object>[];
      return http.Response(
          jsonEncode({
            'page': 1,
            'perPage': 1,
            'totalItems': items.length,
            'totalPages': 1,
            'items': items,
          }),
          200,
          headers: json);
    });
    h = charHarness(clientFactory: () => server);
    addTearDown(h.close);
    await seedConversationAndKey(h);

    await buildRepo(h).leaveGroup('g1');
    expect(deleted, isTrue);
    expect(leftLineAtDelete, isTrue,
        reason: 'the "left" line is sent while still a member');
  });
}
