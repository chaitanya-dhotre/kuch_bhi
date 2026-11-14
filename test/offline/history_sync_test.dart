/// History-sync spec S1 + S4 (docs/design/pages/history-sync.md): tick
/// status comes from one receipts list and one member list per chat, not
/// from 2–3 requests per own message.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import 'char_harness.dart';

final _old = DateTime.utc(2026, 7, 21, 10);
final _readAt = DateTime.utc(2026, 11, 5, 12);
const _day = 86400;

RecordModel _receipt(String to, {bool delivered = false, bool read = false}) =>
    RecordModel.fromJson({
      'id': 'r_$to',
      'recipient_id': to,
      'delivered_at': delivered || read ? 'x' : '',
      'read_at': read ? 'x' : '',
    });

Map<String, Object?> _msg(int i, {required bool mine}) {
  final at = _old.subtract(Duration(minutes: i)).toIso8601String();
  return {
    'id': 'm${i.toString().padLeft(3, '0')}',
    'collectionId': 'messages',
    'collectionName': 'messages',
    'created': at,
    'updated': at,
    'conversation_id': 'g1',
    'sender_id': mine ? 'u_test' : 'u_peer',
    'type': 'text',
    // Empty body: no decrypt hop, the row still lands (keeps the test fast).
    'encrypted_body': '',
    'iv': '',
    'reply_to_id': '',
    'is_deleted_for_everyone': false,
    'is_pinned': false,
    'media_id': '',
    'disappear_after': 0,
    'expires_at': '',
  };
}

Map<String, Object?> _receiptJson(String msgId, String to,
        {bool delivered = true, bool read = false}) =>
    {
      'id': 'r_${msgId}_$to',
      'message_id': msgId,
      'recipient_id': to,
      'delivered_at': delivered || read ? _readAt.toIso8601String() : '',
      'read_at': read ? _readAt.toIso8601String() : '',
      'updated': _readAt.toIso8601String(),
    };

http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body), status,
    headers: {'content-type': 'application/json'});

/// A PocketBase that pages [items] the way the real one does.
http.Response _page(http.Request req, List<Object?> items) {
  final q = req.url.queryParameters;
  final page = int.tryParse(q['page'] ?? '') ?? 1;
  final perPage = int.tryParse(q['perPage'] ?? '') ?? 30;
  final skip = q['skipTotal'] == 'true' || q['skipTotal'] == '1';
  final slice = items.skip((page - 1) * perPage).take(perPage).toList();
  return _json({
    'page': page,
    'perPage': perPage,
    'totalItems': skip ? -1 : items.length,
    'totalPages': skip ? -1 : (items.length / perPage).ceil(),
    'items': slice,
  });
}

/// Records every request; answers messages, receipts and members.
class _Server {
  _Server({
    this.messages = const [],
    this.receipts = const [],
    this.failReceipts = false,
    this.failMembers = false,
  });
  final List<Map<String, Object?>> messages;
  final List<Map<String, Object?>> receipts;
  static const members = ['u_test', 'u_peer'];
  final bool failReceipts;
  final bool failMembers;
  final requests = <http.Request>[];

  Iterable<http.Request> on(String collection) => requests.where(
      (r) => r.url.path.contains('/collections/$collection/records'));

  late final client = MockClient((req) async {
    final path = req.url.path;
    if (path.startsWith('/api/realtime')) {
      return Completer<http.Response>().future;
    }
    requests.add(req);
    final filter = req.url.queryParameters['filter'] ?? '';
    if (path.contains('/collections/messages/records/')) {
      return _json(messages.first);
    }
    if (path.contains('/collections/messages/records')) {
      return _page(req, messages);
    }
    if (path.contains('/collections/message_receipts/records')) {
      if (failReceipts) return _json({'message': 'boom'}, 500);
      return _page(req, receipts);
    }
    if (path.contains('/collections/conversation_members/records') &&
        filter.contains('conversation_id')) {
      if (failMembers) return _json({'message': 'boom'}, 500);
      return _page(req, [
        for (final u in members) {'id': 'mem_$u', 'user_id': u},
      ]);
    }
    return _page(req, const []);
  });
}

Future<CharHarness> _signedIn(_Server server) async {
  final h = charHarness(clientFactory: () => server.client);
  addTearDown(h.close);
  await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
  await seedConversationAndKey(h);
  h.pbClient.serverClock.observe(HttpDate.format(DateTime.now()));
  return h;
}

/// 450 messages, 300 mine; mine alternate read / delivered / no receipt.
_Server _bigChat({bool failReceipts = false, bool failMembers = false}) {
  final messages = [for (var i = 0; i < 450; i++) _msg(i, mine: i % 3 != 0)];
  final receipts = <Map<String, Object?>>[];
  for (var i = 0; i < 450; i++) {
    if (i % 3 == 0) continue;
    final id = messages[i]['id'] as String;
    if (i % 3 == 1) receipts.add(_receiptJson(id, 'u_peer', read: true));
    if (i % 3 == 2 && i % 2 == 0) receipts.add(_receiptJson(id, 'u_peer'));
  }
  return _Server(
    messages: messages,
    receipts: receipts,
    failReceipts: failReceipts,
    failMembers: failMembers,
  );
}

