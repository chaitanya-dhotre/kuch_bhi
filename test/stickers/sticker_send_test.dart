/// Mascot §J5: a sticker is a text send whose encrypted body names it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/constants/app_strings.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import '../offline/char_harness.dart';
import '../offline/media_send_harness.dart';

Future<String> _newest(MessageRepositoryImpl repo) async =>
    (await repo.db.messagesDao.watchMessages('g1').first).first.localId;

Future<String?> _decrypt(
  MessageRepositoryImpl repo,
  String ciphertext,
  String iv,
) => repo.encryption.decryptMessage(ciphertext, iv, fixtureGroupKey);

void main() {
  setUp(bodyCache.clear);

  test('sendSticker writes a sticker row and one text_send op; the create '
      'has type sticker and a body that decrypts to "Sticker: hi"', () async {
    final (h, repo, server, _) = await mediaSendSetup();
    await repo.sendSticker(conversationId: 'g1', stickerId: 'hi');
    final id = await _newest(repo);
    final ops = await h.db.outboxDao.forConversation('g1');
    expect(ops.map((o) => o.kind), ['text_send']);

    await until(() async =>
        (await h.db.messagesDao.getMessageByLocalId(id))?.status == 'sent');
    final row = (await h.db.messagesDao.getMessageByLocalId(id))!;
    expect(row.type, 'sticker', reason: 'the ack keeps the row type');

    final body = server.createBodies.single;
    expect(body['type'], 'sticker');
    expect(
      await _decrypt(repo, body['encrypted_body'] as String, body['iv'] as String),
      'Sticker: hi',
    );
  });

  test('offline: queued, then sent on reconnect with the same id', () async {
    final (h, repo, server, _) = await mediaSendSetup();
    server.offline = true;
    await repo.sendSticker(conversationId: 'g1', stickerId: 'on-my-way');
    final id = await _newest(repo);
    final op = (await h.db.outboxDao.forConversation('g1')).single.opId;
    await repo.outboxWorker.drain();
    expect((await h.db.messagesDao.getMessageByLocalId(id))!.status, 'pending');

    server.offline = false;
    repo.outboxWorker.onConnectivityRestored();
    await until(() async =>
        (await h.db.messagesDao.getMessageByLocalId(id))?.status == 'sent');
    expect(server.createOrder, [op]);
    expect(server.messages[op]!['type'], 'sticker');
  });

  test('deleted before the ack: cancelled like a text (F-b)', () async {
    final (h, repo, server, _) = await mediaSendSetup();
    server.offline = true;
    await repo.sendSticker(conversationId: 'g1', stickerId: 'hi');
    final id = await _newest(repo);
    final op = (await h.db.outboxDao.forConversation('g1')).single.opId;
    await repo.outboxWorker.drain();

    await repo.deleteMessage(id);
    server.offline = false;
    repo.outboxWorker.onConnectivityRestored();
    await repo.outboxWorker.drain();
    expect(server.createOrder, isEmpty);
    expect(await h.db.messagesDao.getMessageByLocalId(id), isNull);
    expect(await h.db.outboxDao.byId(op), isNull);
  });

  test('a reply to a sticker carries reply_to_id and an encrypted '
      '"🍊 Sticker" preview', () async {
    final (h, repo, server, _) = await mediaSendSetup();
    await repo.sendSticker(conversationId: 'g1', stickerId: 'love');
    final parent = await _newest(repo);
    await until(() async =>
        (await h.db.messagesDao.getMessageByLocalId(parent))?.status ==
        'sent');
    final parentServerId =
        (await h.db.messagesDao.getMessageByLocalId(parent))!.serverId;

    await repo.sendMessage(
      conversationId: 'g1',
      plaintext: 'aww',
      replyToLocalId: parent,
    );
    await until(() async => server.createBodies.length == 2);
    final body = server.createBodies.last;
    expect(body['reply_to_id'], parentServerId);
    final parts = (body['reply_preview'] as String).split(':');
    expect(await _decrypt(repo, parts[1], parts[0]), kPreviewStickerLabel);
  });

  test('a pending sticker retries through the text op, never the media '
      'upload', () async {
    final (h, repo, server, _) = await mediaSendSetup();
    server.createStatus = 400; // first create refused → failed
    await repo.sendSticker(conversationId: 'g1', stickerId: 'hi');
    final id = await _newest(repo);
    await repo.outboxWorker.drain();
    await until(() async => server.createBodies.isNotEmpty);

    await repo.retryMessage(id);
    await until(() async =>
        (await h.db.messagesDao.getMessageByLocalId(id))?.status == 'sent');
    expect(server.mediaUploads, 0);
    expect(server.messages.values.single['type'], 'sticker');
  });

  test('search never returns a sticker whose body contains the query',
      () async {
    final (_, repo, _, _) = await mediaSendSetup();
    await repo.sendSticker(conversationId: 'g1', stickerId: 'hi');
    await repo.sendMessage(conversationId: 'g1', plaintext: 'hi there');
    final hits = await repo.searchMessages('g1', 'hi');
    expect(hits.map((m) => m.type), ['text']);
  });
}
