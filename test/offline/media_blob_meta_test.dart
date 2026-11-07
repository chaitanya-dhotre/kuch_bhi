/// Media send C2/C3/C5: the blob row keeps the media's metadata (schema
/// v12), so a cache hit after a restart still knows size, expiry, type,
/// real name and video length (smell 9, backlog 13.4); `registerLocal`
/// files the sender's copy; logout wipes it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/media_blob_table.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/video_message_bubble.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';
import 'package:kuch_bhi/infrastructure/media/media_blob_store.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

import 'char_harness.dart';

const _expires = '2026-12-30T10:00:00.000Z';

MockClient _server() => MockClient((req) async {
      if (req.url.path.contains('/collections/message_media/records') &&
          req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'page': 1,
            'perPage': 1,
            'totalItems': 1,
            'totalPages': 1,
            'items': [
              {
                'id': 'med1',
                'collectionId': 'message_media',
                'collectionName': 'message_media',
                'created': '2026-10-07T10:00:00.000Z',
                'updated': '2026-10-07T10:00:00.000Z',
                'message_id': 'vid1',
                'thumbnail': 'thumb.jpg.enc',
                'thumb_iv': '', // legacy plaintext: no decrypt in this test
                'file_name': 'clip.mp4',
                'mime_type': 'video/mp4',
                'expires_at': _expires,
                'duration_seconds': 12,
                'video_width': 720,
                'video_height': 1280,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (req.url.path.endsWith('/thumb.jpg.enc')) {
        return http.Response.bytes(List<int>.filled(64, 7), 200);
      }
      return http.Response('{}', 404);
    });

MediaBlobStore _store(CharHarness h, Directory parent) {
  final store = MediaBlobStore(
    dao: h.db.mediaBlobDao,
    messages: h.db.messagesDao,
    pbClient: h.pbClient,
    encryption: h.encryption,
    resolveKey: (_) async => fixtureGroupKey,
    epoch: () => 0,
    cacheDir: () async => parent,
    httpClient: _server(),
  );
  addTearDown(store.dispose);
  return store;
}

Future<Directory> _parent() async {
  final d = await Directory.systemTemp.createTemp('blob_meta');
  addTearDown(() => d.delete(recursive: true));
  return d;
}

void main() {
  test('schema v11 → v12 keeps blob rows, meta null, user_version 12',
      () async {
    final dir = await _parent();
    final file = File('${dir.path}/kuch_bhi.sqlite');
    final before = raw.sqlite3.open(file.path);
    before.execute(_kV11MediaBlobCreate);
    before.execute(
      "INSERT INTO media_blob_table (blob_id, message_id, local_path, bytes, "
      "last_access, state, upload_pending) VALUES "
      "('srv1_t','srv1','/x/srv1_t_a.jpg',64,1760000000,'ready',0)",
    );
    before.execute('PRAGMA user_version = 11');
    before.dispose();

    final db = AppDatabase.forExecutor(NativeDatabase(file));
    final rows = await db.select(db.mediaBlobTable).get();
    expect(rows, hasLength(1));
    expect(rows.single.blobId, 'srv1_t');
    expect(rows.single.state, BlobState.ready);
    expect(rows.single.meta, isNull);
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.data.values.first, 14);
    await db.close();
  });

  test('ready write stores meta; after a restart the fast path returns it, '
      'with the real name', () async {
    final h = charHarness(clientFactory: _server);
    addTearDown(h.close);
    final parent = await _parent();

    final first = await _store(h, parent).requestBlob('vid1_t', 'test');
    expect(first!.durationSeconds, 12);
    final row = await h.db.mediaBlobDao.byId('vid1_t');
    expect(jsonDecode(row!.meta!), {
      'width': 720,
      'height': 1280,
      'durationSeconds': 12,
      'expiresAt': _expires,
      'mimeType': 'video/mp4',
      'fileName': 'clip.mp4',
    });

    // A new store = an app restart (mediaFileProvider is per session).
    final again = await _store(h, parent).requestBlob('vid1_t', 'restart');
    expect(again!.file.path, first.file.path);
    expect(again.width, 720);
    expect(again.height, 1280);
    expect(again.durationSeconds, 12);
    expect(again.expiresAt, DateTime.parse(_expires).toLocal());
    expect(again.mimeType, 'video/mp4');
    expect(again.fileName, 'clip.mp4', reason: 'no vid1_t_ prefix');
  });

  group('13.4', () {
    // Real async (the store's startup work cannot run in testWidgets' fake
    // zone): warm the blob, then read it through a fresh store = a restart.
    late LocalMediaFile cached;
    late CharHarness h;
    late Directory parent;
    setUpAll(() async {
      h = charHarness(clientFactory: _server);
      parent = await Directory.systemTemp.createTemp('blob_meta_134');
      await _store(h, parent).requestBlob('vid1_t', 'warm');
      cached = (await _store(h, parent).requestBlob('vid1_t', 'restart'))!;
    });
    tearDownAll(() async {
      await h.close();
      await parent.delete(recursive: true);
    });

    testWidgets('a video bubble over a cached thumb shows its length, not '
        '0:00', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          mediaFileProvider.overrideWith((ref, r) => cached),
          mediaFullLocalProvider.overrideWith((ref, r) => Stream.value(null)),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const Scaffold(
            body: Center(
              child: VideoMessageBubble(
                  conversationId: 'g1',
                  serverId: 'vid1',
                  isMine: false,
                  isDark: false),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(find.text('0:12'), findsOneWidget);
      expect(find.text('0:00'), findsNothing);
    });
  });

  test('registerLocal moves the file under media_clear as a ready blob',
      () async {
    final h = charHarness();
    addTearDown(h.close);
    final parent = await _parent();
    final src = File('${parent.path}/img_1.jpg')..writeAsBytesSync([1, 2, 3]);
    final meta = mediaMetaJson(LocalMediaFile(file: src, width: 4, height: 3,
        fileName: 'img_1.jpg'));

    final moved = await _store(h, parent).registerLocal(
        blobId: 'abc_f', file: src, meta: meta, uploadPending: true);

    expect(moved!.path, '${parent.path}/media_clear/abc_f_img_1.jpg');
    expect(src.existsSync(), isFalse);
    final row = (await h.db.mediaBlobDao.byId('abc_f'))!;
    expect(row.state, BlobState.ready);
    expect(row.bytes, 3);
    expect(row.uploadPending, isTrue);
    expect(row.messageId, 'abc');
    final hit = await _store(h, parent).requestBlob('abc_f', 'own');
    expect(hit!.width, 4);
    expect(hit.fileName, 'img_1.jpg');
  });

  test('registerLocal after the session ended: no row, nothing moved',
      () async {
    final h = charHarness();
    addTearDown(h.close);
    final parent = await _parent();
    final store = _store(h, parent);
    await store.ready;
    final src = File('${parent.path}/v.mp4')..writeAsBytesSync([1]);
    h.pbClient.pb.authStore.clear(); // logout
    final moved = await store.registerLocal(
        blobId: 'abc_f', file: src, meta: '{}', uploadPending: true);
    expect(moved, isNull);
    expect(src.existsSync(), isTrue);
    expect(await h.db.mediaBlobDao.byId('abc_f'), isNull);
  });

  test('logout wipe deletes a registered file', () async {
    final h = charHarness();
    addTearDown(h.close);
    final parent = await _parent();
    final src = File('${parent.path}/doc.pdf')..writeAsBytesSync([1]);
    final moved = await _store(h, parent)
        .registerLocal(blobId: 'abc_f', file: src, meta: '{}');
    expect(moved!.existsSync(), isTrue);

    await wipeMediaCache(() async => parent);
    expect(moved.existsSync(), isFalse);
    expect(Directory('${parent.path}/media_clear').existsSync(), isFalse);
  });
}

/// `media_blob_table` as drift's onCreate made it at schema v11.
const _kV11MediaBlobCreate = 'CREATE TABLE IF NOT EXISTS "media_blob_table" '
    '("blob_id" TEXT NOT NULL, "message_id" TEXT NOT NULL, '
    '"remote_ref" TEXT NULL, "expected_size" INTEGER NULL, '
    '"expected_hash" TEXT NULL, "local_path" TEXT NULL, '
    '"bytes" INTEGER NOT NULL DEFAULT 0, "last_access" INTEGER NOT NULL, '
    '"state" TEXT NOT NULL DEFAULT \'queued\', "error_class" TEXT NULL, '
    '"upload_pending" INTEGER NOT NULL DEFAULT 0 '
    'CHECK ("upload_pending" IN (0, 1)), PRIMARY KEY ("blob_id"));';
