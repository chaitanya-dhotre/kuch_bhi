import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:drift/drift.dart' show Value;
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';

import 'char_harness.dart'; // buildRepo + seedConversationAndKey live here

/// Backlog §7 — false "You were removed from this group".
///
/// Live repro 2026-10-12: a freshly-created group's `conversation_members`
/// fetch predates the new membership row, and the reconcile verdict loop
/// treats "absent from that one list snapshot" as an admin removal — wiping
/// the group key and dropping a local system bubble within seconds of
/// creation (and dropping the group from the chat list).
///
/// Contract pinned here (fix = consecutive-miss + refetch-before-verdict):
/// 1. stale list + live row (point query sees it) → NO verdict;
/// 2. list miss + point query miss twice in a row → verdict fires;
/// 3. point query failing → never verdict (cannot confirm ⇒ no condemn).

/// Mutable feed for the fake PocketBase: the main membership list and the
/// per-conversation confirmation probe are answered independently so a test
/// can reproduce the stale-snapshot race (list empty, row exists).
class SyncFeed {
  List<Map<String, dynamic>> listItems = [];
  List<Map<String, dynamic>> probeItems = [];
  int probeStatus = 200; // != 200 → point query fails (unconfirmable)
  int probeCalls = 0;
  int listCalls = 0;
}

Map<String, dynamic> memberItem({String id = 'm1'}) => {
      'id': id,
      'collectionId': 'conv_members_cid',
      'collectionName': 'conversation_members',
      'created': '2026-10-13T10:00:00.000Z',
      'updated': '2026-10-13T10:00:00.000Z',
      'fields': {},
      'conversation_id': 'g1',
      'user_id': 'u_test',
      'role': 'member',
      'joined_at': '2026-10-13T10:00:00.000Z',
    };

http.Response _envelope(List<Map<String, dynamic>> items) => http.Response(
      jsonEncode({
        'page': 1,
        'perPage': 30,
        'totalItems': items.length,
        'totalPages': 1,
        'items': items,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

/// Routes by the `filter` query param: the main sync list filters only on
/// `user_id`; the confirmation probe filters on `conversation_id` too.
MockClient syncClient(SyncFeed feed) => MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future; // SSE hangs, never 404s
      }
      if (req.url.path.contains('/collections/conversation_members/records')) {
        final filter = req.url.queryParameters['filter'] ?? '';
        if (filter.contains('conversation_id=')) {
          feed.probeCalls++;
          if (feed.probeStatus != 200) {
            return http.Response('{"message":"boom"}', feed.probeStatus);
          }
          return _envelope(feed.probeItems);
        }
        feed.listCalls++;
        return _envelope(feed.listItems);
      }
      return http.Response('{"message":"unhandled"}', 404);
    });

Future<String?> membershipRole(CharHarness h) async =>
    (await h.db.conversationsDao.getMemberByUserAndConv('u_test', 'g1'))
        ?.role;

Future<List<String>> systemBubbles(CharHarness h) async {
  final rows = await h.db.messagesDao.watchMessages('g1').first;
  return [
    for (final r in rows)
      if (r.type == 'system') bodyCache.get(r.localId) ?? '',
  ];
}

