/// Offline-first reactions (user, 2026-10-30): a reaction shows at once from
/// Drift, rides the outbox to the server when online, survives a cold start
/// offline, and a server read never undoes a reaction still queued.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/outbox_table.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/outbox_worker.dart'
    show kOutboxPauseKey;

import 'char_harness.dart';

/// A server that is down until [online] flips; records every request.
class _Server {
  var online = false;
  final requests = <http.Request>[];

  /// Reactions the server holds, as PocketBase JSON.
  final records = <Map<String, dynamic>>[];

  /// Status for every reaction create (null = 200).
  int? createStatus;

  /// Status for every reaction delete (null = the real answer).
  int? deleteStatus;

  /// When set, a reaction list read waits for it (a request in flight).
  Completer<void>? listGate;

  /// When set, a reaction create waits for it.
  Completer<void>? createGate;

  /// The create lands but its answer is lost (connection drops).
  var createLosesAnswer = false;

  http.Client client() => MockClient((req) async {
        if (!online) throw http.ClientException('network down');
        requests.add(req);
        final path = req.url.path;
        if (!path.startsWith('/api/collections/reactions/records')) {
          return http.Response('{}', 404);
        }
        if (req.method == 'POST') {
          await createGate?.future;
          if (createStatus != null) {
            return http.Response('{"message":"no"}', createStatus!);
          }
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          records.add({...body, 'collectionName': 'reactions'});
          if (createLosesAnswer) throw http.ClientException('connection lost');
          return _json(body);
        }
        if (req.method == 'DELETE') {
          if (deleteStatus != null) {
            return http.Response('{"message":"down"}', deleteStatus!);
          }
          final id = path.split('/').last;
          final before = records.length;
          records.removeWhere((r) => r['id'] == id);
          return before == records.length
              ? http.Response('{"message":"missing"}', 404)
              : http.Response('', 204);
        }
        if (req.method == 'GET' && path.split('/').last != 'records') {
          final id = path.split('/').last;
          final hit = records.where((r) => r['id'] == id);
          return hit.isEmpty
              ? http.Response('{"message":"missing"}', 404)
              : _json(hit.first);
        }
        await listGate?.future;
        final snapshot = [...records];
        return _json({
          'page': 1,
          'perPage': 200,
          'totalItems': snapshot.length,
          'totalPages': 1,
          'items': snapshot,
        });
      });
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _record(String id, String user, String emoji) => {
      'id': id,
      'collectionName': 'reactions',
      'message_id': 'srv1',
      'conversation_id': 'g1',
      'user_id': user,
      'emoji': emoji,
    };

Future<CharHarness> _harness(_Server server) async {
  final h = charHarness(clientFactory: server.client);
  addTearDown(h.close);
  await seedConversationAndKey(h);
  await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
    localId: 'loc1',
    conversationId: 'g1',
    senderId: 'u_other',
    type: 'text',
    encryptedBody: 'x',
    iv: '',
    serverId: const Value('srv1'),
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  ));
  return h;
}

Future<List<OutboxTableData>> _reactionOps(AppDatabase db) async =>
    (await db.outboxDao.all())
        .where((o) => o.kind.startsWith('reaction_'))
        .toList();

String _summary(List<ReactionGroup> gs) =>
    gs.map((g) => '${g.emoji}${g.count}${g.isMine ? '*' : ''}').join(' ');

