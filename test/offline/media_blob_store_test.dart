/// Task 5 — MediaBlobStore: requestBlob FSM, startup janitor, deferred
/// eviction (brief's 5 named tests).
///
/// Determinism rules:
/// - ONE [MockClient] (package:http/testing) serves both seams: it is the
///   harness `clientFactory` (PocketBase record lookups) and the store's
///   `httpClient` (file downloads). An `offline` flag throws connection
///   errors instead of responding.
/// - Real file IO in fresh `Directory.systemTemp` subdirs — no fake
///   filesystem; `cacheDir` is injected so nothing touches path_provider.
/// - `resolveKey` injected (fixture key) — the blob path never reads
///   secure storage.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/constants/app_constants.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/media_blob_table.dart';
import 'package:kuch_bhi/infrastructure/media/media_blob_store.dart';

import 'char_harness.dart';

const _jsonHeaders = {'content-type': 'application/json'};

// ── Canned PocketBase media record ────────────────────────────────────────

http.Response _recordList(Map<String, dynamic> record) => http.Response(
      jsonEncode({
        'page': 1,
        'perPage': 1,
        'totalItems': 1,
        'totalPages': 1,
        'items': [record],
      }),
      200,
      headers: _jsonHeaders,
    );

Map<String, dynamic> _mediaRecord({
  required String id,
  required String messageId,
  String file = 'blob.bin.enc',
  String fileIv = '',
  String fileName = 'blob.bin',
}) =>
    {
      'id': id,
      'collectionId': 'message_media',
      'collectionName': 'message_media',
      'created': '2026-10-07T10:00:00.000Z',
      'updated': '2026-10-07T10:00:00.000Z',
      'message_id': messageId,
      'file': file,
      'file_iv': fileIv,
      'file_name': fileName,
      'mime_type': 'image/jpeg',
      'expires_at': '',
      'duration_seconds': 0,
    };

// ── Seeds ─────────────────────────────────────────────────────────────────

Future<void> _seedBlob(
  AppDatabase db, {
  required String blobId,
  String? messageId,
  BlobState state = BlobState.queued,
  int bytes = 0,
  DateTime? lastAccess,
  String? expectedHash,
  int? expectedSize,
  String? localPath,
  bool uploadPending = false,
}) =>
    db.mediaBlobDao.insert(MediaBlobTableCompanion.insert(
          blobId: blobId,
          // `'srv1_f'` → `'srv1'`; message-id join for protection/key.
          messageId: messageId ?? blobId.split('_').first,
          lastAccess: lastAccess ?? DateTime.utc(2026, 1, 1),
          state: Value(state),
          bytes: Value(bytes),
          expectedHash: Value(expectedHash),
          expectedSize: Value(expectedSize),
          localPath: Value(localPath),
          uploadPending: Value(uploadPending),
        ));

Future<void> _seedMessage(
  AppDatabase db, {
  required String serverId,
  String conv = 'g1',
  bool starred = false,
  bool pinned = false,
}) =>
    db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
          localId: 'loc_$serverId',
          conversationId: conv,
          senderId: 'u_test',
          type: 'image',
          encryptedBody: 'x',
          iv: '',
          serverId: Value(serverId),
          isStarred: Value(starred),
          isPinned: Value(pinned),
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ));

// ── Helpers ───────────────────────────────────────────────────────────────

