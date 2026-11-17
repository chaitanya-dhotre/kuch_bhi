/// Leave-rotation spec (docs/design/pages/leave-rotation.md) §6 gates 5–12:
/// the elected owner's phone rotates when a current-key holder is no longer
/// a member, and the leaver's own phone never touches group_keys.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import 'char_harness.dart';

const _me = 'u_test';
const _json = {'content-type': 'application/json'};

/// Stateful fake PocketBase: members of g1, its group_keys rows, and every
/// group_keys request.
class _Server {
  _Server(this.members, List<(String, int)> keys)
    : keys = [for (final k in keys) (user: k.$1, version: k.$2)];
  final Map<String, String> members; // user id → role
  final List<({String user, int version})> keys;
  final posts = <({String user, int version})>[];
  var keyRequests = 0;
  int? keyRequestsAtDelete;
  var checkReads = 0; // full group_keys list of g1 (the K1 check)
  var memberListFails = false;
  late String myPub;

  Map<String, dynamic> _member(String uid) => {
    'id': 'mem_$uid',
    'collectionId': 'cm',
    'collectionName': 'conversation_members',
    'created': '2026-07-01 10:00:00.000Z',
    'updated': '2026-07-01 10:00:00.000Z',
    'conversation_id': 'g1',
    'user_id': uid,
    'role': members[uid],
    'joined_at': '2026-07-01 10:00:00.000Z',
    if (uid == _me)
      'expand': {
        'conversation_id': {
          'id': 'g1',
          'collectionId': 'cv',
          'collectionName': 'conversations',
          'created': '2026-07-01 10:00:00.000Z',
          'updated': '2026-07-01 10:00:00.000Z',
          'type': 'group',
          'name': 'Leave test',
          'created_by': _me,
        },
      },
  };

  http.Response _list(List<Map<String, dynamic>> items) => http.Response(
    jsonEncode({
      'page': 1,
      'perPage': 500,
      'totalItems': items.length,
      'totalPages': 1,
      'items': items,
    }),
    200,
    headers: _json,
  );

  MockClient client() => MockClient((req) async {
    final path = req.url.path;
    final filter = req.url.queryParameters['filter'] ?? '';
    if (path.startsWith('/api/realtime')) {
      return Completer<http.Response>().future;
    }
    if (path.contains('/collections/conversation_members/records')) {
      if (req.method == 'DELETE') {
        keyRequestsAtDelete = keyRequests;
        members.remove(path.split('/').last.replaceFirst('mem_', ''));
        return http.Response('', 204);
      }
      Iterable<String> ids = members.keys;
      if (filter == 'user_id="$_me"') {
        ids = ids.where((u) => u == _me);
      } else if (filter.contains('user_id!="$_me"')) {
        ids = ids.where((u) => u != _me);
      } else if (filter.contains('&&user_id="')) {
        final uid = RegExp(r'user_id="([^"]+)"').firstMatch(filter)!.group(1);
        ids = ids.where((u) => u == uid);
      } else if (filter == 'conversation_id="g1"' && memberListFails) {
        return http.Response('{"message":"boom"}', 500);
      }
      if (filter.contains('role="admin"')) {
        ids = ids.where((u) => members[u] == 'admin');
      }
      return _list([for (final u in ids) _member(u)]);
    }
    if (path.contains('/collections/group_keys/records')) {
      keyRequests++;
      if (req.method == 'POST') {
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        final row = (
          user: b['user_id'] as String,
          version: (b['key_version'] as num).toInt(),
        );
        keys.add(row);
        posts.add(row);
        return http.Response(
          jsonEncode({'id': 'k${keys.length}', ...b}),
          200,
          headers: _json,
        );
      }
      if (filter == 'conversation_id="g1"' &&
          req.url.queryParameters['sort'] == null) {
        checkReads++;
      }
      final rows = [...keys]..sort((a, b) => b.version - a.version);
      return _list([
        for (final k in rows)
          {
            'id': 'k_${k.user}_${k.version}',
            'collectionId': 'gk',
            'collectionName': 'group_keys',
            'created': '2026-07-01 10:00:00.000Z',
            'updated': '2026-07-01 10:00:00.000Z',
            'conversation_id': 'g1',
            'user_id': k.user,
            'key_version': k.version,
            'encrypted_key': 'x',
            'encrypted_by_user_id': _me,
          },
      ]);
    }
    if (req.method == 'GET' && path.contains('/collections/users/records/')) {
      final uid = path.split('/').last;
      return http.Response(
        jsonEncode({
          'id': uid,
          'collectionId': 'us',
          'collectionName': 'users',
          'created': '2026-07-01 10:00:00.000Z',
          'updated': '2026-07-01 10:00:00.000Z',
          'username': uid,
          'public_key': myPub,
        }),
        200,
        headers: _json,
      );
    }
    if (req.method == 'GET') return _list(const []);
    return http.Response('{"message":"unhandled"}', 400);
  });
}

