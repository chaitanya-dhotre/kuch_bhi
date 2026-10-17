import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drift/drift.dart' show Value;
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';

import 'char_harness.dart';

/// F2b (2026-10-14): every focus return used to run the FULL resync —
/// conversations sync + per-conversation backfill for ALL memberships
/// (measured: 18 convs / ~15s per notification-shade pull on M52). SSE
/// has no replay, so a resume MUST still discover messages that arrived
/// while away — but one aggregate `created >= <local-watermark>` query
/// can pick the target set instead of scanning every conversation.
///
/// Contract pinned here:
/// A. short resume (< 60s away): ONE aggregate delta query; per-conversation
///    backfill runs ONLY for conversations whose aggregate rows are not
///    already durable locally — a no-change shade return does ZERO
///    per-conv message fetches;
/// B. short resume with a genuinely new server row: that row's
///    conversation IS backfilled (badge/data recovery on shade return);
/// C. full resume (null away = cold start, or ≥ 60s): every membership is
///    backfilled exactly as before — the gate never shrinks the long path.

class ResyncFeed {
  /// Records per-conversation message fetches
  /// (`filter` contains `conversation_id=`).
  final perConv = <String>[];

  /// Records aggregate delta queries (`filter` contains `created >=`).
  var aggregate = 0;

  /// Records the `page` parameter of every aggregate delta query.
  final aggregatePages = <int>[];

  /// Records conversation-members list syncs (`filter` contains `user_id=`).
  var memberSyncs = 0;

  /// Records served message records for BOTH query shapes.
  List<Map<String, dynamic>> newRows = [];

  /// Bound to by tests: full-record list for per-conv fetches.
  List<Map<String, dynamic>> perConvRecords = [];

  /// Rows the aggregate query returns (boundary + new).
  List<Map<String, dynamic>> aggregateRecords = [];

  /// Server star flags (starred_messages sync).
  final starredIds = <String>{};

  /// Server deleted-for-me flags (deleted_messages_for_me sync).
  final deletedIds = <String>{};
}

MockClient resyncClient(ResyncFeed feed) => MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future; // SSE hangs, never 404s
      }
      http.Response envelope(List<Map<String, dynamic>> items) =>
          http.Response(
            jsonEncode({
              'page': 1, 'perPage': 40, 'totalItems': items.length,
              'totalPages': 1, 'items': items,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );

      if (req.url.path.contains('/collections/starred_messages/records')) {
        return envelope([
          for (final id in feed.starredIds) {'message_id': id},
        ]);
      }
      if (req.url.path.contains('/collections/deleted_messages_for_me/records')) {
        return envelope([
          for (final id in feed.deletedIds) {'message_id': id},
        ]);
      }
      // C2 receipt reconcile: the only OWN message in this file is
      // srv_r1 (C2b) — everything else is u_peer's and never queries.
      if (req.url.path.contains('/collections/message_receipts/records')) {
        return envelope([
          {
            'message_id': 'srv_r1',
            'recipient_id': 'u_peer',
            'delivered_at': '2026-10-07T10:01:00.000Z',
            'read_at': '2026-10-07T10:01:05.000Z',
          },
        ]);
      }
      if (req.url.path.contains('/collections/conversation_members/records')) {
        final filter = req.url.queryParameters['filter'] ?? '';
        if (filter.contains('user_id=')) {
          feed.memberSyncs++;
          return envelope(const []); // no server memberships → sync loop idle
        }
        return http.Response('{"message":"not found"}', 404);
      }
      if (req.url.path.contains('/collections/messages/records')) {
        final filter = req.url.queryParameters['filter'] ?? '';
        if (filter.contains('conversation_id=')) {
          final conv = RegExp(r'conversation_id="([^"]+)"').firstMatch(filter);
          feed.perConv.add(conv?.group(1) ?? '?');
          return envelope(feed.perConvRecords);
        }
        if (filter.contains('created >=')) {
          feed.aggregate++;
          final page =
              int.tryParse(req.url.queryParameters['page'] ?? '1') ?? 1;
          feed.aggregatePages.add(page);
          final start = (page - 1) * 100;
          final slice = start >= feed.aggregateRecords.length
              ? const <Map<String, dynamic>>[]
              : feed.aggregateRecords.sublist(
                  start,
                  start + 100 > feed.aggregateRecords.length
                      ? feed.aggregateRecords.length
                      : start + 100,
                );
          return envelope(slice);
        }
        return http.Response('{"message":"unhandled messages query"}', 404);
      }
      return http.Response('{"message":"unhandled"}', 404);
    });