void main() {
  test('char: stale membership list does NOT condemn a live membership',
      () async {
    final feed = SyncFeed()
      ..listItems = [] // snapshot predates the new group's row
      ..probeItems = [memberItem()]; // point query sees it — row is live
    final h = charHarness(clientFactory: () => syncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);

    await repo.debugSyncConversations();

    expect(await membershipRole(h), isNot('left'),
        reason: 'stale list snapshot must not trigger the removal verdict');
    expect(await h.storage.read(key: 'group_key_g1'), isNotNull,
        reason: 'group key must survive a stale snapshot');
    expect(await systemBubbles(h), isEmpty,
        reason: 'no "You were removed from this group" bubble');
  });

  test('char: removal verdict fires only after consecutive confirmed misses',
      () async {
    final feed = SyncFeed()
      ..listItems = [] // membership genuinely gone server-side
      ..probeItems = [];
    final h = charHarness(clientFactory: () => syncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);

    await repo.debugSyncConversations(); // confirmed miss #1
    expect(await membershipRole(h), isNot('left'),
        reason: 'one confirmed miss is not enough — refetch next cycle');
    expect(await h.storage.read(key: 'group_key_g1'), isNotNull);
    expect(await systemBubbles(h), isEmpty);

    await repo.debugSyncConversations(); // confirmed miss #2 → verdict
    expect(await membershipRole(h), 'left',
        reason: 'second consecutive confirmed miss condemns the row');
    expect(await h.storage.read(key: 'group_key_g1'), isNull,
        reason: 'group key wiped on true removal');
    expect(await systemBubbles(h),
        contains('You were removed from this group'),
        reason: 'local system bubble emitted for a true removal');
  });

  test('char: failing confirmation probe never condemns', () async {
    final feed = SyncFeed()
      ..listItems = []
      ..probeStatus = 500; // cannot confirm absence
    final h = charHarness(clientFactory: () => syncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);

    await repo.debugSyncConversations();
    await repo.debugSyncConversations();
    await repo.debugSyncConversations();

    expect(await membershipRole(h), isNot('left'),
        reason: 'unconfirmable absence must never reach the verdict');
    expect(await h.storage.read(key: 'group_key_g1'), isNotNull);
    expect(await systemBubbles(h), isEmpty);
  });

  // Removal-lock R1: the removed phone gets one trigger at most, so the
  // held miss must schedule its own second pass.
  test('R1: a held miss re-checks on its own and condemns', () async {
    final feed = SyncFeed()
      ..listItems = []
      ..probeItems = [];
    final h = charHarness(clientFactory: () => syncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h)
      ..removalRecheckDelay = const Duration(milliseconds: 20);

    await repo.debugSyncConversations(); // miss 1/2, held
    expect(await membershipRole(h), isNot('left'));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(await membershipRole(h), 'left',
        reason: 'the follow-up pass is the second confirmed miss');
    expect(await h.storage.read(key: 'group_key_g1'), isNull);
    expect(await systemBubbles(h),
        contains('You were removed from this group'));
    expect(feed.probeCalls, 2, reason: 'one follow-up, no loop after it');
    expect(feed.listCalls, 1,
        reason: 'R2: the re-check asks only about the held chat');
  });

  test('R1: row found on the re-check — no verdict, no further timer',
      () async {
    final feed = SyncFeed()
      ..listItems = []
      ..probeItems = [];
    final h = charHarness(clientFactory: () => syncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h)
      ..removalRecheckDelay = const Duration(milliseconds: 20);

    await repo.debugSyncConversations(); // miss 1/2, held
    feed.probeItems = [memberItem()]; // the row is there after all
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(feed.probeCalls, 2);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(feed.probeCalls, 2, reason: 'a found row schedules nothing');
    expect(await membershipRole(h), isNot('left'));
    expect(await systemBubbles(h), isEmpty);
  });

  test('R1: a failing probe schedules no re-check', () async {
    final feed = SyncFeed()
      ..listItems = []
      ..probeStatus = 500;
    final h = charHarness(clientFactory: () => syncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h)
      ..removalRecheckDelay = const Duration(milliseconds: 20);

    await repo.debugSyncConversations();
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(feed.probeCalls, 1, reason: 'unconfirmed absence is not held');
    expect(await membershipRole(h), isNot('left'));
  });

  test('R2: leaving from this phone before the re-check is not a removal',
      () async {
    final feed = SyncFeed()
      ..listItems = []
      ..probeItems = [];
    final h = charHarness(clientFactory: () => syncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h)
      ..removalRecheckDelay = const Duration(milliseconds: 20);

    await repo.debugSyncConversations(); // miss 1/2, held
    await (h.db.update(h.db.conversationMembersTable)
          ..where((t) => t.userId.equals('u_test')))
        .write(const ConversationMembersTableCompanion(role: Value('left')));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(feed.probeCalls, 1, reason: 'a left row is not probed again');
    expect(await systemBubbles(h), isEmpty,
        reason: 'no "You were removed" after leaving here');
  });
}
