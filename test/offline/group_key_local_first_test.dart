import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/decrypt/decrypt_pass.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';

import 'char_harness.dart';

/// Loading-issue root cause (2026-10-13): every chat open rendered 🔒+bar
/// for ~1–5s because the DISPLAY decrypt path
/// (`DecryptPass.runFor → _resolveKeys → getOrFetchGroupKeyCandidates`)
/// was network-first for any logged-in user — it awaited a blocking
/// `group_keys.getFullList` per conversation, sequentially, even though
/// every key was already in secure storage (measured: runFor 4704ms for
/// 9 rows, `localCached=2` on every call).
///
/// Contract pinned here:
/// A. local candidates + non-`requireCurrent` caller → returns WITHOUT
///    waiting on the network (this is the 1–5s fix);
/// B. `requireCurrent: true` (send/outbox) still contacts the server and
///    still refuses to silently send under a stale cache (existing
///    invariant — regression pin);
/// C. the local-first path still schedules a background server
///    revalidation (rotation freshness is not sacrificed);
/// D. when that background revalidation brings a NEW key version, rows
///    the stale set could not open are re-queued and re-run (rotation
///    edge: messages arrived while the app was closed).

// ── helpers ────────────────────────────────────────────────────────────

http.Response _envelope(List<Map<String, dynamic>> items) => http.Response(
      jsonEncode({
        'page': 1,
        'perPage': 30,
        'totalItems': items.length,
        'totalPages': 1,
        'items': items,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

/// Mutable group_keys server feed — set [SyncFeed.items] before triggering
/// a fetch (mirrors the removal_reconcile test's SyncFeed pattern).
class SyncFeed {
  List<Map<String, dynamic>> items = [];
  final List<String> recorded = [];
  Duration delay = Duration.zero;
}

/// Realtime hangs (never 404s — pocketbase's SseClient retries a 404
/// forever); `group_keys` answers from [feed]; everything else 404s.
MockClient keyClient(SyncFeed feed, {bool hangGroupKeys = false}) =>
    MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (req.url.path.contains('/collections/group_keys/records')) {
        feed.recorded.add(req.url.toString());
        if (hangGroupKeys) return Completer<http.Response>().future;
        if (feed.delay != Duration.zero) {
          await Future<void>.delayed(feed.delay);
        }
        return _envelope(feed.items);
      }
      return http.Response('{"message":"unhandled"}', 404);
    });

Future<void> _waitUntil(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 5),
  String what = 'condition',
}) async {
  final sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) {
      fail('timed out after ${timeout.inMilliseconds}ms waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// One envelope record carrying [encryptedKey] for key_version [version],
/// expanded with an `encrypted_by_user_id` record whose `public_key` is
/// [adminPub] — the exact shape `getOrFetchGroupKeyCandidates` reads.
Map<String, dynamic> _gkRecord({
  required String encryptedKey,
  required int version,
  required String adminPub,
}) =>
    {
      'id': 'gk_v$version',
      'collectionId': 'group_keys',
      'collectionName': 'group_keys',
      'created': '2026-10-13T10:00:00.000Z',
      'updated': '2026-10-13T10:00:00.000Z',
      'fields': {},
      'conversation_id': 'g1',
      'user_id': 'u_test',
      'key_version': version,
      'encrypted_key': encryptedKey,
      'encrypted_by_user_id': 'admin1',
      'expand': {
        'encrypted_by_user_id': [
          {
            'id': 'admin1',
            'collectionId': 'users',
            'collectionName': 'users',
            'created': '2026-10-13T10:00:00.000Z',
            'updated': '2026-10-13T10:00:00.000Z',
            'fields': {},
            'username': 'admin',
            'public_key': adminPub,
          },
        ],
      },
    };

void main() {
  setUp(bodyCache.clear);

  test('A: local candidates + decrypt path return WITHOUT waiting on network',
      () async {
    final feed = SyncFeed();
    final h = charHarness(clientFactory: () => keyClient(feed, hangGroupKeys: true));
    addTearDown(h.close);
    h.storage.put('group_key_g1', base64.encode(fixtureGroupKey));

    // Plain .timeout: pre-fix this THROWS TimeoutException (network await).
    final cands =
        await h.encryption.getOrFetchGroupKeyCandidates('g1', 'u_test')
            .timeout(const Duration(seconds: 1));

    expect(cands, isNotEmpty, reason: 'cached key must satisfy the decrypt path');
    expect(cands.first, fixtureGroupKey);
  });

  test(
      'B: requireCurrent (send path) still hits the server and still refuses '
      'a stale-cache send when the server returns nothing',
      () async {
    final feed = SyncFeed(); // items = [] → empty 200
    final h = charHarness(clientFactory: () => keyClient(feed));
    addTearDown(h.close);
    h.storage.put('group_key_g1', base64.encode(fixtureGroupKey));

    await expectLater(
      h.encryption.getOrFetchGroupKey('g1', 'u_test'),
      throwsA(isA<dynamic>()),
      reason: 'empty server response must NOT fall back to the stale cache',
    );
    expect(feed.recorded, hasLength(1),
        reason: 'send path must contact the server despite a local cache');
  });

  test('C: local-first return still schedules a background revalidation',
      () async {
    final feed = SyncFeed()..delay = const Duration(milliseconds: 400);
    final h = charHarness(clientFactory: () => keyClient(feed));
    addTearDown(h.close);
    h.storage.put('group_key_g1', base64.encode(fixtureGroupKey));

    final sw = Stopwatch()..start();
    final cands =
        await h.encryption.getOrFetchGroupKeyCandidates('g1', 'u_test')
            .timeout(const Duration(seconds: 1));
    expect(cands, isNotEmpty);
    // ignore: avoid_print
    print('PERF local_first_group_key_ms=${sw.elapsedMilliseconds}');
    expect(sw.elapsedMilliseconds, lessThan(300),
        reason: 'return must not include network time');

    // The refresh fired unawaited — it must REACH the network.
    await _waitUntil(() => feed.recorded.isNotEmpty,
        what: 'background revalidation request');
  });

  test(
      'D: background refresh bringing a new key re-opens rows the stale set '
      'could not (rotation-while-closed edge)', () async {
    final feed = SyncFeed();
    final h = charHarness(clientFactory: () => keyClient(feed));
    addTearDown(h.close);
    await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
    await seedConversationAndKey(h, withKey: false);

    // MY keypair (auto-generated once, stored in the harness storage).
    final myPub = await h.encryption.getPublicKeyBase64();
    final key1 = h.encryption.generateGroupKey(); // stale local key
    final key2 = h.encryption.generateGroupKey(); // server-only new key
    h.storage.put('group_key_g1', base64.encode(key1));
    h.storage.put('group_key_g1_1', base64.encode(key1));

    // Envelope for key2: encrypt side derives ECDH(myPriv, memberPub=myPub),
    // decrypt side derives ECDH(myPriv, adminPub=myPub) — self-consistent.
    final env = await h.encryption.encryptGroupKeyForMember(key2, myPub, 'g1');
    feed.items = [
      _gkRecord(encryptedKey: env, version: 2, adminPub: myPub),
    ];

    // Cold-ingest row: ciphertext under key2, only key1 local, state
    // 'pending' (what _ingestDecryptState writes when keys were present
    // but the body did not open).
    final cipher = await h.encryption.encryptMessage('rotated text', key2);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_rot',
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: cipher.ciphertext,
      iv: cipher.iv,
      serverId: const Value('srv_m_rot'),
      decryptState: const Value('pending'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ));

    final pass = DecryptPass(db: h.db, enc: h.encryption, epoch: () => 0);
    await pass.runFor(['m_rot']); // stale key1 only → cannot open key2 row

    // The background refresh must land the v2 key, re-queue the row and
    // re-run it — the bubble resolves without reopening the chat.
    await _waitUntil(() => bodyCache.get('m_rot') == 'rotated text',
        what: 'row re-opened after background key refresh');
    final row = await h.db.messagesDao.getMessageByLocalId('m_rot');
    expect(row?.decryptState, 'ready');
    expect(feed.recorded, isNotEmpty, reason: 'refresh contacted group_keys');
  });

  // ── D1: readiness banner (groupKeyReadyProvider) local-first ─────────
  //
  // The "Waiting for a group admin…" composer gate polled
  // `hasUsableKey → getOrFetchGroupKey(requireCurrent)` — a BLOCKING
  // network-first call per 3s poll, so a cold-process open showed the
  // banner even with a warm local key set (M52 cold-open probe,
  // 2026-10-13).

  test('D1: hasUsableKey satisfied by local cache WITHOUT waiting on network',
      () async {
    final feed = SyncFeed();
    final h =
        charHarness(clientFactory: () => keyClient(feed, hangGroupKeys: true));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);

    final repo = buildRepo(h);
    // Plain .timeout: pre-fix this THROWS TimeoutException (blocking
    // requireCurrent network call against a hanging server).
    final ok =
        await repo.hasUsableKey('g1').timeout(const Duration(seconds: 1));

    expect(ok, isTrue,
        reason: 'warm local key must clear the readiness gate without a '
            'group_keys round-trip');
  });

  test('D1-negative: no local key + empty server → false (server contacted)',
      () async {
    final feed = SyncFeed(); // items = [] → empty 200
    final h = charHarness(clientFactory: () => keyClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: false);

    final repo = buildRepo(h);
    final ok = await repo.hasUsableKey('g1');

    expect(ok, isFalse,
        reason: 'join-accepted-but-no-key-yet must still show the banner');
    expect(feed.recorded, hasLength(1),
        reason: 'cold cache must contact the server');
  });

  // ── D2: app-start prefetch — chat-open never pays the network ────────
  //
  // Colds (fresh install / pm-clear / never-opened convs) previously
  // hydrated keys ONLY at chat open (the video's 1–4s lock window).
  // Prefetch runs after every conversation sync and fills any group whose
  // key set is not yet resident.

  test(
      'D2: prefetchGroupKeys hydrates a cold group-key cache from the server',
      () async {
    final feed = SyncFeed();
    final h = charHarness(clientFactory: () => keyClient(feed));
    addTearDown(h.close);
    await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
    await seedConversationAndKey(h, withKey: false);

    // Self-consistent ECDH envelope (test D's trick): encrypt side derives
    // ECDH(myPriv, memberPub=myPub), decrypt side ECDH(myPriv, adminPub).
    final myPub = await h.encryption.getPublicKeyBase64();
    final key = h.encryption.generateGroupKey();
    final env = await h.encryption.encryptGroupKeyForMember(key, myPub, 'g1');
    feed.items = [
      _gkRecord(encryptedKey: env, version: 1, adminPub: myPub),
    ];

    final repo = buildRepo(h);
    await repo.prefetchGroupKeys();

    var hydrated = false;
    for (var i = 0; i < 100 && !hydrated; i++) {
      hydrated = await h.encryption.hasLocalGroupKey('g1');
      if (!hydrated) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    expect(hydrated, isTrue, reason: 'prefetched local group key');
    expect(feed.recorded, isNotEmpty, reason: 'cold prefetch contacted server');
  });

  test('D2-skip: prefetch with a warm local cache makes NO network call',
      () async {
    final feed = SyncFeed();
    final h = charHarness(clientFactory: () => keyClient(feed));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);

    final repo = buildRepo(h);
    await repo.prefetchGroupKeys();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(h.storage.readAllCalls, 1,
        reason: 'warm-group scan must use one secure-storage readAll');
    expect(await h.encryption.hasLocalGroupKey('g1'), isTrue);
    expect(feed.recorded, isEmpty,
        reason: 'warm convs must be skipped — prefetch never re-fetches');
  });
}