Map<String, dynamic> msgRecord({
  required String id,
  required String conversationId,
  required String created,
  required String encryptedBody,
  required String iv,
}) =>
    {
      'id': id,
      'collectionId': 'messages', 'collectionName': 'messages',
      'created': created,
      'updated': created,
      'fields': {},
      'conversation_id': conversationId, 'sender_id': 'u_peer',
      'type': 'text', 'encrypted_body': encryptedBody, 'iv': iv,
      'reply_to_id': '', 'reply_preview': '',
      'is_deleted_for_everyone': false, 'is_deleted_for_me': false,
      'is_pinned': false, 'is_starred': false,
      'status': 'sent', 'media_id': '',
    };

void main() {
  test(
      'A: short resume (<60s), no new server rows → one aggregate query, '
      'zero per-conversation fetches', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc =
        await pre.encryption.encryptMessage('old row', fixtureGroupKey);

    final feed = ResyncFeed();
    final h = charHarness(clientFactory: () => resyncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_old',
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: enc.ciphertext,
      iv: enc.iv,
      serverId: const Value('srv_old'),
      decryptState: const Value('ready'),
      createdAt: DateTime.utc(2026, 10, 7, 10),
      updatedAt: DateTime.utc(2026, 10, 7, 10),
    ));

    final repo = buildRepo(h);
    await repo.resyncOnResume(awayFor: const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(feed.memberSyncs, greaterThanOrEqualTo(1),
        reason: 'membership sync still runs on the light path');
    expect(feed.aggregate, 1,
        reason: 'light path runs exactly one aggregate delta query');
    expect(feed.perConv, isEmpty,
        reason: 'no new server rows → zero per-conversation fetches');
    final row = await h.db.messagesDao.getMessageByLocalId('m_old');
    expect(row, isNotNull, reason: 'local row untouched');
  });

  test(
      'B: short resume backfills the conversation whose row is genuinely '
      'new on the server', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final oldEnc =
        await pre.encryption.encryptMessage('old row', fixtureGroupKey);
    final newEnc =
        await pre.encryption.encryptMessage('fresh row', fixtureGroupKey);

    final feed = ResyncFeed();
    final h = charHarness(clientFactory: () => resyncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_old',
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: oldEnc.ciphertext,
      iv: oldEnc.iv,
      serverId: const Value('srv_old'),
      decryptState: const Value('ready'),
      createdAt: DateTime.utc(2026, 10, 7, 10),
      updatedAt: DateTime.utc(2026, 10, 7, 10),
    ));

    // Aggregate sees boundary (srv_old) + a genuinely new row (srv_new);
    // the per-conv fetch serves the full record set for g1.
    feed.aggregateRecords = [
      msgRecord(
        id: 'srv_new',
        conversationId: 'g1',
        created: '2026-10-07T12:00:00.000Z',
        encryptedBody: newEnc.ciphertext,
        iv: newEnc.iv,
      ),
      msgRecord(
        id: 'srv_old',
        conversationId: 'g1',
        created: '2026-10-07T10:00:00.000Z',
        encryptedBody: oldEnc.ciphertext,
        iv: oldEnc.iv,
      ),
    ];
    feed.perConvRecords = feed.aggregateRecords;

    final repo = buildRepo(h);
    await repo.resyncOnResume(awayFor: const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(feed.perConv, ['g1'],
        reason: 'the conv with a new server row is backfilled');
    final rows = await h.db.messagesDao.watchMessages('g1').first;
    expect(rows, hasLength(2), reason: 'new row ingested on shade return');
    final fresh = rows.firstWhere((r) => r.serverId == 'srv_new');
    expect(fresh.decryptState, 'ready');
    expect(bodyCache.get(fresh.localId), 'fresh row');
  });

  test(
      'C: full resume (cold start, awayFor null) still backfills every '
      'membership', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc = await pre.encryption.encryptMessage('old row', fixtureGroupKey);

    final feed = ResyncFeed();
    final h = charHarness(clientFactory: () => resyncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_old',
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: enc.ciphertext,
      iv: enc.iv,
      serverId: const Value('srv_old'),
      decryptState: const Value('ready'),
      createdAt: DateTime.utc(2026, 10, 7, 10),
      updatedAt: DateTime.utc(2026, 10, 7, 10),
    ));
    feed.perConvRecords = [
      msgRecord(
        id: 'srv_old',
        conversationId: 'g1',
        created: '2026-10-07T10:00:00.000Z',
        encryptedBody: enc.ciphertext,
        iv: enc.iv,
      ),
    ];

    final repo = buildRepo(h);
    await repo.resyncOnResume(); // cold-start shape: no awayFor
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(feed.perConv, contains('g1'),
        reason: 'full path backfills memberships regardless of deltas');
    expect(feed.aggregate, 0,
        reason: 'full path does not run the aggregate delta query');
  });

  test(
      'C2: resume away ≥ 60s takes the full path too', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc = await pre.encryption.encryptMessage('old row', fixtureGroupKey);

    final feed = ResyncFeed();
    final h = charHarness(clientFactory: () => resyncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_old',
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: enc.ciphertext,
      iv: enc.iv,
      serverId: const Value('srv_old'),
      decryptState: const Value('ready'),
      createdAt: DateTime.utc(2026, 10, 7, 10),
      updatedAt: DateTime.utc(2026, 10, 7, 10),
    ));
    feed.perConvRecords = [
      msgRecord(
        id: 'srv_old',
        conversationId: 'g1',
        created: '2026-10-07T10:00:00.000Z',
        encryptedBody: enc.ciphertext,
        iv: enc.iv,
      ),
    ];

    final repo = buildRepo(h);
    await repo.resyncOnResume(awayFor: const Duration(seconds: 120));
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(feed.perConv, contains('g1'),
        reason: '≥60s away → full backfill path');
    expect(feed.aggregate, 0);
  });

  test(
      'D: star sync does not rewrite a row that is ALREADY starred '
      '(idle no-op — the unconditional updatedAt bump dirtied drift on '
      'every resume)', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc = await pre.encryption.encryptMessage('star me', fixtureGroupKey);

    final feed = ResyncFeed()..starredIds.add('srv_star');
    final h = charHarness(clientFactory: () => resyncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_star',
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: enc.ciphertext,
      iv: enc.iv,
      serverId: const Value('srv_star'),
      decryptState: const Value('ready'),
      isStarred: const Value(true), // already starred locally
      createdAt: DateTime.utc(2026, 10, 7, 10),
      updatedAt: DateTime.utc(2026, 10, 7, 10),
    ));
    feed.perConvRecords = [
      msgRecord(
        id: 'srv_star',
        conversationId: 'g1',
        created: '2026-10-07T10:00:00.123Z',
        encryptedBody: enc.ciphertext,
        iv: enc.iv,
      ),
    ];
    final before = (await h.db.messagesDao.getMessageByLocalId('m_star'))!
        .updatedAt
        .millisecondsSinceEpoch;

    final repo = buildRepo(h);
    await repo.resyncOnResume(); // full path → per-conv fetch → star sync
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final after = (await h.db.messagesDao.getMessageByLocalId('m_star'))!;
    expect(after.isStarred, isTrue);
    expect(after.updatedAt.millisecondsSinceEpoch, before,
        reason: 'already-starred row must not be rewritten by star sync');
  });

  test(
      'E: deleted-for-me sync does not rewrite a row ALREADY flagged '
      '(idle no-op)', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc = await pre.encryption.encryptMessage('gone', fixtureGroupKey);

    final feed = ResyncFeed()..deletedIds.add('srv_gone');
    final h = charHarness(clientFactory: () => resyncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_gone',
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: enc.ciphertext,
      iv: enc.iv,
      serverId: const Value('srv_gone'),
      decryptState: const Value('ready'),
      isDeletedForMe: const Value(true), // already flagged locally
      createdAt: DateTime.utc(2026, 10, 7, 10),
      updatedAt: DateTime.utc(2026, 10, 7, 10),
    ));
    feed.perConvRecords = [
      msgRecord(
        id: 'srv_gone',
        conversationId: 'g1',
        created: '2026-10-07T10:00:00.123Z',
        encryptedBody: enc.ciphertext,
        iv: enc.iv,
      ),
    ];
    final before = (await h.db.messagesDao.getMessageByLocalId('m_gone'))!
        .updatedAt
        .millisecondsSinceEpoch;

    final repo = buildRepo(h);
    await repo.resyncOnResume();
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final after = (await h.db.messagesDao.getMessageByLocalId('m_gone'))!;
    expect(after.isDeletedForMe, isTrue);
    expect(after.updatedAt.millisecondsSinceEpoch, before,
        reason: 'already-flagged row must not be rewritten by delete sync');
  });

  test(
      'C4: delta discovery paginates — a conv whose new rows fall past '
      'the first 100 aggregate rows is still backfilled', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc =
        await pre.encryption.encryptMessage('old row', fixtureGroupKey);

    final feed = ResyncFeed();
    // Page 1 (100 rows): copies of the ALREADY-DURABLE boundary row —
    // unchanged, so none are actionable. Page 2 (20 rows): genuinely new
    // rows for a SECOND conversation that a single-page probe never sees.
    feed.aggregateRecords = [
      for (var i = 0; i < 100; i++)
        msgRecord(
          id: 'srv_old',
          conversationId: 'g1',
          created: '2026-10-07T10:00:00.123Z',
          encryptedBody: enc.ciphertext,
          iv: enc.iv,
        ),
      for (var i = 0; i < 20; i++)
        msgRecord(
          id: 'srv_g2_$i',
          conversationId: 'g2',
          created: '2026-10-07T10:05:${(i % 60).toString().padLeft(2, '0')}.000Z',
          encryptedBody: enc.ciphertext,
          iv: enc.iv,
        ),
    ];

    final h = charHarness(clientFactory: () => resyncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_old',
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: enc.ciphertext,
      iv: enc.iv,
      serverId: const Value('srv_old'),
      decryptState: const Value('ready'),
      createdAt: DateTime.utc(2026, 10, 7, 10),
      updatedAt: DateTime.utc(2026, 10, 7, 10),
    ));

    final repo = buildRepo(h);
    await repo.resyncOnResume(awayFor: const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(feed.aggregatePages, contains(2),
        reason: 'a full first page (100 rows) must trigger page 2 — '
            'target discovery is capped at perPage otherwise');
    expect(feed.perConv, contains('g2'),
        reason: 'rows past row 100 still yield an actionable target');
  });

  test(
      'C2a: light resume with ZERO delta still reconciles starred + '
      'deleted-for-me flags via USER-scoped queries (quiet convs were '
      'skipped until chat-open or a ≥60s full resume)', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc =
        await pre.encryption.encryptMessage('quiet', fixtureGroupKey);

    final feed = ResyncFeed()
      ..starredIds.add('srv_s1')
      ..deletedIds.add('srv_d1');
    final h = charHarness(clientFactory: () => resyncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_s1',
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: enc.ciphertext,
      iv: enc.iv,
      serverId: const Value('srv_s1'),
      decryptState: const Value('ready'),
      createdAt: DateTime.utc(2026, 10, 7, 10),
      updatedAt: DateTime.utc(2026, 10, 7, 10),
    ));
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_d1',
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: enc.ciphertext,
      iv: enc.iv,
      serverId: const Value('srv_d1'),
      decryptState: const Value('ready'),
      createdAt: DateTime.utc(2026, 10, 7, 11),
      updatedAt: DateTime.utc(2026, 10, 7, 11),
    ));
    // aggregateRecords stays empty ⇒ zero actionable rows ⇒ (before the
    // fix) zero per-conv fetches ⇒ the per-conv syncs never ran.

    final repo = buildRepo(h);
    await repo.resyncOnResume(awayFor: const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(feed.perConv, isEmpty,
        reason: 'C2: quiet convs must be covered WITHOUT per-conv fetches');
    final s = (await h.db.messagesDao.getMessageByLocalId('m_s1'))!;
    expect(s.isStarred, isTrue,
        reason: 'user-scoped starred sync must flip quiet-conv rows on '
            'the light path');
    final d = (await h.db.messagesDao.getMessageByLocalId('m_d1'))!;
    expect(d.isDeletedForMe, isTrue,
        reason: 'user-scoped deleted-for-me sync must flip quiet-conv '
            'rows on the light path');
  });

  test(
      'C2b: light resume reconciles receipt ticks for OWN messages in '
      'conversations with no new rows (user-scoped)', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc =
        await pre.encryption.encryptMessage('tick me', fixtureGroupKey);

    final feed = ResyncFeed();
    final h = charHarness(clientFactory: () => resyncClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_own',
      conversationId: 'g1',
      senderId: 'u_test',
      type: 'text',
      encryptedBody: enc.ciphertext,
      iv: enc.iv,
      serverId: const Value('srv_r1'),
      decryptState: const Value('ready'),
      status: const Value('sent'),
      createdAt: DateTime.utc(2026, 10, 7, 10),
      updatedAt: DateTime.utc(2026, 10, 7, 10),
    ));

    final repo = buildRepo(h);
    await repo.resyncOnResume(awayFor: const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final row = (await h.db.messagesDao.getMessageByLocalId('m_own'))!;
    expect(row.status, 'read',
        reason: 'C2: receipt reconcile must run on the light path — '
            'server says u_peer read srv_r1');
  });
}
