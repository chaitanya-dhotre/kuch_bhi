/// C1 (adversarial review #72, 2026-10-17): `maxServerCreatedAt` is the
/// F2 light-resume watermark and its contract is "device clock never
/// participates" — but two writers attach `serverId` while keeping the
/// DEVICE-clock `createdAt`:
///   1. media ack Step D (message_repository_impl ~:1723);
///   2. drain-ack duplicate-create recovery (serverId stamped, createdAt
///      left at the optimistic enqueue time).
/// With a device ahead of the PocketBase VM, the watermark then excludes
/// every server-stamped row and quick resumes silently miss messages
/// (SSE has no replay). Pin: BOTH writers stamp the SERVER `created`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kuch_bhi/data/local/database/app_database.dart';

import 'char_harness.dart';

/// Fixed server time, far from any device clock — if the row carries this,
/// it came from the ack record, not DateTime.now().
const _serverCreated = '2020-02-02T02:02:02.000Z';

Map<String, dynamic> _pbRecord({
  required String id,
  required String created,
  Map<String, dynamic> extra = const {},
}) =>
    {
      'id': id,
      'collectionId': 'messages',
      'collectionName': 'messages',
      'created': created,
      'updated': created,
      'fields': <String, dynamic>{},
      ...extra,
    };

http.Response _json(Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

/// Serves the media-send flow: messages.create (Step B), the
/// message_media.create upload (Step C). SSE hangs.
MockClient _mediaClient() => MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (req.method == 'POST' &&
          req.url.path.contains('/collections/messages/records')) {
        return _json(_pbRecord(id: 'srv_media', created: _serverCreated));
      }
      if (req.method == 'POST' &&
          req.url.path.contains('/collections/message_media/records')) {
        return _json(_pbRecord(
          id: 'med_1',
          created: _serverCreated,
          extra: {'collectionId': 'message_media', 'collectionName': 'message_media'},
        ));
      }
      return http.Response('{"message":"unhandled ${req.url}"}', 404);
    });

/// Serves the duplicate-create recovery: GET messages/srv_dup → an owned
/// record stamped at server time.
MockClient _dupClient() => MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (req.url.path.contains('/collections/messages/records/srv_dup')) {
        return _json(_pbRecord(
          id: 'srv_dup',
          created: _serverCreated,
          extra: {'sender_id': 'u_test', 'conversation_id': 'g1'},
        ));
      }
      return http.Response('{"message":"unhandled ${req.url}"}', 404);
    });

void main() {
  test(
      'C1a: media ack stamps the SERVER created — watermark stays '
      'server-time even when the device clock leads', () async {
    final h = charHarness(clientFactory: _mediaClient);
    addTearDown(h.close);
    await seedConversationAndKey(h);

    final tmp = File(
        '${Directory.systemTemp.path}/kb_c1a_${DateTime.now().microsecondsSinceEpoch}.txt')
      ..writeAsStringSync('payload');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync();
    });

    await buildRepo(h).sendMediaMessage(
      conversationId: 'g1',
      mediaType: 'document',
      mediaFile: tmp,
    );

    // Upload runs unawaited in the background — poll for the acked row.
    MessagesTableData? acked;
    for (var i = 0; i < 60; i++) {
      final rows = await h.db.messagesDao.watchMessages('g1').first;
      for (final r in rows) {
        if (r.serverId != null) acked = r;
      }
      if (acked != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(acked, isNotNull, reason: 'media ack (Step D) must land');
    expect(acked!.createdAt.toUtc(), DateTime.parse(_serverCreated).toUtc(),
        reason: 'C1 — Step D stamps record.created, never DateTime.now()');

    final watermark = await h.db.messagesDao.maxServerCreatedAt();
    expect(watermark!.toUtc(), DateTime.parse(_serverCreated).toUtc(),
        reason: 'the F2 light watermark must stay server-time only');
  });

  test(
      'C1b: duplicate-create recovery (drain-ack) stamps the SERVER created '
      'before the serverId lands', () async {
    final h = charHarness(clientFactory: _dupClient);
    addTearDown(h.close);
    await seedConversationAndKey(h);

    // Optimistic enqueue row: device-clock createdAt, no serverId yet.
    final deviceNow = DateTime.now().toUtc();
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_dup',
      conversationId: 'g1',
      senderId: 'u_test',
      type: 'text',
      encryptedBody: 'x',
      iv: 'y',
      createdAt: deviceNow,
      updatedAt: deviceNow,
    ));
    await h.db.outboxDao.enqueue(OutboxTableCompanion.insert(
      opId: 'srv_dup',
      kind: 'message_send',
      ref: 'm_dup',
      conversationId: 'g1',
      seq: 1,
      createdAt: deviceNow,
    ));

    final ok = await buildRepo(h).resolveDuplicateSend(
      opId: 'srv_dup',
      senderId: 'u_test',
      conversationId: 'g1',
    );
    expect(ok, isTrue, reason: 'owned duplicate resolves as a drain-ack');

    final row = (await h.db.messagesDao.getMessageByLocalId('m_dup'))!;
    expect(row.serverId, 'srv_dup');
    expect(row.createdAt.toUtc(), DateTime.parse(_serverCreated).toUtc(),
        reason: 'C1 — recovery stamps record.created, never device time');

    final watermark = await h.db.messagesDao.maxServerCreatedAt();
    expect(watermark!.toUtc(), DateTime.parse(_serverCreated).toUtc(),
        reason: 'the F2 light watermark must stay server-time only');
  });
}
