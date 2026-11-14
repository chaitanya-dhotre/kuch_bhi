/// P4 (user ruling 1): a star toggled OFFLINE must persist locally.
///
/// `messages_table.is_starred` is the media cache's protected-set input
/// (spec §media policy: protected = un-uploaded outgoing ∨ starred ∨
/// pinned) and the post-relaunch UI source. `toggleStar` must write Drift
/// BEFORE/independent of the PB sync, and that local write must keep the
/// blob eviction-safe.
///
/// This test drives the REAL repository against an offline HTTP client
/// (every PocketBase call throws) — the star must land in Drift anyway,
/// and `evictIfNeeded` must skip the starred blob while over cap.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/constants/app_constants.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/media_blob_table.dart';
import 'package:kuch_bhi/infrastructure/media/media_blob_store.dart';

import 'char_harness.dart';

void main() {
  test(
      'offline star: toggleStar (network throws) writes is_starred locally; '
      'evictIfNeeded spares the starred blob while over cap', () async {
    final offlineClient = MockClient(
      (request) async => throw http.ClientException('network down'),
    );
    final h = charHarness(clientFactory: () => offlineClient);
    addTearDown(h.close);

    await seedConversationAndKey(h);

    // Cached message WITH a serverId — the PB sync path would run online.
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'loc1',
      conversationId: 'g1',
      senderId: 'u_test',
      type: 'image',
      encryptedBody: 'x',
      iv: '',
      serverId: Value('srv1'),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ));

    final repo = buildRepo(h);

    // Star offline — must complete without throwing (PB failure is
    // best-effort/absorbed; the local write is the contract).
    await repo.toggleStar('loc1');
    var row = await h.db.messagesDao.getMessageByLocalId('loc1');
    expect(row, isNotNull);
    expect(row!.isStarred, isTrue,
        reason: 'offline star must flip is_starred in Drift — eviction '
            'protection and post-relaunch UI read this column');

    // Unstar offline flips back.
    await repo.toggleStar('loc1');
    row = await h.db.messagesDao.getMessageByLocalId('loc1');
    expect(row!.isStarred, isFalse, reason: 'offline unstar flips back');

    // Star again — the eviction proof uses the starred state.
    await repo.toggleStar('loc1');
    row = await h.db.messagesDao.getMessageByLocalId('loc1');
    expect(row!.isStarred, isTrue);

    // ── Protected-set proof: oversized cache, blob joined to srv1 ──
    //   b_f  100MiB starred(message srv1) — LRU-oldest → PROTECTED skip
    //   t_f  250MiB unprotected             — evicted → total 100 ≤ 300
    // A broken join (is_starred not written) would evict b_f → FAIL.
    final parent = await Directory.systemTemp.createTemp('star_offline_');
    addTearDown(() => parent.delete(recursive: true));
    final cacheDir = Directory('${parent.path}/media_clear')
      ..createSync(recursive: true);

    final mib = 1024 * 1024;
    await h.db.mediaBlobDao.insert(MediaBlobTableCompanion.insert(
      blobId: 'b_f',
      messageId: 'srv1',
      lastAccess: DateTime.utc(2026, 1, 1),
      state: const Value(BlobState.ready),
      bytes: Value(100 * mib),
    ));
    await h.db.mediaBlobDao.insert(MediaBlobTableCompanion.insert(
      blobId: 't_f',
      messageId: 'srv_other',
      lastAccess: DateTime.utc(2026, 1, 2),
      state: const Value(BlobState.ready),
      bytes: Value(250 * mib),
    ));

    final store = MediaBlobStore(
      dao: h.db.mediaBlobDao,
      messages: h.db.messagesDao,
      pbClient: h.pbClient,
      encryption: h.encryption,
      resolveKey: (_) async => [fixtureGroupKey],
      epoch: () => 0,
      cacheDir: () async => cacheDir,
      httpClient: offlineClient,
    );
    addTearDown(store.dispose);
    await store.ready;
    await store.evictIfNeeded();

    Future<BlobState> stateOf(String id) async =>
        (await h.db.mediaBlobDao.byId(id))!.state;
    expect(await stateOf('b_f'), BlobState.ready,
        reason: 'offline-starred message protects its blob — the eviction '
            'join reads the locally-written is_starred');
    expect(await stateOf('t_f'), BlobState.evicted,
        reason: 'unprotected tail evicted (proves the loop ran over cap '
            'and visited b_f first)');
    final total = await h.db.mediaBlobDao.readyTotalBytes();
    expect(total, lessThanOrEqualTo(kMediaCacheMaxBytes));
  });
}