String _expected(int i) =>
    i % 3 == 1 ? 'read' : (i % 2 == 0 ? 'delivered' : 'sent');

// --- The two rules as they were before S1, copied for the golden table. ---

/// Old `_computeSenderStatus` (history ingest), members list reachable.
String _oldIngest(List<RecordModel> res, List<String> members, String sender) {
  if (res.isEmpty) return 'sent';
  var required = members.where((u) => u.isNotEmpty && u != sender).toSet();
  if (required.isEmpty) required = {'__none__'};
  return _oldRule(res, required);
}

/// Old `_updateMsgReceiptStatus` (reconcile), members list reachable.
String? _oldReconcile(
    List<RecordModel> res, List<String> members, String sender) {
  if (res.isEmpty) return null; // no write
  var required = members.where((u) => u.isNotEmpty && u != sender).toSet();
  if (required.isEmpty) {
    required = res
        .map((r) => r.getStringValue('recipient_id'))
        .where((u) => u.isNotEmpty)
        .toSet();
  }
  return _oldRule(res, required);
}

String _oldRule(List<RecordModel> res, Set<String> required) {
  Set<String> who(String f) => res
      .where((r) => r.getStringValue(f).isNotEmpty)
      .map((r) => r.getStringValue('recipient_id'))
      .toSet();
  if (required.every(who('read_at').contains)) return 'read';
  if (required.every(who('delivered_at').contains)) return 'delivered';
  return 'sent';
}