/// Local rows: me with [myRole] plus [others] (all plain members).
Future<(CharHarness, MessageRepositoryImpl)> _setup(
  _Server srv, {
  String myRole = 'admin',
  List<String> others = const ['u_b'],
}) async {
  final h = charHarness(clientFactory: srv.client);
  addTearDown(h.close);
  await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, _me);
  await seedConversationAndKey(h);
  srv.myPub = await h.encryption.getPublicKeyBase64();
  await h.db.conversationsDao.upsertMember(
    ConversationMembersTableCompanion.insert(
      id: 'mem_$_me',
      conversationId: 'g1',
      userId: _me,
      role: Value(myRole),
      joinedAt: DateTime.utc(2026, 7, 1),
    ),
  );
  await h.db.conversationsDao.removeStaleMemberRows('g1', {'mem_$_me'});
  for (final u in others) {
    await h.db.conversationsDao.upsertMember(
      ConversationMembersTableCompanion.insert(
        id: 'mem_$u',
        conversationId: 'g1',
        userId: u,
        joinedAt: DateTime.utc(2026, 7, 1),
      ),
    );
  }
  final repo = buildRepo(h)..keyCheckDelay = const Duration(milliseconds: 20);
  return (h, repo);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 400));

void main() {
  test('5: owner phone rotates the leaver out', () async {
    final srv = _Server({_me: 'admin'}, [(_me, 3), ('u_b', 3)]);
    final (_, repo) = await _setup(srv);

    await repo.debugSyncConversations();
    await _settle();

    expect(srv.posts, [
      (user: _me, version: 4),
    ], reason: 'one rotation at v4, for the remaining member only');
  });

  test('6: a smaller-id admin on the server owns it, so no rotation', () async {
    final srv = _Server(
      {_me: 'admin', 'a_admin': 'admin'},
      [(_me, 3), ('a_admin', 3), ('u_b', 3)],
    );
    final (_, repo) = await _setup(srv, others: ['a_admin', 'u_b']);

    await repo.debugSyncConversations();
    await _settle();

    expect(srv.checkReads, 0);
    expect(srv.posts, isEmpty);
  });

  test('7: a plain member phone makes no group_keys request', () async {
    final srv = _Server({_me: 'member'}, [(_me, 3), ('u_b', 3)]);
    final (_, repo) = await _setup(srv, myRole: 'member');

    await repo.debugSyncConversations();
    final before = srv.keyRequests;
    await _settle();

    expect(
      srv.keyRequests,
      before,
      reason: 'the check stops at the local gate',
    );
    expect(srv.posts, isEmpty);
  });

  test('8: member list error = no rotation, no throw', () async {
    final srv = _Server({_me: 'admin'}, [(_me, 3), ('u_b', 3)])
      ..memberListFails = true;
    final (_, repo) = await _setup(srv);

    await repo.debugSyncConversations();
    await _settle();

    expect(srv.checkReads, 0);
    expect(srv.posts, isEmpty);
  });

  test('9: nobody stale or missing = no rotation', () async {
    // u_c was already rotated out earlier (no row at v3); u_b still a member.
    final srv = _Server(
      {_me: 'admin', 'u_b': 'member'},
      [(_me, 3), ('u_b', 3), ('u_c', 2)],
    );
    final (_, repo) = await _setup(srv, others: ['u_b', 'u_c']);

    await repo.debugSyncConversations();
    await _settle();

    expect(srv.checkReads, 1, reason: 'u_c gone triggered one check');
    expect(srv.posts, isEmpty);
  });

  test('10: a removal by me rotates once, the sync adds none', () async {
    final srv = _Server(
      {_me: 'admin', 'u_b': 'member'},
      [(_me, 3), ('u_b', 3)],
    );
    final (_, repo) = await _setup(srv);

    await repo.removeMemberFromGroup('g1', 'u_b');
    await repo.debugSyncConversations();
    await _settle();

    expect(srv.posts, [(user: _me, version: 4)]);
  });

  test('11: two syncs inside the delay = one check, one rotation', () async {
    final srv = _Server({_me: 'admin'}, [(_me, 3), ('u_b', 3), ('u_c', 3)]);
    final (h, repo) = await _setup(srv, others: ['u_b']);

    await repo.debugSyncConversations();
    // A second leaver seen by the next pass, still inside the debounce.
    await h.db.conversationsDao.upsertMember(
      ConversationMembersTableCompanion.insert(
        id: 'mem_u_c',
        conversationId: 'g1',
        userId: 'u_c',
        joinedAt: DateTime.utc(2026, 7, 1),
      ),
    );
    await repo.debugSyncConversations();
    await _settle();

    expect(srv.checkReads, 1);
    expect(srv.posts, [(user: _me, version: 4)]);
  });

  test('12: leaveGroup makes no group_keys request', () async {
    final srv = _Server(
      {_me: 'member', 'u_a': 'admin'},
      [(_me, 3), ('u_a', 3)],
    );
    final (_, repo) = await _setup(srv, myRole: 'member', others: ['u_a']);

    await repo.leaveGroup('g1');
    await _settle();

    expect(srv.members.containsKey(_me), isFalse);
    // The "left" line reads the key before the delete; nothing after it.
    expect(
      srv.keyRequests,
      srv.keyRequestsAtDelete,
      reason: 'no rotate after the leave (K3)',
    );
    expect(srv.posts, isEmpty);
  });
}
