import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';

import 'char_harness.dart';

/// former-member-history C1: after a wipe, a group this account left or was
/// removed from comes back as a read-only `left` chat from its
/// `former_members` record. Chats with a local row are never touched.

const _conv = {
  'id': 'g1',
  'collectionId': 'conv_cid',
  'collectionName': 'conversations',
  'created': '2026-10-01T10:00:00.000Z',
  'updated': '2026-10-01T10:00:00.000Z',
  'type': 'group',
  'name': 'Former test',
  'created_by': 'u_admin',
  'last_message_at': '2026-11-20T10:00:00.000Z',
};

Map<String, dynamic> _former({String reason = 'removed'}) => {
  'id': 'fm1',
  'collectionId': 'fm_cid',
  'collectionName': 'former_members',
  'created': '2026-11-16T10:00:00.000Z',
  'updated': '2026-11-16T10:00:00.000Z',
  'conversation_id': 'g1',
  'user_id': 'u_test',
  'joined_at': '2026-10-02T10:00:00.000Z',
  'history_until': '2026-11-16T10:00:00.000Z',
  'reason': reason,
  'expand': {'conversation_id': _conv},
};

Map<String, dynamic> _member() => {
  'id': 'm_new',
  'collectionId': 'cm_cid',
  'collectionName': 'conversation_members',
  'created': '2026-11-17T10:00:00.000Z',
  'updated': '2026-11-17T10:00:00.000Z',
  'conversation_id': 'g1',
  'user_id': 'u_test',
  'role': 'member',
  'joined_at': '2026-11-17T10:00:00.000Z',
  'expand': {'conversation_id': _conv},
};

http.Response _page(List<Map<String, dynamic>> items) => http.Response(
  jsonEncode({
    'page': 1,
    'perPage': 500,
    'totalItems': items.length,
    'totalPages': 1,
    'items': items,
  }),
  200,
  headers: {'content-type': 'application/json'},
);

/// [mine]: my member rows (sync list). [former]: my former rows, or null for
/// a server without the collection (404). Probes and other-member lists: empty.
MockClient _client(
  List<Map<String, dynamic>> mine,
  List<Map<String, dynamic>>? former,
) => MockClient((req) async {
  final p = req.url.path;
  if (p.startsWith('/api/realtime')) return Completer<http.Response>().future;
  if (p.contains('/collections/former_members/records')) {
    return former == null
        ? http.Response('{"message":"Missing collection context."}', 404)
        : _page(former);
  }
  if (p.contains('/collections/conversation_members/records')) {
    final f = req.url.queryParameters['filter'] ?? '';
    return _page(f.contains('conversation_id=') ? [] : mine);
  }
  return http.Response('{"message":"unhandled"}', 404);
});

Future<List<({String body, DateTime at})>> _system(CharHarness h) async {
  final rows = await h.db.messagesDao.watchMessages('g1').first;
  return [
    for (final r in rows)
      if (r.type == 'system')
        (body: bodyCache.get(r.localId) ?? '', at: r.createdAt),
  ];
}

void main() {
  test(
    'fresh install: a removed group comes back as left, with the line',
    () async {
      final h = charHarness(clientFactory: () => _client([], [_former()]));
      addTearDown(h.close);
      await buildRepo(h).debugSyncConversations();

      final conv = await h.db.conversationsDao.getConversationById('g1');
      expect(conv?.name, 'Former test');
      expect(
        conv?.lastMessageAt?.toUtc(),
        DateTime.utc(2026, 11, 16, 10),
        reason: 'ordered at history_until, not the group\'s newest message',
      );
      final me = await h.db.conversationsDao.getMemberByUserAndConv(
        'u_test',
        'g1',
      );
      expect(me?.id, 'fm1');
      expect(me?.role, 'left');
      expect(me?.joinedAt.toUtc(), DateTime.utc(2026, 10, 2, 10));
      final sys = await _system(h);
      expect(sys.map((s) => s.body), ['You were removed from this group']);
      expect(sys.single.at.toUtc(), DateTime.utc(2026, 11, 16, 10));
    },
  );

  test('a left group comes back without the removed line', () async {
    final h = charHarness(
      clientFactory: () => _client([], [_former(reason: 'left')]),
    );
    addTearDown(h.close);
    await buildRepo(h).debugSyncConversations();

    expect(
      (await h.db.conversationsDao.getMemberByUserAndConv(
        'u_test',
        'g1',
      ))?.role,
      'left',
    );
    expect(await _system(h), isEmpty);
  });

  test('a chat with a local row is left to the removal guard', () async {
    final h = charHarness(clientFactory: () => _client([], [_former()]));
    addTearDown(h.close);
    await seedConversationAndKey(h); // un-wiped phone, role member
    await buildRepo(h).debugSyncConversations(); // removal miss 1/2

    final me = await h.db.conversationsDao.getMemberByUserAndConv(
      'u_test',
      'g1',
    );
    expect(me?.id, 'm1');
    expect(me?.role, isNot('left'));
    expect(await _system(h), isEmpty);
  });

  test('a re-added (active) chat wins over its former record', () async {
    final h = charHarness(
      clientFactory: () => _client([_member()], [_former()]),
    );
    addTearDown(h.close);
    await buildRepo(h).debugSyncConversations();

    final me = await h.db.conversationsDao.getMemberByUserAndConv(
      'u_test',
      'g1',
    );
    expect(me?.id, 'm_new');
    expect(me?.role, 'member');
    expect(await _system(h), isEmpty);
  });

  test('a server without former_members: logged, sync goes on', () async {
    final h = charHarness(clientFactory: () => _client([_member()], null));
    addTearDown(h.close);
    await buildRepo(h).debugSyncConversations();

    expect(
      (await h.db.conversationsDao.getMemberByUserAndConv(
        'u_test',
        'g1',
      ))?.role,
      'member',
    );
  });
}
