import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';

import 'char_harness.dart';

/// 2026-10-30: 4,326 receipt creates were refused with 429 in one day.
/// markConversationRead listed only my UNREAD receipts, so every chat open
/// tried to create a receipt for each already-read incoming message (400 on
/// the unique index, then 429 once *:create hit 20 per 5 s).
///
/// Contract: opening a chat creates receipts only for incoming messages that
/// have none, and updates only receipts that are not read yet.
void main() {
  test('mark read creates/updates only what is missing', () async {
    final creates = <String>[];
    final updates = <String>[];
    var listFilter = '';
    final client = MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (req.url.path.contains('/collections/message_receipts/records')) {
        if (req.method == 'POST') {
          creates.add(jsonDecode(req.body)['message_id'] as String);
          return http.Response('{"id":"new"}', 200,
              headers: {'content-type': 'application/json'});
        }
        if (req.method == 'PATCH') {
          updates.add(req.url.pathSegments.last);
          return http.Response('{"id":"x"}', 200,
              headers: {'content-type': 'application/json'});
        }
        listFilter = req.url.queryParameters['filter'] ?? '';
        // Server honours the read_at="" filter, as PocketBase would.
        final items = [
          {
            'id': 'r_read', 'message_id': 'srv_read',
            'recipient_id': 'u_test',
            'delivered_at': '2026-10-07T10:01:00.000Z',
            'read_at': '2026-10-07T10:02:00.000Z',
          },
          {
            'id': 'r_unread', 'message_id': 'srv_unread',
            'recipient_id': 'u_test',
            'delivered_at': '2026-10-07T10:01:00.000Z', 'read_at': '',
          },
        ].where((r) =>
            !listFilter.contains('read_at=""') || r['read_at'] == '').toList();
        return http.Response(
          jsonEncode({
            'page': 1, 'perPage': 200, 'totalItems': items.length,
            'totalPages': 1, 'items': items,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"message":"unhandled"}', 404);
    });

    final h = charHarness(clientFactory: () => client);
    addTearDown(h.close);
    await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
    await seedConversationAndKey(h);
    var minute = 0;
    for (final sid in ['srv_read', 'srv_unread', 'srv_missing']) {
      final at = DateTime.utc(2026, 10, 7, 10, minute++);
      await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId: 'l_$sid',
        conversationId: 'g1',
        senderId: 'u_peer',
        type: 'text',
        encryptedBody: 'x',
        iv: 'x',
        serverId: Value(sid),
        createdAt: at,
        updatedAt: at,
      ));
    }

    await buildRepo(h).markConversationRead('g1');

    expect(creates, ['srv_missing'],
        reason: 'an already-read message must not get a second create');
    expect(updates, ['r_unread'], reason: 'read receipts are left alone');
  });
}