Future<String> _sha256Hex(List<int> bytes) async {
  final digest = await Sha256().hash(bytes);
  return digest.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

/// Builds the store under test: harness DB + injected MockClient +
/// injected temp parent dir (app-private convention: `<parent>/media_clear`).
/// [epoch] defaults to a constant session (no §11 bump); the epoch test
/// injects a mutable holder.
MediaBlobStore _store(
  CharHarness h, {
  required http.Client client,
  required Future<Directory> Function() cacheDir,
  Future<List<int>> Function(String convId)? resolveKey,
  int Function()? epoch,
}) {
  final store = MediaBlobStore(
    dao: h.db.mediaBlobDao,
    messages: h.db.messagesDao,
    pbClient: h.pbClient,
    encryption: h.encryption,
    resolveKey: resolveKey ?? (_) async => fixtureGroupKey,
    epoch: epoch ?? (() => 0),
    cacheDir: cacheDir,
    httpClient: client,
  );
  addTearDown(store.dispose);
  return store;
}

Future<Directory> _tempParent(String tag) async {
  final parent = await Directory.systemTemp.createTemp('media_blob_$tag');
  addTearDown(() => parent.delete(recursive: true));
  return parent;
}

/// Polls the row until `state == downloading` (bounded) — the brief's
/// drain sequence proof for test 1.
Future<bool> _awaitState(
  AppDatabase db,
  String blobId,
  BlobState want, {
  int tries = 400,
}) async {
  for (var i = 0; i < tries; i++) {
    final row = await db.mediaBlobDao.byId(blobId);
    if (row?.state == want) return true;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return false;
}

void main() {
  test(
      'offline → requestBlob leaves state queued; onConnectivity → drains to downloading→ready',
      () async {
    var online = false;
    final gate = Completer<void>();
    final served = utf8.encode('clear-bytes-fixture-0001');
    var fileHits = 0;

    final mock = MockClient((req) async {
      if (!online) throw http.ClientException('connection refused (offline)');
      if (req.url.path.contains('/api/collections/')) {
        return _recordList(
            _mediaRecord(id: 'mrec_srv1', messageId: 'srv1'));
      }
      if (req.url.path.contains('/api/files/')) {
        fileHits++;
        if (!gate.isCompleted) await gate.future; // hold mid-download
        return http.Response.bytes(served, 200);
      }
      return http.Response('{}', 404);
    });

    // ONE mock serves both seams: harness PocketBase (record lookups via
    // clientFactory) + store httpClient (file download).
    final h = charHarness(clientFactory: () => mock);
    addTearDown(h.close);
    final parent = await _tempParent('t1');

    await _seedBlob(
      h.db,
      blobId: 'srv1_f',
      expectedHash: await _sha256Hex(served),
    );

    final store = _store(
      h,
      client: mock,
      cacheDir: () async => parent,
    );

    // Phase 1 — offline: pipeline attempts, network throws, stays queued.
    final off = await store.requestBlob('srv1_f', 'test');
    expect(off, isNull, reason: 'offline fetch returns null (placeholder)');
    final row1 = await h.db.mediaBlobDao.byId('srv1_f');
    expect(row1!.state, BlobState.queued,
        reason: 'offline never leaves queued, never fails');
    expect(fileHits, 0);

    // Phase 2 — connectivity restored: drain queued → downloading → ready.
    online = true;
    final drain = store.onConnectivityRestored();
    final sawDownloading =
        await _awaitState(h.db, 'srv1_f', BlobState.downloading);
    expect(sawDownloading, isTrue,
        reason: 'drain must pass through the downloading state');
    gate.complete();
    await drain;

    final row2 = await h.db.mediaBlobDao.byId('srv1_f');
    expect(row2!.state, BlobState.ready);
    expect(row2.bytes, served.length);
    expect(fileHits, 1);

    final file = File('${parent.path}/media_clear/srv1_f_blob.bin');
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), 'clear-bytes-fixture-0001');
  });

  test(
      'kill mid-download: stale downloading row + orphan temp file → janitor() resets to queued and deletes temp',
      () async {
    final h = charHarness();
    addTearDown(h.close);
    final parent = await _tempParent('t2');

    final mediaCache = Directory('${parent.path}/media_clear')
      ..createSync(recursive: true);
    final orphan =
        File('${mediaCache.path}/srv1_f.part')..writeAsStringSync('partial');
    final survivor =
        File('${mediaCache.path}/srv1_f_keep.jpg')..writeAsStringSync('keep');

    // Process died mid-pipeline: row frozen in downloading.
    await _seedBlob(h.db, blobId: 'srv1_f', state: BlobState.downloading);

    final store = _store(
      h,
      client: MockClient((_) async => http.Response('{}', 500)),
      cacheDir: () async => parent,
    );
    await store.ready; // construction-time kick (nothing seeded back then)
    await store.janitor();

    final row = await h.db.mediaBlobDao.byId('srv1_f');
    expect(row!.state, BlobState.queued,
        reason: 'stale downloading resets — next drain retries');
    expect(orphan.existsSync(), isFalse,
        reason: 'orphan .part temp deleted');
    expect(survivor.existsSync(), isTrue,
        reason: 'decrypted file on disk untouched');
  });

  test(
      'eviction: seed 311MB of ready blobs → evictIfNeeded deletes only LRU unprotected; protected = uploadPending OR starred(message) OR pinned(message) survive (each VISITED while total still over cap); total after ≤ kMediaCacheMaxBytes; state becomes evicted (metadata kept)',
      () async {
    final h = charHarness();
    addTearDown(h.close);
    final parent = await _tempParent('t3');
    final mediaCache = Directory('${parent.path}/media_clear')
      ..createSync(recursive: true);

    final base = DateTime.utc(2026, 1, 1);
    DateTime at(int hours) => base.add(Duration(hours: hours));

    // I2 (fix round 1): sizes + ages are chosen so b (starred) and c
    // (pinned) are EXAMINED while the running total is STILL over
    // kMediaCacheMaxBytes, and a non-protected eviction lands AFTER each
    // skip — a broken _isProtected join would evict b/c and FAIL here.
    //   t0 E  0.5MiB uploadPending → SKIP (protected)
    //   t1 D  1KiB REAL file       → evict (file-delete proof)
    //   t2 B  100MiB starred       → SKIP while total = 311.001MiB > cap
    //   t3 M  0.5MiB               → evict AFTER the B skip (still > cap)
    //   t4 C  50MiB pinned         → SKIP while total = 310.5MiB > cap
    //   t5 T  160MiB               → evict AFTER the C skip → 150.5 ≤ cap

    // E — uploadPending, OLDEST → protected, must be SKIPPED by LRU.
    await _seedBlob(h.db, blobId: 'up1_f', state: BlobState.ready,
        bytes: 512 * 1024, lastAccess: at(0), uploadPending: true);
    // D — 1KB REAL file, next-oldest, unprotected → evicted + file deleted.
    final dFile = File('${mediaCache.path}/d1_f_pic.jpg')
      ..writeAsStringSync('x' * 1024);
    await _seedBlob(h.db, blobId: 'd1_f', state: BlobState.ready,
        bytes: 1024, lastAccess: at(1), localPath: dFile.path);
    // B — starred message → protected, visited while over cap.
    await _seedMessage(h.db, serverId: 'b1', starred: true);
    await _seedBlob(h.db, blobId: 'b1_f', messageId: 'b1',
        state: BlobState.ready,
        bytes: 100 * 1024 * 1024,
        lastAccess: at(2));
    // M — small unprotected row BETWEEN b and c: evicted after the B skip.
    await _seedBlob(h.db, blobId: 'mid_f', state: BlobState.ready,
        bytes: 512 * 1024, lastAccess: at(3));
    // C — pinned message → protected, visited while over cap.
    await _seedMessage(h.db, serverId: 'c1', pinned: true);
    await _seedBlob(h.db, blobId: 'c1_f', messageId: 'c1',
        state: BlobState.ready,
        bytes: 50 * 1024 * 1024,
        lastAccess: at(4));
    // T — big unprotected tail: evicted after the C skip, lands ≤ cap.
    await _seedBlob(h.db, blobId: 'tail_f', state: BlobState.ready,
        bytes: 160 * 1024 * 1024, lastAccess: at(5));

    final store = _store(
      h,
      client: MockClient((_) async => http.Response('{}', 500)),
      cacheDir: () async => parent,
    );
    await store.ready; // app-start trigger also runs the pass
    await store.evictIfNeeded();

    final total = await h.db.mediaBlobDao.readyTotalBytes();
    expect(total, lessThanOrEqualTo(kMediaCacheMaxBytes));

    Future<BlobState> stateOf(String id) async =>
        (await h.db.mediaBlobDao.byId(id))!.state;
    expect(await stateOf('up1_f'), BlobState.ready,
        reason: 'uploadPending protected despite being LRU-oldest');
    expect(await stateOf('b1_f'), BlobState.ready,
        reason: 'starred(message) protected — loop still OVER cap here '
            '(a broken join would have evicted it)');
    expect(await stateOf('c1_f'), BlobState.ready,
        reason: 'pinned(message) protected — loop still OVER cap here '
            '(a broken join would have evicted it)');
    expect(await stateOf('d1_f'), BlobState.evicted,
        reason: 'LRU unprotected evicted + file deleted');
    expect(await stateOf('mid_f'), BlobState.evicted,
        reason: 'non-protected evicted AFTER the starred skip '
            '(proves the loop passed b while over cap)');
    expect(await stateOf('tail_f'), BlobState.evicted,
        reason: 'non-protected evicted AFTER the pinned skip '
            '(proves the loop passed c while over cap)');
    expect(dFile.existsSync(), isFalse,
        reason: 'evicted row deletes its file');

    // Metadata kept on evicted rows (spec §9).
    final t = await h.db.mediaBlobDao.byId('tail_f');
    expect(t, isNotNull);
    expect(t!.bytes, 160 * 1024 * 1024);
    // Compare the INSTANT — drift hands DateTime back in local time while
    // the seed was UTC (Dart DateTime == also compares the utc flag).
    expect(t.lastAccess.millisecondsSinceEpoch,
        at(5).millisecondsSinceEpoch);
  });

  test(
      'dead URL → failed(dead_link); verify mismatch → failed(verify); decrypt fail → failed(decrypt) — none auto-retry',
      () async {
    final parent = await _tempParent('t4');

    final verBytes = utf8.encode('verify-target-bytes');
    // ≥16 bytes so the GCM split inside _isoDecryptBytes has ct + mac.
    final decBytes = List<int>.filled(32, 7);
    var fileHits = 0;

    final mock = MockClient((req) async {
      if (req.url.path.contains('/api/collections/')) {
        final filter = req.url.queryParameters['filter'] ?? '';
        final msgId =
            RegExp(r'message_id="([^"]+)"').firstMatch(filter)?.group(1) ?? '';
        // dec1 carries a NON-empty iv → decrypt stage must run.
        final iv = msgId == 'dec1'
            ? 'AAAAAAAAAAAAAAAAAAAAAA==' // 12 zero bytes (GCM nonce)
            : '';
        return _recordList(_mediaRecord(
            id: 'mrec_$msgId', messageId: msgId, fileIv: iv));
      }
      if (req.url.path.contains('/api/files/')) {
        fileHits++;
        if (req.url.path.contains('mrec_dead1')) {
          return http.Response('gone', 404);
        }
        if (req.url.path.contains('mrec_ver1')) {
          return http.Response.bytes(verBytes, 200);
        }
        if (req.url.path.contains('mrec_dec1')) {
          return http.Response.bytes(decBytes, 200);
        }
        return http.Response('{}', 404);
      }
      return http.Response('{}', 404);
    });

    // ONE mock serves both seams: harness PocketBase (record lookups) +
    // store httpClient (file download).
    final h = charHarness(clientFactory: () => mock);
    addTearDown(h.close);

    await _seedMessage(h.db, serverId: 'dec1'); // conversation for resolveKey
    await _seedBlob(h.db, blobId: 'dead1_f');
    await _seedBlob(h.db, blobId: 'ver1_f',
        expectedHash: await _sha256Hex(utf8.encode('different-bytes')));
    await _seedBlob(h.db, blobId: 'dec1_f');

    final store = _store(
      h,
      client: mock,
      cacheDir: () async => parent,
      resolveKey: (_) async => fixtureGroupKey,
    );

    expect(await store.requestBlob('dead1_f', 'test'), isNull);
    expect(await store.requestBlob('ver1_f', 'test'), isNull);
    expect(await store.requestBlob('dec1_f', 'test'), isNull);

    final dead = await h.db.mediaBlobDao.byId('dead1_f');
    expect(dead!.state, BlobState.failed);
    expect(dead.errorClass, 'dead_link');

    final ver = await h.db.mediaBlobDao.byId('ver1_f');
    expect(ver!.state, BlobState.failed);
    expect(ver.errorClass, 'verify');

    final dec = await h.db.mediaBlobDao.byId('dec1_f');
    expect(dec!.state, BlobState.failed);
    expect(dec.errorClass, 'decrypt');

    // Terminal: a re-request must NOT touch the network or the state.
    final hitsBefore = fileHits;
    expect(await store.requestBlob('dead1_f', 'retry'), isNull);
    expect(await store.requestBlob('ver1_f', 'retry'), isNull);
    expect(await store.requestBlob('dec1_f', 'retry'), isNull);
    expect(fileHits, hitsBefore,
        reason: 'failed is terminal — no auto-retry (spec §9)');
    expect((await h.db.mediaBlobDao.byId('dec1_f'))!.state,
        BlobState.failed);
  });

  test(
      'ready means on-disk decrypted: file exists under app-private dir (test temp dir) and is NOT ciphertext (magic bytes check)',
      () async {
    final parent = await _tempParent('t5');

    final h0 = charHarness(); // crypto seam only (no HTTP yet)
    addTearDown(h0.close);
    // Real E2E round-trip: encrypt the fixture with the fixture group key,
    // serve the CIPHERTEXT, assert the stored file is the CLEAR magic.
    final magic = utf8.encode('%PDF-1.4 clear-fixture');
    final enc = await h0.encryption.encryptBytes(magic, fixtureGroupKey);
    final cipher = base64Decode(enc.ciphertext);

    final mock = MockClient((req) async {
      if (req.url.path.contains('/api/collections/')) {
        return _recordList(_mediaRecord(
            id: 'mrec_mag1', messageId: 'mag1', fileIv: enc.iv));
      }
      if (req.url.path.contains('/api/files/')) {
        return http.Response.bytes(cipher, 200);
      }
      return http.Response('{}', 404);
    });

    final h = charHarness(clientFactory: () => mock);
    addTearDown(h.close);

    await _seedMessage(h.db, serverId: 'mag1');
    await _seedBlob(h.db, blobId: 'mag1_f');

    final store = _store(
      h,
      client: mock,
      cacheDir: () async => parent,
      resolveKey: (_) async => fixtureGroupKey,
    );

    final result = await store.requestBlob('mag1_f', 'test');
    expect(result, isNotNull);

    final row = await h.db.mediaBlobDao.byId('mag1_f');
    expect(row!.state, BlobState.ready);
    final path = row.localPath!;
    expect(path, startsWith(parent.path),
        reason: 'app-private dir convention (test temp parent)');

    final file = File(path);
    expect(await file.exists(), isTrue);
    final content = await file.readAsBytes();
    expect(content.sublist(0, magic.length), equals(magic),
        reason: 'magic bytes = decrypted plaintext');
    expect(content, isNot(equals(cipher)),
        reason: 'must NOT be ciphertext');
    expect(row.bytes, magic.length);
  });

  test(
      'spec §11 epoch guard: pipeline, janitor and evict all drop writes after a session bump (no post-logout repopulation)',
      () async {
    final gate = Completer<void>();
    final served = utf8.encode('clear-epoch-fixture');
    final mock = MockClient((req) async {
      if (req.url.path.contains('/api/collections/')) {
        return _recordList(_mediaRecord(id: 'mrec_srv1', messageId: 'srv1'));
      }
      if (req.url.path.contains('/api/files/')) {
        if (!gate.isCompleted) await gate.future; // hold mid-download
        return http.Response.bytes(served, 200);
      }
      return http.Response('{}', 404);
    });
    final h = charHarness(clientFactory: () => mock);
    addTearDown(h.close);
    final parent = await _tempParent('t6');

    var epoch = 0; // mutable holder — bump = logout / account switch
    final store = _store(
      h,
      client: mock,
      cacheDir: () async => parent,
      epoch: () => epoch,
    );
    // Drain the ctor maintenance kick FIRST — its janitor reset must not
    // race the pipeline's downloading write below.
    await store.ready;

    // ── Pipeline: bump lands while the download is gated mid-flight ──
    await _seedBlob(h.db,
        blobId: 'srv1_f', expectedHash: await _sha256Hex(served));
    final fetch = store.requestBlob('srv1_f', 'test');
    expect(await _awaitState(h.db, 'srv1_f', BlobState.downloading), isTrue,
        reason: 'pipeline must be mid-flight before the bump');
    epoch = 1; // session ends
    gate.complete();
    expect(await fetch, isNull,
        reason: 'aborted pipeline returns null, no throw');
    final row = await h.db.mediaBlobDao.byId('srv1_f');
    expect(row!.state, BlobState.downloading,
        reason: 'no FSM write after the bump (guard before temp/ready)');
    final mediaCache = Directory('${parent.path}/media_clear')
      ..createSync(recursive: true);
    expect(File('${mediaCache.path}/srv1_f_blob.bin').existsSync(), isFalse,
        reason: 'NO cleartext file written after the bump');
    expect(File('${mediaCache.path}/srv1_f.part').existsSync(), isFalse,
        reason: 'NO temp file written after the bump');

    // ── Janitor: bump lands between the entry capture and the temp
    // sweep (janitor suspends on the dao reset; the per-iteration §11
    // re-check must drop the orphan delete) ──
    final orphan =
        File('${mediaCache.path}/srv1_f.part')..writeAsStringSync('partial');
    final jan = store.janitor(); // captures epoch=1
    epoch = 2;
    await jan;
    expect(orphan.existsSync(), isTrue,
        reason: 'janitor temp delete dropped after the bump');

    // ── Evict: bump lands while the size probe is in flight ──
    final bigFile = File('${mediaCache.path}/ev1_f_big.bin')
      ..writeAsStringSync('B');
    await _seedBlob(h.db, blobId: 'ev1_f', state: BlobState.ready,
        bytes: 310 * 1024 * 1024,
        lastAccess: DateTime.utc(2026, 1, 2),
        localPath: bigFile.path);
    final ev = store.evictIfNeeded(); // captures epoch=2
    epoch = 3;
    await ev;
    expect(bigFile.existsSync(), isTrue,
        reason: 'evict file delete dropped after the bump');
    expect((await h.db.mediaBlobDao.byId('ev1_f'))!.state, BlobState.ready,
        reason: 'evicted state write dropped after the bump');
  });
}
