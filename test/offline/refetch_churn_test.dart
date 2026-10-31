import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kuch_bhi/data/local/database/app_database.dart';

import 'char_harness.dart';

/// Backlog 13.3 and 13.2 (2026-10-31, M52).
///
/// 13.3: "3 Oct Test" gained one unread on every resync with no new
/// message. Its newest row can't be decrypted, so the inclusive delta keeps
/// re-ingesting it (F2a retries unresolved rows). Each re-ingest re-bumped
/// the badge: PocketBase stamps carry milliseconds, drift stores
/// last_message_at in seconds, so the row always looked "newer". The same
/// re-ingest rewrote the `key_missing` verdict as `pending`, and nothing
/// re-runs the decrypt for it, so the Home preview sat on a skeleton.
///
/// 13.2: every receipt reconcile wrote the same status back, and each write
/// re-emitted the open chat's whole message list.

Map<String, Object?> _msg({
  required String id,
  required String sender,
  required String body,
  required String iv,
}) => {
  'id': id,
  'collectionId': 'messages', 'collectionName': 'messages',
  'created': '2026-10-07T10:00:00.123Z', // real stamps carry ms
  'updated': '2026-10-07T10:00:00.123Z',
  'conversation_id': 'g1', 'sender_id': sender,
  'type': 'text', 'encrypted_body': body, 'iv': iv,
  'reply_to_id': '', 'reply_preview': '',
  'is_deleted_for_everyone': false, 'is_deleted_for_me': false,
  'is_pinned': false, 'is_starred': false,
  'status': 'sent', 'media_id': '',
};

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

http.Response _list(List<Object?> items) => _json({
  'page': 1, 'perPage': 200, 'totalItems': items.length,
  'totalPages': 1, 'items': items,
});

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 600));

void main() {
  test('13.3: refetching an undecryptable newest row keeps the unread count '
      'and its key_missing verdict', () async {
    // Encrypted under a key this device never had (the lost rotation).
    final pre = charHarness();
    addTearDown(pre.close);
    final enc = await pre.encryption
        .encryptMessage('lost', List<int>.generate(32, (i) => 100 + i));
    final record =
        _msg(id: 'srv1', sender: 'u_peer', body: enc.ciphertext, iv: enc.iv);

    final h = charHarness(clientFactory: () => MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (req.url.path.contains('/collections/messages/records')) {
        return _list([record]);
      }
      return http.Response('{"message":"unhandled"}', 404);
    }));
    addTearDown(h.close);
    await seedConversationAndKey(h); // a current key that does not open it
    final repo = buildRepo(h);

    await repo.watchMessages('g1').first; // cold fetch
    await _settle();
    final row = (await h.db.messagesDao.watchMessages('g1').first).single;
    final unread0 =
        (await h.db.conversationsDao.getConversationById('g1'))!.unreadCount;
    expect(unread0, 1, reason: 'precondition: the new message badges once');
    // DecryptPass's verdict once the bubble or preview asked for the body.
    await (h.db.update(h.db.messagesTable)
          ..where((t) => t.localId.equals(row.localId)))
        .write(const MessagesTableCompanion(decryptState: Value('key_missing')));

    for (var i = 0; i < 2; i++) {
      await repo.watchMessages('g1').first; // warm refetch, same record
      await _settle();
    }

    final conv = (await h.db.conversationsDao.getConversationById('g1'))!;
    expect(conv.unreadCount, 1,
        reason: 'a refetched row is not a new message');
    final after = (await h.db.messagesDao.getMessageByServerId('srv1'))!;
    expect(after.decryptState, 'key_missing',
        reason: 'a retry that still misses must not regress the verdict to '
            'pending: the preview would sit on a skeleton');
  });

  test('13.3: a new message in the same second as the last one still badges',
      () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final a = await pre.encryption.encryptMessage('a', fixtureGroupKey);
    final b = await pre.encryption.encryptMessage('b', fixtureGroupKey);
    final recA = _msg(id: 'srvA', sender: 'u_peer', body: a.ciphertext,
        iv: a.iv);
    final recB = {
      ..._msg(id: 'srvB', sender: 'u_peer', body: b.ciphertext, iv: b.iv),
      'created': '2026-10-07T10:00:00.800Z',
      'updated': '2026-10-07T10:00:00.800Z',
    };
    var served = [recA];

    final h = charHarness(clientFactory: () => MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (req.url.path.contains('/collections/messages/records')) {
        return _list(served);
      }
      return http.Response('{"message":"unhandled"}', 404);
    }));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);

    await repo.watchMessages('g1').first;
    await _settle();
    expect((await h.db.conversationsDao.getConversationById('g1'))!
        .unreadCount, 1, reason: 'precondition');

    served = [recB, recA]; // B lands 0.7 s after A, same second
    await repo.watchMessages('g1').first;
    await _settle();

    expect((await h.db.conversationsDao.getConversationById('g1'))!
        .unreadCount, 2, reason: 'a genuinely new row badges');
  });

  test('13.2: a receipt reconcile that computes the current status writes '
      'nothing', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc = await pre.encryption.encryptMessage('mine', fixtureGroupKey);
    final record =
        _msg(id: 'srv1', sender: 'u_test', body: enc.ciphertext, iv: enc.iv);
    var receiptLists = 0;

    final h = charHarness(clientFactory: () => MockClient((req) async {
      final p = req.url.path;
      if (p.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (p.endsWith('/collections/messages/records/srv1')) {
        return _json(record);
      }
      if (p.contains('/collections/messages/records')) return _list([record]);
      if (p.contains('/collections/conversation_members/records')) {
        return _list([
          for (final u in ['u_test', 'u_a', 'u_b', 'u_c'])
            {'id': 'm_$u', 'conversation_id': 'g1', 'user_id': u},
        ]);
      }
      if (p.contains('/collections/message_receipts/records')) {
        receiptLists++;
        // 1 of 3 delivered and read → 'sent' (the M52 log line).
        return _list([
          {'id': 'r_a', 'message_id': 'srv1', 'recipient_id': 'u_a',
           'delivered_at': '2026-10-07T10:01:00.000Z',
           'read_at': '2026-10-07T10:02:00.000Z'},
          {'id': 'r_b', 'message_id': 'srv1', 'recipient_id': 'u_b',
           'delivered_at': '', 'read_at': ''},
        ]);
      }
      return http.Response('{"message":"unhandled"}', 404);
    }));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);

    await repo.watchMessages('g1').first; // cold fetch: tick computed 'sent'
    await _settle();
    expect((await h.db.messagesDao.getMessageByServerId('srv1'))!.status,
        'sent', reason: 'precondition');

    var emits = 0;
    final sub =
        h.db.messagesDao.watchMessages('g1').skip(1).listen((_) => emits++);
    addTearDown(sub.cancel);
    final listsBefore = receiptLists;
    for (var i = 0; i < 2; i++) {
      await repo.watchMessages('g1').first; // warm refetch → reconcile
      await _settle();
    }

    expect(receiptLists, greaterThan(listsBefore),
        reason: 'precondition: the reconcile ran');
    expect(emits, 0,
        reason: 'an unchanged status must not re-emit the whole list');
  });
}
