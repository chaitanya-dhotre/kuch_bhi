import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:kuch_bhi/services/encryption_service.dart';

import 'char_harness.dart'; // buildRepo + seedConversationAndKey live here

/// A MockClient answering the ONLY URL the cold path hits
/// (`…/collections/messages/records`) with a PocketBase list envelope whose
/// single record carries the fields `_cacheMessagesBatch` reads.
///
/// CORRECTION vs the brief: `/api/realtime` hangs (never completes) instead
/// of falling into the 404 branch. The repo constructor schedules a 500ms
/// SSE reconnect; pocketbase's SseClient RETRIES a 404 forever on
/// 200–2000ms timers, which would keep firing after the test ends.
MockClient fetchListClient({
  required EncryptResult enc,
  required String conversationId,
}) =>
    MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future; // SSE hangs, never 404s
      }
      if (!req.url.path.contains('/collections/messages/records')) {
        return http.Response('{"message":"unhandled"}', 404);
      }
      return http.Response(
        jsonEncode({
          'page': 1, 'perPage': 40, 'totalItems': 1, 'totalPages': 1,
          'items': [{
            'id': 'srv1',
            'collectionId': 'messages', 'collectionName': 'messages',
            'created': '2026-10-07T10:00:00.000Z',
            'updated': '2026-10-07T10:00:00.000Z',
            'fields': {},
            'conversation_id': conversationId, 'sender_id': 'u_peer',
            'type': 'text', 'encrypted_body': enc.ciphertext, 'iv': enc.iv,
            'reply_to_id': '', 'reply_preview': '',
            'is_deleted_for_everyone': false, 'is_deleted_for_me': false,
            'is_pinned': false, 'is_starred': false,
            'status': 'sent', 'media_id': '',
          }],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

void main() {
  test('char: send persists optimistic pending row before the network ack', () async {
    final h = charHarness(clientFactory: () => MockClient(
        (req) => Completer<http.Response>().future)); // never completes
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);

    // ignore: unused_local_variable — intentionally never awaited (see below)
    final send = repo.sendMessage(conversationId: 'g1', plaintext: 'hello');
    await Future<void>.delayed(const Duration(milliseconds: 50)); // let enqueue land
    final rows = await h.db.messagesDao.watchMessages('g1').first;
    expect(rows, hasLength(1), reason: 'optimistic row exists pre-ack');
    expect(rows.first.status, 'pending');
    expect(rows.first.decryptedBody, 'hello'); // Task 9 drops this column by design
    // send is still pending on purpose — never awaited here
  });

  test('char: cold watchMessages with key fetches, decrypts and caches', () async {
    final pre = charHarness(); // throwaway: only to encrypt with the fixture key
    addTearDown(pre.close);
    final enc = await pre.encryption.encryptMessage('hello from server', fixtureGroupKey);

    final h2 = charHarness(clientFactory: () => fetchListClient(enc: enc, conversationId: 'g1'));
    addTearDown(h2.close);
    await seedConversationAndKey(h2, withKey: true); // group_key_g1 = fixtureGroupKey
    final repo = buildRepo(h2);

    final rows = await repo.watchMessages('g1').first; // cold path awaits fetch
    expect(rows, isNotEmpty);
    expect(rows.first.decryptedBody, 'hello from server',
        reason: 'ciphertext decrypted at cache-write, row visible');
  });

  test('char: cold watchMessages with key MISSING skips cache (defect pinned — Task 7 flips)',
      () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc = await pre.encryption.encryptMessage('lost key', fixtureGroupKey);

    final h2 = charHarness(clientFactory: () => fetchListClient(enc: enc, conversationId: 'g1'));
    addTearDown(h2.close);
    await seedConversationAndKey(h2, withKey: false); // group_key_g1 absent
    final repo = buildRepo(h2);

    final rows = await repo.watchMessages('g1').first;
    expect(rows, isEmpty,
        reason: 'CHAR: pins the :2484 skip defect; Task 7 flips this expectation in its own commit');
  });
}
