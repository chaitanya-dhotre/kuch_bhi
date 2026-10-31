/// Backlog (user report 2026-10-31): five messages sent quickly showed in
/// the wrong order — bubbles jumped and slowly settled. Two causes:
///  1. a pending row keeps device time; its predecessor's ack re-stamps the
///     predecessor with the LATER server time, so it overtook the still-
///     queued rows (send latency alone does it, no clock skew needed);
///  2. drift stores createdAt in whole seconds, so same-second rows fell to
///     a random-id tiebreak (random op ids, random uuid localIds).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';

import 'char_harness.dart';

void main() {
  setUp(bodyCache.clear);

  test('a burst of 5 sends never reorders while acks land one by one',
      () async {
    // Server clock 2 s ahead of the device, all five creates inside ONE
    // server second (the tiebreak case).
    final now = DateTime.now().toUtc().add(const Duration(seconds: 2));
    final serverBase = DateTime.fromMillisecondsSinceEpoch(
        now.millisecondsSinceEpoch ~/ 1000 * 1000,
        isUtc: true);
    var creates = 0;
    final h = charHarness(
      clientFactory: () => MockClient((req) async {
        if (req.url.path.startsWith('/api/realtime')) {
          return Completer<http.Response>().future;
        }
        if (req.method == 'POST' &&
            req.url.path.contains('/collections/messages/records')) {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final created = serverBase
              .add(Duration(milliseconds: 100 * creates++))
              .toIso8601String();
          return http.Response(
            jsonEncode({
              ...body,
              'collectionId': 'messages',
              'collectionName': 'messages',
              'created': created,
              'updated': created,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"message":"unhandled"}', 404);
      }),
    );
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);
    await repo.outboxWorker.onAuthPaused(true); // drain by hand below

    final sendOrder = <String>[];
    for (var i = 0; i < 5; i++) {
      await repo.sendMessage(conversationId: 'g1', plaintext: 'm$i');
      final rows = await h.db.messagesDao.watchMessages('g1').first;
      sendOrder.add(
          rows.map((r) => r.localId).firstWhere((id) => !sendOrder.contains(id)));
    }

    Future<void> expectSendOrder(String when) async {
      final rows = await h.db.messagesDao.watchMessages('g1').first;
      // watchMessages is newest-first.
      expect(rows.reversed.map((r) => r.localId).toList(), sendOrder,
          reason: when);
    }

    await expectSendOrder('right after the burst, before any ack');
    final ops = await h.db.outboxDao.forConversation('g1');
    expect(ops, hasLength(5));
    for (var i = 0; i < ops.length; i++) {
      await repo.sendOutboxOp(ops[i]);
      await expectSendOrder('after ack ${i + 1} of 5');
    }
  });
}
