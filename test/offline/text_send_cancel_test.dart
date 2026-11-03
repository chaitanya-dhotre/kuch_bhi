/// F-b (multi-select follow-up): a text the outbox has not sent yet and that
/// the user deletes never goes out, and its bubble stays gone:
///  - deleted while queued (offline): no create ever reaches the server;
///  - deleted while the create is in flight: the late ack never shows it and
///    the server copy is marked deleted for everyone;
///  - a failed text deleted no longer blocks the chat's later sends;
///  - the texts around it keep their order (burst-order guard, fb2fd2c).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/tables/outbox_table.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import 'char_harness.dart';
import 'media_send_harness.dart';

Future<String> _send(MessageRepositoryImpl repo, String text) async {
  final before = await repo.db.messagesDao.watchMessages('g1').first;
  await repo.sendMessage(conversationId: 'g1', plaintext: text);
  final rows = await repo.db.messagesDao.watchMessages('g1').first;
  return rows
      .map((r) => r.localId)
      .firstWhere((id) => !before.any((b) => b.localId == id));
}

Future<String> _opFor(CharHarness h, String localId) async =>
    (await h.db.outboxDao.forConversation('g1'))
        .firstWhere((o) => o.ref == localId)
        .opId;

Future<List<String>> _oldestFirst(CharHarness h) async =>
    (await h.db.messagesDao.watchMessages('g1').first)
        .reversed
        .map((r) => r.localId)
        .toList();

