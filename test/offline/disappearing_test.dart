/// Backlog §7, spec docs/design/pages/disappearing.md. The user's chat lost
/// its history on the phone: ingest stamped every old message with
/// createdAt + the chat's timer, and the next chat open purged them. A
/// message now disappears only by a length the server fixed when it arrived,
/// and its clock starts when it is read.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, HttpDate;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';

import 'char_harness.dart';

const _day = 86400;
final _old = DateTime.utc(2026, 7, 21, 10);

Map<String, Object?> _record({
  String id = 'srv1',
  String sender = 'u_peer',
  DateTime? created,
  int disappearAfter = 0,
  String expiresAt = '',
}) {
  final at = (created ?? _old).toIso8601String();
  return {
    'id': id,
    'collectionId': 'messages',
    'collectionName': 'messages',
    'created': at,
    'updated': at,
    'conversation_id': 'g1',
    'sender_id': sender,
    'type': 'text',
    'encrypted_body': 'c',
    'iv': 'i',
    'reply_to_id': '',
    'is_deleted_for_everyone': false,
    'is_pinned': false,
    'media_id': '',
    'disappear_after': disappearAfter,
    'expires_at': expiresAt,
  };
}

http.Response _list(List<Object?> items) => http.Response(
      jsonEncode({
        'page': 1,
        'perPage': 200,
        'totalItems': items.length,
        'totalPages': 1,
        'items': items,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

/// Answers message pages with [messages], receipts with [receipts], members
/// with [members]; anything else is an empty list.
MockClient _server({
  List<Map<String, Object?>> messages = const [],
  List<Map<String, Object?>> receipts = const [],
  List<Map<String, Object?>> members = const [],
}) =>
    MockClient((req) async {
      final path = req.url.path;
      if (path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (path.contains('/collections/messages/records/')) {
        return http.Response(jsonEncode(messages.first), 200,
            headers: {'content-type': 'application/json'});
      }
      if (path.contains('/collections/messages/records')) {
        return _list(messages);
      }
      if (path.contains('/collections/message_receipts/records')) {
        return _list(receipts);
      }
      if (path.contains('/collections/conversation_members/records')) {
        return _list(members);
      }
      return _list(const []);
    });

Future<void> _setTimer(CharHarness h, int seconds) =>
    (h.db.update(h.db.conversationsTable)..where((t) => t.id.equals('g1')))
        .write(ConversationsTableCompanion(
            disappearingDuration: Value(seconds)));

Future<void> _seedRow(
  CharHarness h, {
  String id = 'srv1',
  String sender = 'u_peer',
  int? disappearAfter,
  DateTime? expiresAt,
  String status = 'delivered',
}) =>
    h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'l_$id',
      serverId: Value(id),
      conversationId: 'g1',
      senderId: sender,
      type: 'text',
      encryptedBody: 'c',
      iv: 'i',
      status: Value(status),
      disappearAfter: Value(disappearAfter),
      expiresAt: Value(expiresAt),
      createdAt: _old,
      updatedAt: _old,
    ));

/// A chat open runs the purge, so two opens are the bug's whole path: the
/// first ingests, the second purges.
Future<void> _openChatTwice(CharHarness h) async {
  final repo = buildRepo(h);
  await repo.watchMessages('g1').first;
  await repo.watchMessages('g1').first;
}

CharHarness _harness(MockClient client) {
  final h = charHarness(clientFactory: () => client);
  addTearDown(h.close);
  return h;
}

Future<void> _signIn(CharHarness h) async {
  await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
  await seedConversationAndKey(h);
  _serverSays(h, DateTime.now());
}

void _serverSays(CharHarness h, DateTime time) =>
    h.pbClient.serverClock.observe(HttpDate.format(time));

void main() {
  setUp(bodyCache.clear);

  test('a message older than the timer survives a chat open', () async {
    final h = _harness(_server(messages: [_record()]));
    await _signIn(h);
    await _setTimer(h, _day);

    await _openChatTwice(h);

    final row = await h.db.messagesDao.getMessageByServerId('srv1');
    expect(row, isNotNull, reason: 'old history must not be purged');
    expect(row!.expiresAt, isNull);
  });

  test('an unread timed message waits for its reader', () async {
    final h = _harness(_server(messages: [_record(disappearAfter: _day)]));
    await _signIn(h);

    await _openChatTwice(h);

    final row = await h.db.messagesDao.getMessageByServerId('srv1');
    expect(row, isNotNull);
    expect(row!.disappearAfter, _day);
    expect(row.expiresAt, isNull, reason: 'the clock has not started');
  });

  test('reading starts the clock on my unread timed rows, even offline',
      () async {
    final h = _harness(MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      throw http.ClientException('offline');
    }));
    await _signIn(h);
    await _seedRow(h, disappearAfter: _day);
    await _seedRow(h, id: 'srv_plain');
    await _seedRow(h, id: 'srv_mine', sender: 'u_test', disappearAfter: _day);
    final running = DateTime.utc(2030, 1, 1);
    await _seedRow(h, id: 'srv_running', disappearAfter: _day, expiresAt: running);

    final before = DateTime.now();
    await buildRepo(h).markConversationRead('g1');

    Future<DateTime?> expiry(String id) async =>
        (await h.db.messagesDao.getMessageByServerId(id))!.expiresAt;
    final started = await expiry('srv1');
    expect(started, isNotNull);
    expect(
      started!.difference(before).inSeconds,
      inInclusiveRange(_day - 2, _day + 5),
    );
    expect(await expiry('srv_plain'), isNull, reason: 'no timer on this one');
    expect(await expiry('srv_mine'), isNull, reason: 'my copy waits for ticks');
    expect((await expiry('srv_running'))!.toUtc(), running,
        reason: 'a running clock is never restarted');
  });

  test('my copy still counts when the server hides the record', () async {
    final lastRead = DateTime.utc(2026, 11, 5, 12);
    final h = _harness(MockClient((req) async {
      final path = req.url.path;
      if (path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (path.contains('/collections/messages/records/')) {
        return http.Response('{"message":"hidden"}', 404);
      }
      if (path.contains('/collections/message_receipts/records')) {
        return _list([
          {
            'id': 'r_read',
            'message_id': 'srv1',
            'recipient_id': 'u_a',
            'delivered_at': lastRead.toIso8601String(),
            'read_at': lastRead.toIso8601String(),
            'updated': lastRead.toIso8601String(),
          },
          // Left the group without reading: only the member list knows that.
          {
            'id': 'r_left',
            'message_id': 'srv1',
            'recipient_id': 'u_left',
            'delivered_at': '',
            'read_at': '',
            'updated': lastRead.toIso8601String(),
          },
        ]);
      }
      if (path.contains('/collections/conversation_members/records')) {
        return _list([
          {'id': 'm1', 'user_id': 'u_test'},
          {'id': 'm2', 'user_id': 'u_a'},
        ]);
      }
      return _list(const []);
    }));
    await _signIn(h);
    await _seedRow(h, sender: 'u_test', disappearAfter: _day, status: 'delivered');

    await buildRepo(h).debugReconcileReceipts('g1');

    final row = await h.db.messagesDao.getMessageByServerId('srv1');
    expect(row!.expiresAt!.toUtc(), lastRead.add(const Duration(days: 1)));
  });

  group('an expired message I read must still tell the server', () {
    final past = DateTime.now().subtract(const Duration(hours: 1));

    test('it sends the owed receipt, then goes', () async {
      final updates = <String>[];
      final h = _harness(MockClient((req) async {
        if (req.url.path.startsWith('/api/realtime')) {
          return Completer<http.Response>().future;
        }
        if (req.url.path.contains('/collections/message_receipts/records')) {
          if (req.method == 'PATCH') {
            updates.add(req.url.pathSegments.last);
            return http.Response('{"id":"r1"}', 200,
                headers: {'content-type': 'application/json'});
          }
          return _list([
            {
              'id': 'r1',
              'message_id': 'srv1',
              'recipient_id': 'u_test',
              'delivered_at': '',
              'read_at': '',
            },
          ]);
        }
        return _list(const []);
      }));
      await _signIn(h);
      await _seedRow(h, disappearAfter: _day, expiresAt: past);

      await buildRepo(h).watchMessages('g1').first;

      expect(updates, ['r1']);
      expect(await h.db.messagesDao.getMessageByServerId('srv1'), isNull);
    });

    test('with no network it waits', () async {
      final h = _harness(MockClient((req) async {
        if (req.url.path.startsWith('/api/realtime')) {
          return Completer<http.Response>().future;
        }
        throw http.ClientException('offline');
      }));
      await _signIn(h);
      await _seedRow(h, disappearAfter: _day, expiresAt: past);

      await buildRepo(h).watchMessages('g1').first;

      expect(await h.db.messagesDao.getMessageByServerId('srv1'), isNotNull);
    });
  });

  test('my own message starts counting from the last read', () async {
    final lastRead = DateTime.utc(2026, 11, 5, 12);
    final h = _harness(_server(
      messages: [_record(sender: 'u_test', disappearAfter: _day)],
      receipts: [
        {
          'id': 'r1',
          'message_id': 'srv1',
          'recipient_id': 'u_a',
          'delivered_at': lastRead.toIso8601String(),
          'read_at': lastRead.subtract(const Duration(hours: 2)).toIso8601String(),
          'updated': lastRead.subtract(const Duration(hours: 2)).toIso8601String(),
        },
        {
          'id': 'r2',
          'message_id': 'srv1',
          'recipient_id': 'u_b',
          'delivered_at': lastRead.toIso8601String(),
          // A reader's device clock: the server's `updated` is what counts.
          'read_at': '2031-01-01T00:00:00.000Z',
          'updated': lastRead.toIso8601String(),
        },
      ],
      members: [
        {'id': 'm1', 'user_id': 'u_test'},
        {'id': 'm2', 'user_id': 'u_a'},
        {'id': 'm3', 'user_id': 'u_b'},
      ],
    ));
    await _signIn(h);
    await _seedRow(h, sender: 'u_test', disappearAfter: _day, status: 'delivered');

    await buildRepo(h).debugReconcileReceipts('g1');

    final row = await h.db.messagesDao.getMessageByServerId('srv1');
    expect(row!.status, 'read');
    expect(row.expiresAt!.toUtc(), lastRead.add(const Duration(days: 1)));
  });

  test('changing the timer leaves sent messages as they are', () async {
    final running = DateTime.utc(2030, 1, 1);
    final h = _harness(_server(
      messages: [_record(disappearAfter: _day, created: DateTime.utc(2026, 11, 1))],
    ));
    await _signIn(h);
    await _setTimer(h, _day);
    await _seedRow(h, disappearAfter: _day, expiresAt: running);

    await _setTimer(h, 0);
    await buildRepo(h).loadMoreMessages('g1', 0);

    final row = await h.db.messagesDao.getMessageByServerId('srv1');
    expect(row!.expiresAt!.toUtc(), running);
    expect(row.disappearAfter, _day);
  });

  test('a reinstall copies a clock the server already started', () async {
    final at = DateTime.utc(2030, 1, 1);
    final h = _harness(_server(messages: [
      _record(disappearAfter: _day, expiresAt: at.toIso8601String()),
    ]));
    await _signIn(h);

    await buildRepo(h).loadMoreMessages('g1', 0);

    final row = await h.db.messagesDao.getMessageByServerId('srv1');
    expect(row!.expiresAt!.toUtc(), at);
  });

  test('a queued send has no clock, and its ack keeps the server length',
      () async {
    final h = _harness(MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (req.method == 'POST' &&
          req.url.path.contains('/collections/messages/records')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final now = DateTime.now().toUtc().toIso8601String();
        return http.Response(
          jsonEncode({
            ...body,
            'collectionId': 'messages',
            'collectionName': 'messages',
            'created': now,
            'updated': now,
            'disappear_after': _day,
            'expires_at': '',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"message":"unhandled"}', 404);
    }));
    await _signIn(h);
    await _setTimer(h, _day);
    final repo = buildRepo(h);
    await repo.outboxWorker.onAuthPaused(true);

    await repo.sendMessage(conversationId: 'g1', plaintext: 'hi');
    final queued = (await h.db.messagesDao.watchMessages('g1').first).single;
    expect(queued.expiresAt, isNull);

    await repo.sendOutboxOp((await h.db.outboxDao.forConversation('g1')).single);
    final sent = await h.db.messagesDao.getMessageByLocalId(queued.localId);
    expect(sent!.status, 'sent');
    expect(sent.disappearAfter, _day);
    expect(sent.expiresAt, isNull, reason: 'nobody has read it yet');
  });

  test('a server delete event never brings the row back', () async {
    final h = _harness(_server());
    await _signIn(h);
    final repo = buildRepo(h);

    await repo.onMessageEvent(RecordSubscriptionEvent(
      action: 'delete',
      record: RecordModel.fromJson(_record(disappearAfter: _day)),
    ));

    expect(await h.db.messagesDao.getMessageByServerId('srv1'), isNull);
  });

  test('an SSE pin keeps the length', () async {
    final h = _harness(_server());
    await _signIn(h);
    await _seedRow(h, disappearAfter: _day);
    final row = await h.db.messagesDao.getMessageByServerId('srv1');

    final c = buildRepo(h).ssePinDeleteCompanion(
      existing: row!,
      serverPinned: true,
      serverDeleted: false,
    );

    expect(c.disappearAfter.value, _day);
  });

  test('nothing to stamp re-emits nothing, so reading cannot loop', () async {
    final h = _harness(_server());
    await _signIn(h);
    await _seedRow(h); // no timer
    var emits = 0;
    final sub = h.db.messagesDao.watchMessages('g1').listen((_) => emits++);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    final before = emits;

    await buildRepo(h).markConversationRead('g1');
    await pumpEventQueue();

    expect(emits, before);
  });

  test('a row stored by the push handler picks up its length at fetch',
      () async {
    final h = _harness(_server(messages: [_record(disappearAfter: _day)]));
    await _signIn(h);
    await _seedRow(h); // same body, already 'ready', no length

    await buildRepo(h).watchMessages('g1').first; // cached rows: fetch runs on
    await h.db.messagesDao.watchMessages('g1').firstWhere(
          (rows) => rows.single.disappearAfter == _day,
        );
  });

  test('a lost-ack re-run stores the length', () async {
    final h = _harness(_server(messages: [
      _record(id: 'op1', sender: 'u_test', disappearAfter: _day),
    ]));
    await _signIn(h);
    final at = DateTime.utc(2026, 11, 5);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'l1',
      conversationId: 'g1',
      senderId: 'u_test',
      type: 'text',
      encryptedBody: 'c',
      iv: 'i',
      status: const Value('pending'),
      createdAt: at,
      updatedAt: at,
    ));
    await h.db.outboxDao.enqueue(OutboxTableCompanion.insert(
      opId: 'op1',
      kind: 'send_text',
      ref: 'l1',
      conversationId: 'g1',
      seq: 1,
      createdAt: at,
    ));

    await buildRepo(h).resolveDuplicateSend(
      opId: 'op1',
      senderId: 'u_test',
      conversationId: 'g1',
    );

    final row = await h.db.messagesDao.getMessageByLocalId('l1');
    expect(row!.disappearAfter, _day);
  });

  group('a message my clock already removed stays gone', () {
    Map<String, Object?> myRead(DateTime at) => {
          'id': 'r1',
          'message_id': 'srv1',
          'recipient_id': 'u_test',
          'delivered_at': at.toIso8601String(),
          'read_at': at.toIso8601String(),
          'updated': at.toIso8601String(),
        };

    Future<bool> refetch(CharHarness h) async {
      await _signIn(h);
      await buildRepo(h).loadMoreMessages('g1', 0);
      await _openChatTwice(h);
      final row = await h.db.messagesDao.getMessageByServerId('srv1');
      if (row == null) {
        final conv = await h.db.conversationsDao.getConversationById('g1');
        expect(conv!.unreadCount, 0, reason: 'no phantom badge');
      }
      return row != null;
    }

    test('my clock ran out while someone else has not read', () async {
      final h = _harness(_server(
        messages: [_record(disappearAfter: _day)],
        receipts: [
          myRead(DateTime.now().toUtc().subtract(const Duration(days: 2))),
        ],
      ));
      expect(await refetch(h), isFalse);
    });

    test('my clock is still running after a reinstall', () async {
      final h = _harness(_server(
        messages: [_record(disappearAfter: _day)],
        receipts: [
          myRead(DateTime.now().toUtc().subtract(const Duration(hours: 1))),
        ],
      ));
      expect(await refetch(h), isTrue);
    });

    test('a receipts failure keeps the message', () async {
      final h = _harness(MockClient((req) async {
        if (req.url.path.startsWith('/api/realtime')) {
          return Completer<http.Response>().future;
        }
        if (req.url.path.contains('/collections/messages/records')) {
          return _list([_record(disappearAfter: _day)]);
        }
        return http.Response('{"message":"down"}', 500);
      }));
      await _signIn(h);
      await buildRepo(h).loadMoreMessages('g1', 0);
      expect(await h.db.messagesDao.getMessageByServerId('srv1'), isNotNull);
    });
  });

  test('a full history page may have more, a short one is the end', () async {
    final page = [
      for (var i = 0; i < 40; i++)
        _record(id: 'srv$i', created: DateTime.utc(2026, 7, 21, 10, i)),
    ];
    final full = _harness(_server(messages: page));
    await _signIn(full);
    expect(await buildRepo(full).loadMoreMessages('g1', 40), isTrue);

    final short = _harness(_server(messages: page.take(3).toList()));
    await _signIn(short);
    expect(await buildRepo(short).loadMoreMessages('g1', 40), isFalse);
  });

  test('a message I cannot show is not read', () async {
    final updates = <String>[];
    final creates = <String>[];
    final h = _harness(MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (req.url.path.contains('/collections/message_receipts/records')) {
        if (req.method == 'PATCH') updates.add(req.url.pathSegments.last);
        if (req.method == 'POST') {
          creates.add(jsonDecode(req.body)['message_id'] as String);
        }
        if (req.method != 'GET') return _list(const []);
        return _list([
          {
            'id': 'r_locked',
            'message_id': 'srv_locked',
            'recipient_id': 'u_test',
            'delivered_at': '',
            'read_at': '',
          },
          {
            'id': 'r_not_here',
            'message_id': 'srv_not_here',
            'recipient_id': 'u_test',
            'delivered_at': '',
            'read_at': '',
          },
          {
            'id': 'r_ok',
            'message_id': 'srv_ok',
            'recipient_id': 'u_test',
            'delivered_at': '',
            'read_at': '',
          },
        ]);
      }
      return _list(const []);
    }));
    await _signIn(h);
    await _seedRow(h, id: 'srv_ok', disappearAfter: _day);
    await _seedRow(h, id: 'srv_locked', disappearAfter: _day);
    await _seedRow(h, id: 'srv_nokey', disappearAfter: _day);
    for (final id in ['srv_locked', 'srv_nokey']) {
      await (h.db.update(h.db.messagesTable)
            ..where((t) => t.serverId.equals(id)))
          .write(const MessagesTableCompanion(
              decryptState: Value('key_missing')));
    }

    await buildRepo(h).markConversationRead('g1');

    expect(updates, ['r_ok'], reason: 'unreadable and unloaded rows stay unread');
    expect(creates, isEmpty, reason: 'no read receipt for a locked row');
    Future<DateTime?> expiry(String id) async =>
        (await h.db.messagesDao.getMessageByServerId(id))!.expiresAt;
    expect(await expiry('srv_ok'), isNotNull);
    expect(await expiry('srv_locked'), isNull);
    expect(await expiry('srv_nokey'), isNull);
  });

  group('only server time can expire a message', () {
    final past = DateTime.now().subtract(const Duration(hours: 1));

    Future<bool> survivesOpen(CharHarness h) async {
      await buildRepo(h).watchMessages('g1').first;
      await pumpEventQueue();
      return await h.db.messagesDao.getMessageByServerId('srv1') != null;
    }

    test('a device clock set a day ahead deletes nothing', () async {
      final h = _harness(_server());
      await _signIn(h);
      await _seedRow(h, disappearAfter: _day, expiresAt: past);
      _serverSays(h, past.subtract(const Duration(days: 1)));

      expect(await survivesOpen(h), isTrue);
    });

    test('with no server time yet nothing is deleted', () async {
      final h = _harness(_server());
      await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
      await seedConversationAndKey(h);
      await _seedRow(h, disappearAfter: _day, expiresAt: past);

      expect(await survivesOpen(h), isTrue);
    });

    test('server time past the clock deletes it', () async {
      final h = _harness(_server(messages: const []));
      await _signIn(h);
      await _seedRow(h, disappearAfter: _day, expiresAt: past);

      expect(await survivesOpen(h), isFalse);
    });

    test('with no server time yet a read waits to start the clock', () async {
      final h = _harness(_server());
      await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
      await seedConversationAndKey(h);
      await _seedRow(h, disappearAfter: _day);

      await buildRepo(h).markConversationRead('g1');

      final row = await h.db.messagesDao.getMessageByServerId('srv1');
      expect(row!.expiresAt, isNull);
    });
  });

  test('a chat reopened in the same app run still purges', () async {
    final h = _harness(_server());
    await _signIn(h);
    final expiry = DateTime.now().add(const Duration(minutes: 2));
    await _seedRow(h, disappearAfter: 120, expiresAt: expiry);
    final repo = buildRepo(h);
    // First open, before expiry. The stream is then kept for the whole run.
    await repo.watchMessages('g1').first;
    expect(await h.db.messagesDao.getMessageByServerId('srv1'), isNotNull);

    _serverSays(h, expiry.add(const Duration(minutes: 1)));
    await repo.markConversationRead('g1'); // what every open and resume runs

    expect(await h.db.messagesDao.getMessageByServerId('srv1'), isNull);
  });

  test('the phone keeps no decrypted file of an expired message', () async {
    final dir = await Directory.systemTemp.createTemp('kb_purge');
    addTearDown(() => dir.delete(recursive: true));
    final expired = File('${dir.path}/expired_f_a.jpg')..writeAsStringSync('x');
    final kept = File('${dir.path}/kept_f_a.jpg')..writeAsStringSync('x');
    final h = _harness(_server(messages: const []));
    await _signIn(h);
    await _seedRow(
      h,
      id: 'expired',
      disappearAfter: _day,
      expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
    );
    await _seedRow(h, id: 'kept');
    final repo = buildRepo(h);
    for (final (id, file) in [('expired', expired), ('kept', kept)]) {
      await repo.mediaBlobStore.dao.upsert(MediaBlobTableCompanion.insert(
        blobId: '${id}_f',
        messageId: id,
        localPath: Value(file.path),
        lastAccess: DateTime.now(),
      ));
    }

    await repo.watchMessages('g1').first;
    await pumpEventQueue(times: 200);

    expect(expired.existsSync(), isFalse);
    expect(kept.existsSync(), isTrue, reason: 'ordinary media stays');
    expect(await repo.mediaBlobStore.dao.byMessageId('expired'), isEmpty);
    expect(await h.db.messagesDao.getMessageByServerId('expired'), isNull);
  });

  test('a build that went back to v13 and forward again still opens', () async {
    final dir = await Directory.systemTemp.createTemp('kb_v14_again');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/app.db';
    final running = DateTime.utc(2030, 1, 1);
    final seed = AppDatabase.forExecutor(NativeDatabase(File(path)));
    await seed.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'l1',
      serverId: const Value('srv1'),
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: 'c',
      iv: 'i',
      disappearAfter: const Value(_day),
      expiresAt: Value(running),
      createdAt: _old,
      updatedAt: _old,
    ));
    await seed.close();
    // An older build opened it: the version went back, the column stayed.
    final back = raw.sqlite3.open(path);
    back.execute('PRAGMA user_version = 13');
    back.dispose();

    final db = AppDatabase.forExecutor(NativeDatabase(File(path)));
    addTearDown(db.close);

    final row = (await db.select(db.messagesTable).get()).single;
    expect(row.disappearAfter, _day);
    expect(row.expiresAt!.toUtc(), running, reason: 'not a first upgrade');
  });

  test('upgrading to v14 clears every stamp and keeps every message', () async {
    final dir = await Directory.systemTemp.createTemp('kb_v14');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/app.db';
    final seed = AppDatabase.forExecutor(NativeDatabase(File(path)));
    await seed.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'old1',
      serverId: const Value('srvold'),
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: 'c',
      iv: 'i',
      expiresAt: Value(DateTime.utc(2026, 1, 1)),
      createdAt: _old,
      updatedAt: _old,
    ));
    await seed.close();
    final db13 = raw.sqlite3.open(path);
    db13.execute('ALTER TABLE messages_table DROP COLUMN disappear_after');
    db13.execute('PRAGMA user_version = 13');
    db13.dispose();

    final db = AppDatabase.forExecutor(NativeDatabase(File(path)));
    addTearDown(db.close);
    final rows = await db.select(db.messagesTable).get();
    expect(rows, hasLength(1));
    expect(rows.single.expiresAt, isNull);
    expect(rows.single.disappearAfter, isNull);
  });
}