void main() {
  setUp(bodyCache.clear);

  group('gate 1: senderStatusFor', () {
    test('no receipts is sent', () {
      expect(senderStatusFor(const [], {'a'}), 'sent');
      expect(senderStatusFor(const [], {}), 'sent');
    });
    test('all delivered / all read', () {
      expect(
          senderStatusFor([_receipt('a', delivered: true)], {'a'}), 'delivered');
      expect(senderStatusFor([_receipt('a', read: true)], {'a'}), 'read');
    });
    test('group of 3, one receipt missing, is sent', () {
      expect(
          senderStatusFor(
              [_receipt('a', read: true), _receipt('b', read: true)],
              {'a', 'b', 'c'}),
          'sent');
    });
    test('one read, one only delivered, is delivered', () {
      expect(
          senderStatusFor([_receipt('a', read: true), _receipt('b', delivered: true)],
              {'a', 'b'}),
          'delivered');
    });
    test('D1: empty required falls back to the receipts present', () {
      expect(senderStatusFor([_receipt('a', read: true)], {}), 'read');
      expect(
          senderStatusFor(
              [_receipt('a', read: true), _receipt('b', delivered: true)], {}),
          'delivered');
      expect(senderStatusFor([_receipt('a')], {}), 'sent');
    });
  });

  test('gate 3: same statuses as the old rules, 20 cases', () {
    final d = _receipt; // short
    final cases = <(List<RecordModel>, List<String>)>[
      ([], ['me', 'a']),
      ([d('a')], ['me', 'a']),
      ([d('a', delivered: true)], ['me', 'a']),
      ([d('a', read: true)], ['me', 'a']),
      ([d('a', read: true)], ['me', 'a', 'b']),
      ([d('a', read: true), d('b', read: true)], ['me', 'a', 'b']),
      ([d('a', read: true), d('b', delivered: true)], ['me', 'a', 'b']),
      ([d('a', delivered: true), d('b', delivered: true)], ['me', 'a', 'b']),
      ([d('a', delivered: true), d('b')], ['me', 'a', 'b']),
      ([d('a', read: true), d('b', read: true)], ['me', 'a', 'b', 'c']),
      // A receipt from someone who left: the member list wins.
      ([d('a', read: true), d('gone')], ['me', 'a']),
      ([d('a', delivered: true), d('gone', read: true)], ['me', 'a']),
      ([d('gone', read: true)], ['me', 'a']),
      ([d('a', read: true), d('b', read: true), d('c', read: true)],
          ['me', 'a', 'b', 'c']),
      ([d('a', read: true), d('b', read: true), d('c', delivered: true)],
          ['me', 'a', 'b', 'c']),
      ([d('a', delivered: true)], ['me', 'a', 'b', 'c']),
      ([d('a', read: true), d('a', delivered: true)], ['me', 'a']),
      // D1: nobody else left. Old ingest said sent; the one rule now is the
      // reconcile's (receipts present).
      ([d('a', read: true)], ['me']),
      ([d('a', delivered: true)], ['me']),
      ([d('a')], ['me']),
    ];
    expect(cases, hasLength(20));
    for (final (res, members) in cases) {
      final required = members.where((u) => u != 'me').toSet();
      final now = senderStatusFor(res, required);
      expect(now, _oldReconcile(res, members, 'me') ?? 'sent',
          reason: 'reconcile rule, $members');
      if (required.isNotEmpty) {
        expect(now, _oldIngest(res, members, 'me'),
            reason: 'ingest rule, $members');
      }
    }
  });

  test('gate 2: history sync asks for ticks once per chat, and counts once',
      () async {
    final server = _bigChat();
    final h = await _signedIn(server);

    await buildRepo(h).syncAllHistory();

    final receipts = server.on('message_receipts').toList();
    expect(receipts, hasLength(lessThanOrEqualTo(1)));
    expect(receipts.single.url.queryParameters['filter'],
        'conversation_id="g1" && recipient_id!="u_test"');
    // Restore rev 2 R5: the tick members come from local rows, so the
    // history sync sends no member list of its own.
    final members = server
        .on('conversation_members')
        .where((r) => r.url.queryParameters['filter'] == 'conversation_id="g1"')
        .toList();
    expect(members, isEmpty);
    expect(
        server.requests
            .where((r) => r.url.path.contains('/collections/messages/records/')),
        isEmpty,
        reason: 'no messages/<id> lookups');
    final pages = server.on('messages').toList();
    expect(pages.where((r) => r.url.queryParameters['perPage'] == '1'), isEmpty);
    expect(pages, hasLength(3));
    for (final p in pages.skip(1)) {
      expect(p.url.queryParameters['skipTotal'], anyOf('true', '1'));
    }

    for (var i = 0; i < 450; i++) {
      final row = await h.db.messagesDao
          .getMessageByServerId('m${i.toString().padLeft(3, '0')}');
      expect(row, isNotNull);
      if (i % 3 != 0) expect(row!.status, _expected(i), reason: 'row $i');
    }
  });

  group('gate 5: the index fails, history still lands', () {
    test('receipts list fails: own rows are sent', () async {
      final server = _bigChat(failReceipts: true);
      final h = await _signedIn(server);
      await buildRepo(h).syncAllHistory();
      final rows = await h.db.messagesDao.watchMessages('g1').first;
      expect(rows, hasLength(450));
      expect(
          rows.where((r) => r.senderId == 'u_test').map((r) => r.status).toSet(),
          {'sent'});
    });

    test('members list fails: the receipts present decide', () async {
      final server = _bigChat(failMembers: true);
      final h = await _signedIn(server);
      await buildRepo(h).syncAllHistory();
      final rows = await h.db.messagesDao.watchMessages('g1').first;
      expect(rows, hasLength(450));
      expect((await h.db.messagesDao.getMessageByServerId('m001'))!.status,
          'read');
      expect((await h.db.messagesDao.getMessageByServerId('m002'))!.status,
          'delivered');
    });
  });

  test('gate 4: reconcile, 50 own delivered rows, 1 + 1 requests', () async {
    final receipts = <Map<String, Object?>>[];
    for (var i = 0; i < 50; i++) {
      final id = 'o$i';
      // o0 read by everyone; o1 receipts say less (regression); rest same.
      receipts.add(_receiptJson(id, 'u_peer', delivered: i != 1, read: i == 0));
    }
    receipts.add(_receiptJson('o_read', 'u_peer', delivered: false));
    final server = _Server(receipts: receipts);
    final h = await _signedIn(server);
    Future<void> seed(String id, String status) =>
        h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
          localId: 'l_$id',
          serverId: Value(id),
          conversationId: 'g1',
          senderId: 'u_test',
          type: 'text',
          encryptedBody: 'c',
          iv: 'i',
          status: Value(status),
          disappearAfter: const Value(_day),
          createdAt: _old,
          updatedAt: _old,
        ));
    for (var i = 0; i < 50; i++) {
      await seed('o$i', 'delivered');
    }
    await seed('o_read', 'read');

    await buildRepo(h).debugReconcileReceipts('g1');

    expect(server.on('message_receipts'), hasLength(1));
    expect(server.on('conversation_members'), hasLength(1));
    Future<MessagesTableData> row(String id) async =>
        (await h.db.messagesDao.getMessageByServerId(id))!;
    final read = await row('o0');
    expect(read.status, 'read');
    expect(read.expiresAt!.toUtc(), _readAt.add(const Duration(days: 1)),
        reason: 'clock starts on the read write');
    expect((await row('o1')).status, 'delivered', reason: 'never regress');
    for (final id in ['o1', 'o2', 'o49', 'o_read']) {
      expect((await row(id)).updatedAt.toUtc(), _old,
          reason: '$id: no write (regress / same value / already read)');
    }
    expect((await row('o_read')).status, 'read');
  });
}