void main() {
  setUp(bodyCache.clear);

  test('deleted while queued offline: never sent, the bubble stays gone, and '
      'the texts around it still send in order', () async {
    final (h, repo, server, _) = await mediaSendSetup();
    server.offline = true;
    final a = await _send(repo, 'first');
    final b = await _send(repo, 'oops');
    final c = await _send(repo, 'third');
    final opA = await _opFor(h, a);
    final opB = await _opFor(h, b);
    final opC = await _opFor(h, c);
    await repo.outboxWorker.drain();

    await repo.deleteMessage(b); // what the menu does for an unsent row
    expect(await _oldestFirst(h), [a, c]);

    server.offline = false;
    repo.outboxWorker.onConnectivityRestored();
    await until(() async =>
        (await h.db.messagesDao.getMessageByLocalId(c))?.status == 'sent');
    await repo.outboxWorker.drain();

    expect(server.createOrder, [opA, opC], reason: 'the deleted text never left');
    expect(server.messages.containsKey(opB), isFalse);
    expect(await h.db.messagesDao.getMessageByLocalId(b), isNull);
    expect(await h.db.outboxDao.byId(opB), isNull, reason: 'op cleaned up');
    expect(await _oldestFirst(h), [a, c], reason: 'burst order holds');
  });

  test('deleted while its create is in flight: the late ack never shows it, '
      'the server copy is marked deleted for everyone', () async {
    final (h, repo, server, _) = await mediaSendSetup();
    server.createGate = Completer<void>();
    final id = await _send(repo, 'oops');
    final op = await _opFor(h, id);
    await until(() async => server.createBodies.isNotEmpty);

    await repo.deleteMessage(id);
    expect(await h.db.messagesDao.watchMessages('g1').first, isEmpty);

    server.createGate!.complete();
    await until(() async =>
        server.messages[op]?['is_deleted_for_everyone'] == true,
        reason: 'receivers never keep the deleted text');
    await repo.outboxWorker.drain();
    expect(await h.db.messagesDao.watchMessages('g1').first, isEmpty);
    expect(await h.db.messagesDao.getMessageByLocalId(id), isNull);
    expect(await h.db.outboxDao.byId(op), isNull);
  });

  test('in flight, then offline when the ack lands: a page fetch keeps it '
      'hidden and the mark is retried on reconnect', () async {
    final (h, repo, server, _) = await mediaSendSetup();
    server.createGate = Completer<void>();
    final id = await _send(repo, 'oops');
    final op = await _opFor(h, id);
    await until(() async => server.createBodies.isNotEmpty);

    await repo.deleteMessage(id);
    server.offline = true; // the create lands; the mark after it fails
    server.createGate!.complete();
    await until(() async => server.messages.containsKey(op));
    await repo.outboxWorker.drain();
    expect(server.messages[op]!['is_deleted_for_everyone'], isFalse);

    server.offline = false;
    await repo.loadMoreMessages('g1', 0); // the unmarked copy comes back
    expect(await h.db.messagesDao.watchMessages('g1').first, isEmpty,
        reason: 'no second, visible row for the deleted text');

    repo.outboxWorker.onConnectivityRestored();
    await until(() async =>
        server.messages[op]!['is_deleted_for_everyone'] == true);
    await repo.outboxWorker.drain();
    expect(await h.db.messagesDao.watchMessages('g1').first, isEmpty);
    expect(await h.db.outboxDao.byId(op), isNull);
  });

  test('deleted after a lost ack (created, phone never heard): the retry '
      'marks the server copy instead of sending', () async {
    final (h, repo, server, _) = await mediaSendSetup();
    server.loseMessageAck = true;
    final id = await _send(repo, 'oops');
    final op = await _opFor(h, id);
    await until(() async => server.messages.containsKey(op));
    await repo.outboxWorker.drain();

    await repo.deleteMessage(id);
    repo.outboxWorker.onConnectivityRestored(); // retry now, not after backoff
    await until(() async =>
        server.messages[op]!['is_deleted_for_everyone'] == true);
    await repo.outboxWorker.drain();
    expect(server.createOrder, [op], reason: 'never created a second time');
    expect(await h.db.messagesDao.getMessageByLocalId(id), isNull);
  });

  test('deleting a failed text frees the queue for the next send', () async {
    final (h, repo, server, _) = await mediaSendSetup();
    server.offline = true;
    final bad = await _send(repo, 'refused');
    final opBad = await _opFor(h, bad);
    await repo.outboxWorker.drain();
    await h.db.outboxDao.setState(opBad, OutboxState.failedTerminal);
    await h.db.messagesDao.updateMessageStatus(bad, 'failed');

    await repo.deleteMessage(bad);
    server.offline = false;
    final next = await _send(repo, 'next');
    await until(() async =>
        (await h.db.messagesDao.getMessageByLocalId(next))?.status == 'sent',
        reason: 'a deleted failed text must not block the chat');
    expect(await h.db.outboxDao.byId(opBad), isNull);
    expect(server.messages.containsKey(opBad), isFalse);
  });

  test('deleted in flight, then the server refuses the create: the chat\'s '
      'next send still goes', () async {
    final (h, repo, server, _) = await mediaSendSetup();
    server.createGate = Completer<void>();
    server.createStatus = 400;
    final id = await _send(repo, 'oops');
    final op = await _opFor(h, id);
    await until(() async => server.createBodies.isNotEmpty);

    await repo.deleteMessage(id);
    final gate = server.createGate!;
    server.createGate = null;
    gate.complete(); // the create is answered 400
    await until(() async =>
        (await h.db.outboxDao.byId(op))?.state != OutboxState.sending);
    await repo.outboxWorker.drain();
    final next = await _send(repo, 'next');
    await until(() async =>
        (await h.db.messagesDao.getMessageByLocalId(next))?.status == 'sent',
        reason: 'the refused, deleted text must not block the chat');
    expect(await h.db.outboxDao.byId(op), isNull);
    expect(await h.db.messagesDao.getMessageByLocalId(id), isNull);
  });

  test('an ack after the delete (duplicate-id retry) leaves the op unsent, '
      'so a restart still marks the server copy', () async {
    final (h, repo, server, _) = await mediaSendSetup();
    server.offline = true;
    final id = await _send(repo, 'oops');
    final op = await _opFor(h, id);
    await repo.outboxWorker.drain();
    await repo.deleteMessage(id);

    await repo.handleDrainAck(op,
        serverId: op, senderId: 'u_test', conversationId: 'g1');
    expect((await h.db.outboxDao.byId(op))!.state, isNot(OutboxState.sent),
        reason: 'a sent op is never revisited');
    expect((await h.db.messagesDao.getMessageByLocalId(id))!.status,
        'cancelled');
  });

  test('deleted for me after the ack: the normal delete, receivers keep it',
      () async {
    final (h, repo, server, _) = await mediaSendSetup();
    final id = await _send(repo, 'hello');
    final op = await _opFor(h, id);
    await until(() async =>
        (await h.db.messagesDao.getMessageByLocalId(id))?.status == 'sent');

    await repo.deleteMessage(id);
    final row = (await h.db.messagesDao.getMessageByLocalId(id))!;
    expect(row.isDeletedForMe, isTrue);
    expect(server.marks, isEmpty);
    expect(server.messages[op]!['is_deleted_for_everyone'], isFalse);
  });
}