void main() {
  test('offline add shows at once and queues; online drain creates it with '
      'the same id', () async {
    final server = _Server();
    final h = await _harness(server);
    final repo = buildRepo(h);

    await repo.addReaction('srv1', '👍');
    await repo.outboxWorker.drain(); // offline: the try fails → backoff
    expect(_summary(await repo.watchReactions('srv1').first), '👍1*');
    final ops = await _reactionOps(h.db);
    expect(ops.map((o) => o.kind), ['reaction_add']);
    expect(ops.single.state, OutboxState.queued);

    // What the app does when the connection comes back.
    server.online = true;
    repo.outboxWorker.onConnectivityRestored();
    await repo.outboxWorker.drain();
    final mine = (await repo.watchReactions('srv1').first).single;
    expect(server.records.single['id'], mine.reactionId,
        reason: 'the local id is the server id: a retry cannot duplicate');
    expect(server.records.single['emoji'], '👍');
    expect(server.records.single['user_id'], 'u_test');
    expect((await _reactionOps(h.db)).single.state, OutboxState.sent);
  });

  test('a reaction made offline survives a cold start offline', () async {
    final server = _Server();
    final h = await _harness(server);
    await buildRepo(h).addReaction('srv1', '❤️');

    final relaunched = buildRepo(h);
    expect(_summary(await relaunched.watchReactions('srv1').first), '❤️1*');
  });

  test('tapping the same emoji again removes it; before it was sent, '
      'nothing reaches the server', () async {
    final server = _Server();
    final h = await _harness(server);
    final repo = buildRepo(h);

    // Hold the worker so the add is never tried before the undo.
    await h.db.settingsDao.setSetting(kOutboxPauseKey, 'test');
    await repo.addReaction('srv1', '😂');
    await repo.addReaction('srv1', '😂');
    expect(await repo.watchReactions('srv1').first, isEmpty);
    expect(await _reactionOps(h.db), isEmpty, reason: 'the add was cancelled');

    await h.db.settingsDao.setSetting(kOutboxPauseKey, '');
    server.online = true;
    await repo.outboxWorker.drain();
    expect(server.requests, isEmpty);
  });

  test('removing a sent reaction offline hides it and queues a delete; '
      'a 404 on that delete counts as done', () async {
    final server = _Server()..online = true;
    final h = await _harness(server);
    final repo = buildRepo(h);
    await repo.addReaction('srv1', '👍');
    await repo.outboxWorker.drain();
    final id = (await repo.watchReactions('srv1').first).single.reactionId!;

    server.online = false;
    await repo.removeReaction(id);
    expect(await repo.watchReactions('srv1').first, isEmpty);

    server.records.clear(); // someone already deleted it server-side
    server.online = true;
    await repo.outboxWorker.drain();
    final ops = await _reactionOps(h.db);
    expect(ops.map((o) => (o.kind, o.state)), [
      ('reaction_add', OutboxState.sent),
      ('reaction_remove', OutboxState.sent),
    ]);
  });

  test('a server read keeps queued reactions and drops stale ones', () async {
    final server = _Server();
    final h = await _harness(server);
    final repo = buildRepo(h);

    // Queued offline: my ❤️ (not on the server yet).
    await repo.addReaction('srv1', '❤️');
    // A stale local row the server no longer has.
    await h.db.into(h.db.reactionsTable).insert(ReactionsTableCompanion.insert(
          id: 'gone',
          messageLocalId: 'loc1',
          conversationId: 'g1',
          userId: 'u_x',
          emoji: '🔥',
          createdAt: DateTime.utc(2026, 1, 2),
        ));

    server.records.add(_record('r_other', 'u_other', '❤️'));
    server.online = true;
    await repo.refreshReactions('srv1');
    expect(_summary(await repo.watchReactions('srv1').first), '❤️2*');
  });

  test('a server read does not bring back a reaction whose delete is queued',
      () async {
    final server = _Server()..online = true;
    final h = await _harness(server);
    final repo = buildRepo(h);
    await repo.addReaction('srv1', '👍');
    await repo.outboxWorker.drain();
    final id = (await repo.watchReactions('srv1').first).single.reactionId!;

    // The delete can't get through (5xx = backoff), so it stays queued
    // while the server still has the row.
    server.deleteStatus = 503;
    await repo.removeReaction(id);
    await repo.outboxWorker.drain();
    await repo.refreshReactions('srv1');
    expect(await repo.watchReactions('srv1').first, isEmpty);
    expect(server.records, isNotEmpty, reason: 'the delete really is queued');
  });

  test('a reaction the server refuses is dropped and never blocks the chat',
      () async {
    final server = _Server()
      ..online = true
      ..createStatus = 403;
    final h = await _harness(server);
    final repo = buildRepo(h);

    await repo.addReaction('srv1', '👍');
    await repo.outboxWorker.drain();
    expect(await repo.watchReactions('srv1').first, isEmpty);
    expect(await _reactionOps(h.db), isEmpty,
        reason: 'a failedTerminal head would stall every later send in g1');
    final stuck = (await h.db.outboxDao.all())
        .where((o) => o.state == OutboxState.failedTerminal);
    expect(stuck, isEmpty);
  });

  test('refresh offline leaves the local rows alone', () async {
    final server = _Server();
    final h = await _harness(server);
    final repo = buildRepo(h);
    await repo.addReaction('srv1', '🎉');
    await repo.refreshReactions('srv1'); // must not throw
    expect(_summary(await repo.watchReactions('srv1').first), '🎉1*');
  });

  test('a reaction added while a server read is in flight survives it',
      () async {
    final server = _Server()..online = true;
    final h = await _harness(server);
    final repo = buildRepo(h);
    // Hold my create so the add stays pending through the whole read.
    server.createGate = Completer<void>();
    server.listGate = Completer<void>();

    final refresh = repo.refreshReactions('srv1'); // read starts, is held
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await repo.addReaction('srv1', '👍'); // lands during the read
    server.listGate!.complete(); // the read answers without it
    await refresh;
    expect(_summary(await repo.watchReactions('srv1').first), '👍1*');

    server.createGate!.complete();
    await repo.outboxWorker.drain();
    expect(server.records.map((r) => r['emoji']), ['👍'],
        reason: 'the add still reaches the server');
  });

  test('a reaction removed while a server read is in flight stays removed',
      () async {
    final server = _Server()..online = true;
    final h = await _harness(server);
    final repo = buildRepo(h);
    await repo.addReaction('srv1', '👍');
    await repo.outboxWorker.drain();
    final id = (await repo.watchReactions('srv1').first).single.reactionId!;

    server.deleteStatus = 503; // the delete stays queued
    server.listGate = Completer<void>();
    final refresh = repo.refreshReactions('srv1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await repo.removeReaction(id);
    server.listGate!.complete(); // the read still has the row
    await refresh;
    expect(await repo.watchReactions('srv1').first, isEmpty);
  });

  test('undo after the add was sent (but not acked) queues a delete, '
      'never a silent cancel', () async {
    final server = _Server()..online = true;
    final h = await _harness(server);
    final repo = buildRepo(h);
    server.createGate = Completer<void>();

    await repo.addReaction('srv1', '❤️');
    final drain = repo.outboxWorker.drain(); // the create is in flight
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final id = (await repo.watchReactions('srv1').first).single.reactionId!;
    await repo.removeReaction(id);
    server.createGate!.complete();
    await drain;
    await repo.outboxWorker.drain();
    expect(server.records, isEmpty, reason: 'the server ends without it');
  });

  test('an add retried after a lost answer counts as done (400 on own id)',
      () async {
    final server = _Server()..online = true;
    final h = await _harness(server);
    final repo = buildRepo(h);
    await repo.addReaction('srv1', '🔥');
    final id = (await repo.watchReactions('srv1').first).single.reactionId!;
    // The first create reached the server, its answer was lost.
    server.records.add(_record(id, 'u_test', '🔥'));
    server.createStatus = 400;
    await repo.outboxWorker.drain();
    expect((await _reactionOps(h.db)).single.state, OutboxState.sent);
    expect(_summary(await repo.watchReactions('srv1').first), '🔥1*');
  });

  test("a server read after logout writes nothing into the next session's db",
      () async {
    final server = _Server()..online = true;
    final h = await _harness(server);
    final repo = buildRepo(h);
    server.records.add(_record('r_old', 'u_other', '👍'));
    server.listGate = Completer<void>();
    final refresh = repo.refreshReactions('srv1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    h.pbClient.pb.authStore.clear(); // signed out mid-read
    server.listGate!.complete();
    await refresh;
    final rows = await h.db.select(h.db.reactionsTable).get();
    expect(rows, isEmpty);
  });

  test('undo after a create whose answer was lost queues a delete', () async {
    final server = _Server()
      ..online = true
      ..createLosesAnswer = true;
    final h = await _harness(server);
    final repo = buildRepo(h);
    await repo.addReaction('srv1', '👍');
    await repo.outboxWorker.drain(); // lands, answer lost → backoff, queued
    final add = (await _reactionOps(h.db)).single;
    expect((add.state, add.attempts > 0), (OutboxState.queued, true));

    final id = (await repo.watchReactions('srv1').first).single.reactionId!;
    await repo.removeReaction(id);
    expect((await _reactionOps(h.db)).map((o) => o.kind),
        ['reaction_add', 'reaction_remove'],
        reason: 'the server may hold it: cancelling would leave it there');
  });
}
