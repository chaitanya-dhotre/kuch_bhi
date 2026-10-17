import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';

import 'char_harness.dart'; // buildRepo + seedConversationAndKey

/// F2a (2026-10-14 idle-cascade fix): the resume delta is inclusive
/// (`created >= cursor`), so EVERY resume refetches each conversation's
/// boundary row. The old ingest path re-decrypted and re-wrote that row
/// through IngestBoundary (delete-by-serverId + insert) even when nothing
/// changed — dirtying messages_table, re-firing watchMessages, and paying
/// a per-conversation key resolve on every focus return (measured: 18
/// convs / ~15s cascade per notification-shade pull on M52).
///
/// Contract pinned here:
/// A. an unchanged row that is already locally RESOLVED (ready /
///    device_sealed) is a NO-OP on refetch: no row write (updatedAt
///    frozen), no stream emission, no key-resolve hop — while the sync
///    cursor still advances past it;
/// B. a row that is NOT yet resolved (key_missing / pending / failed)
///    still takes the old path on refetch — resume remains a retry
///    opportunity;
/// C. a record whose server-side payload changed (deletion flag, body,
///    pin, …) still lands — the diff must never swallow real updates.

/// Mutable messages-list feed: the same record can be re-served with
/// server-side mutations between fetches.
class MessagesFeed {
  bool deletedForEveryone = false;
  bool pinned = false;
  String encryptedBody = '';
  String iv = '';
}

MockClient messagesListClient({
  required MessagesFeed feed,
  required String conversationId,
}) =>
    MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future; // SSE hangs, never 404s
      }
      if (req.url.path.contains('/collections/group_keys/records')) {
        return http.Response('{"message":"not found"}', 404);
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
            // Non-zero ms on purpose: PocketBase stamps always carry
            // milliseconds while drift stores created_at at SECOND
            // granularity — a naive equality made every real row look
            // "changed" (the .000Z fixtures passed while M52 rewrote all
            // 21 convs on 2026-10-14). Compare at second precision.
            'created': '2026-10-07T10:00:00.123Z',
            'updated': '2026-10-07T10:00:00.123Z',
            'fields': {},
            'conversation_id': conversationId, 'sender_id': 'u_peer',
            'type': 'text', 'encrypted_body': feed.encryptedBody,
            'iv': feed.iv,
            'reply_to_id': '', 'reply_preview': '',
            'is_deleted_for_everyone': feed.deletedForEveryone,
            'is_deleted_for_me': false,
            'is_pinned': feed.pinned, 'is_starred': false,
            'status': 'sent', 'media_id': '',
          }],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

/// Drain-drift helper: counts messages_table stream CHANGES (the initial
/// snapshot from a fresh listener is skipped).
({StreamSubscription sub, int Function() emissions}) watchChanges(
    CharHarness h, String convId) {
  var count = 0;
  final sub = h.db.messagesDao.watchMessages(convId).skip(1).listen((_) {
    count++;
  });
  return (sub: sub, emissions: () => count);
}

void main() {
  test(
      'A: refetch of an unchanged ready row neither rewrites nor emits '
      '(cursor-only commit)', () async {
    final pre = charHarness(); // throwaway: only to encrypt with the fixture key
    addTearDown(pre.close);
    final enc =
        await pre.encryption.encryptMessage('stable body', fixtureGroupKey);

    final feed = MessagesFeed()
      ..encryptedBody = enc.ciphertext
      ..iv = enc.iv;
    final h = charHarness(
        clientFactory: () =>
            messagesListClient(feed: feed, conversationId: 'g1'));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    final repo = buildRepo(h);

    // Cold fetch → row lands ready.
    final cold = await repo.watchMessages('g1').first;
    expect(cold, hasLength(1));
    final localId = cold.first.localId;
    expect(
        (await h.db.messagesDao.getMessageByLocalId(localId))!.decryptState,
        'ready');
    final updatedAt0 =
        (await h.db.messagesDao.getMessageByLocalId(localId))!.updatedAt;

    // Change watcher armed AFTER the cold fetch's own writes. The 1.1s
    // settle guarantees a rewrite (updatedAt = now, second-granularity
    // storage) could not land in the same second as updatedAt0.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final watch = watchChanges(h, 'g1');
    addTearDown(watch.sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // Warm refetch: a second subscription runs the warm branch's
    // _fetchAndCacheMessages (unawaited) with the SAME record.
    await repo.watchMessages('g1').first;
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final row = await h.db.messagesDao.getMessageByLocalId(localId);
    expect(row!.updatedAt.millisecondsSinceEpoch,
        updatedAt0.millisecondsSinceEpoch,
        reason: 'unchanged ready row must NOT be rewritten — the rewrite '
            'is what dirties messages_table on every resume');
    expect(watch.emissions(), 0,
        reason: 'no drift emission for an unchanged row — the emission '
            'storm is the visible "messages refresh" on focus return');
    expect(row.decryptState, 'ready');
  });

  test(
      'B: an unresolved (key_missing) row still takes the retry path on '
      'refetch', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc =
        await pre.encryption.encryptMessage('later readable', fixtureGroupKey);

    final feed = MessagesFeed()
      ..encryptedBody = enc.ciphertext
      ..iv = enc.iv;
    final h = charHarness(
        clientFactory: () =>
            messagesListClient(feed: feed, conversationId: 'g1'));
    addTearDown(h.close);
    // No local key on the cold fetch → row lands key_missing.
    await seedConversationAndKey(h, withKey: false);
    final repo = buildRepo(h);

    // The repo stream HIDES unresolved group rows (isGroupRowVisible), so
    // the DAO is the state oracle; the repo call is only the fetch trigger.
    await repo.watchMessages('g1').first;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final coldRows = await h.db.messagesDao.watchMessages('g1').first;
    expect(coldRows, hasLength(1), reason: 'precondition: row ingested');
    final coldId = coldRows.first.localId;
    expect(
        coldRows.first.decryptState,
        anyOf('key_missing', 'pending'),
        reason: 'precondition: unresolved without a key');

    // Key arrives (e.g. background refresh / later hydrate). C: write-through
    // API required — the cold fetch already loaded the key memory, so a raw
    // storage.put would be invisible to reads.
    await h.encryption.saveGroupKey('g1', fixtureGroupKey);

    await repo.watchMessages('g1').first; // warm refetch = retry opportunity
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final row = (await h.db.messagesDao.getMessageByLocalId(coldId))!;
    expect(row.decryptState, 'ready',
        reason: 'resume refetch must keep retrying unresolved rows');
    expect(bodyCache.get(coldId), 'later readable');
  });

  test(
      'C: a server-side payload change (deletion flag) still lands on '
      'refetch', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc = await pre.encryption.encryptMessage('doomed', fixtureGroupKey);

    final feed = MessagesFeed()
      ..encryptedBody = enc.ciphertext
      ..iv = enc.iv;
    final h = charHarness(
        clientFactory: () =>
            messagesListClient(feed: feed, conversationId: 'g1'));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    final repo = buildRepo(h);

    final cold = await repo.watchMessages('g1').first;
    final coldId = cold.first.localId;
    expect(
        (await h.db.messagesDao.getMessageByLocalId(coldId))!
            .isDeletedForEveryone,
        isFalse);

    feed.deletedForEveryone = true; // server-side delete between fetches
    await repo.watchMessages('g1').first;
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final row = (await h.db.messagesDao.getMessageByLocalId(coldId))!;
    expect(row.isDeletedForEveryone, isTrue,
        reason: 'the no-op diff must never swallow a real server change');
  });
}
