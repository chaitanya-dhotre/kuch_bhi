/// Albums 12.5 B7–B10, C2–C4: an album send writes N rows that share item
/// 0's id, starts no upload of its own, and uploads one at a time in index
/// order through the resume pass; ingest maps the two fields; v12 → v13
/// keeps every row.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/utils/op_id.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/chat/providers/album_provider.dart';
import 'package:kuch_bhi/infrastructure/media/media_blob_store.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/upload_progress.dart';

import 'media_send_harness.dart';

Future<List<AlbumSendItem>> _items(Directory tmp, int n) async => [
  for (var i = 0; i < n; i++)
    (
      mediaType: 'image',
      mediaFile: await tempFile(tmp, 'p$i.jpg'),
      thumbnailFile: await tempFile(tmp, 't$i.jpg', 2000),
      durationSeconds: null,
      durationText: null,
      videoWidth: null,
      videoHeight: null,
    ),
];

Future<List<MessagesTableData>> _album(MessageRepositoryImpl repo) async {
  final rows = await repo.db.messagesDao.watchMessages('g1').first;
  return rows..sort((a, b) => a.albumIndex!.compareTo(b.albumIndex!));
}

Future<String> _status(MessageRepositoryImpl repo, String id) async =>
    (await repo.db.messagesDao.getMessageByLocalId(id))?.status ?? 'gone';

Future<void> _idle(MessageRepositoryImpl repo, List<MessagesTableData> rows) =>
    until(() async {
      for (final r in rows) {
        if (uploadTracker.ticket(r.localId) != null) return false;
      }
      return true;
    });

void main() {
  setUp(bodyCache.clear);

  test('3 items → 3 rows sharing item 0\'s id, index 0/1/2, create bodies '
      'carry both, uploads one at a time in index order', () async {
    final (_, repo, server, tmp) = await mediaSendSetup();
    await repo.sendMediaAlbum(conversationId: 'g1', items: await _items(tmp, 3));

    final rows = await _album(repo);
    expect(rows, hasLength(3));
    final albumId = rows.first.localId;
    expect(isOpId(albumId), isTrue);
    expect(rows.map((r) => r.albumId), everyElement(albumId));
    expect(rows.map((r) => r.albumIndex), [0, 1, 2]);
    expect(rows.map((r) => r.localId).toList()..sort(),
        rows.map((r) => r.localId).toList(),
        reason: 'op ids sort in pick order');

    await until(() async => server.media.length == 3, reason: 'all uploaded');
    expect(server.maxInFlightMedia, 1, reason: 'never two at once (B8)');
    expect(server.createOrder, rows.map((r) => r.localId).toList());
    for (final (i, body) in server.createBodies.indexed) {
      expect(body['album_id'], albumId);
      expect(body['album_index'], i);
    }
    await _idle(repo, rows);
    for (final r in rows) {
      expect(await _status(repo, r.localId), 'sent');
      final after = (await repo.db.messagesDao.getMessageByLocalId(r.localId))!;
      expect((after.albumId, after.albumIndex), (albumId, r.albumIndex),
          reason: 'the ack keeps the album fields');
    }
  });

  test('a single send carries no album fields', () async {
    final (_, repo, server, tmp) = await mediaSendSetup();
    await repo.sendMediaMessage(
      conversationId: 'g1',
      mediaType: 'image',
      mediaFile: await tempFile(tmp, 'one.jpg'),
      thumbnailFile: await tempFile(tmp, 'one_t.jpg', 2000),
    );
    await until(() async => server.media.length == 1);
    expect(server.createBodies.single.containsKey('album_id'), isFalse);
    final row = (await repo.db.messagesDao.watchMessages('g1').first).single;
    expect((row.albumId, row.albumIndex), (null, null));
  });

  test('offline from item 1 → the rest stay pending, untouched; reconnect → '
      'all sent, in order', () async {
    final (_, repo, server, tmp) = await mediaSendSetup();
    server.offline = true;
    await repo.sendMediaAlbum(conversationId: 'g1', items: await _items(tmp, 3));
    final rows = await _album(repo);
    await _idle(repo, rows);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    for (final r in rows) {
      expect(await _status(repo, r.localId), 'pending');
      final blob = await repo.db.mediaBlobDao.byId(
        mediaBlobId(r.localId, thumb: false),
      );
      expect(blob!.uploadPending, isTrue);
    }
    expect(server.createOrder, isEmpty);

    server.offline = false;
    await repo.resumeMediaUploads();
    for (final r in rows) {
      expect(await _status(repo, r.localId), 'sent');
    }
    expect(server.createOrder, rows.map((r) => r.localId).toList());
    expect(server.maxInFlightMedia, 1);
  });

  test('item 1 → 413 failed; item 2 still uploads (B8)', () async {
    final (_, repo, server, tmp) = await mediaSendSetup();
    final arrivals = <String>[];
    final sub = server.mediaArrived.stream.listen((mid) {
      arrivals.add(mid);
      // Heard after that create's own check: arm the answer for the next.
      server.mediaStatus = arrivals.length == 1 ? 413 : null;
    });
    addTearDown(sub.cancel);
    await repo.sendMediaAlbum(conversationId: 'g1', items: await _items(tmp, 3));
    final rows = await _album(repo);
    await until(() async => arrivals.length == 3, reason: 'item 2 tried');
    await _idle(repo, rows);
    expect(await _status(repo, rows[1].localId), 'failed');
    expect(await _status(repo, rows[2].localId), 'sent');
  });

  test('Cancel sending: unsent items go, the sent one stays', () async {
    final (_, repo, server, tmp) = await mediaSendSetup();
    var n = 0;
    final sub = server.mediaArrived.stream.listen((_) {
      if (++n == 1) server.offline = true; // item 0 lands, then the link drops
    });
    addTearDown(sub.cancel);
    await repo.sendMediaAlbum(conversationId: 'g1', items: await _items(tmp, 3));
    final rows = await _album(repo);
    await until(() async => await _status(repo, rows[0].localId) == 'sent');
    await _idle(repo, rows);

    for (final r in rows.skip(1)) {
      expect(await repo.cancelMediaUpload(r.localId), isTrue);
    }
    final left = await repo.db.messagesDao.watchMessages('g1').first;
    expect(left.map((r) => r.localId), [rows[0].localId]);
  });

  test('a re-run after a lost create ack sends the same album fields', () async {
    final (_, repo, server, tmp) = await mediaSendSetup();
    server.loseMessageAck = true;
    await repo.sendMediaAlbum(conversationId: 'g1', items: await _items(tmp, 2));
    final rows = await _album(repo);
    await until(() async => server.createOrder.isNotEmpty);
    await _idle(repo, rows);
    await repo.resumeMediaUploads();
    final first = server.createBodies
        .where((b) => b['id'] == rows[0].localId)
        .toList();
    expect(first, hasLength(2), reason: 'created, ack lost, created again');
    expect(first.map((b) => (b['album_id'], b['album_index'])),
        everyElement((rows[0].localId, 0)));
    expect(await _status(repo, rows[0].localId), 'sent');
  });

  test('ingest maps album_id/album_index; empty album_id → nulls (C3)',
      () async {
    final (_, repo, server, _) = await mediaSendSetup();
    for (final (id, album, index) in [
      ('srvalbum0000001', 'srvalbum0000001', 0),
      ('srvalbum0000002', 'srvalbum0000001', 1),
      ('srvplain0000003', '', 0),
    ]) {
      server.messages[id] = {
        'id': id,
        'collectionId': 'messages',
        'collectionName': 'messages',
        'conversation_id': 'g1',
        'sender_id': 'u_other',
        'type': 'image',
        'encrypted_body': 'x',
        'iv': 'y',
        'album_id': album,
        'album_index': index,
        'created': serverCreated,
        'updated': serverCreated,
      };
      await repo.fetchAndCacheSingleMessage(id, 'g1');
    }
    final got = {
      for (final r in await repo.db.select(repo.db.messagesTable).get())
        r.serverId: (r.albumId, r.albumIndex),
    };
    expect(got['srvalbum0000001'], ('srvalbum0000001', 0));
    expect(got['srvalbum0000002'], ('srvalbum0000001', 1));
    expect(got['srvplain0000003'], (null, null));

    final album = await repo.db.messagesDao
        .rowsInAlbum('g1', 'srvalbum0000001')
        .get();
    expect(album.map((r) => r.albumIndex), [0, 1], reason: 'C4: in order');
  });

  test('rowsInAlbum skips deleted rows', () async {
    final (_, repo, _, _) = await mediaSendSetup();
    final at = DateTime.utc(2026, 11, 1);
    for (final (id, i, gone) in [('a0', 0, false), ('a1', 1, true)]) {
      await repo.db.messagesDao.upsertMessage(
        MessagesTableCompanion.insert(
          localId: id,
          conversationId: 'g1',
          senderId: 'u_test',
          type: 'image',
          encryptedBody: '',
          iv: '',
          albumId: const Value('a0'),
          albumIndex: Value(i),
          isDeletedForMe: Value(gone),
          createdAt: at,
          updatedAt: at,
        ),
      );
    }
    final rows = await repo.db.messagesDao.rowsInAlbum('g1', 'a0').get();
    expect(rows.map((r) => r.localId), ['a0']);
  });

  test("albumRowsProvider: another member's row with the same album_id "
      'never joins', () async {
    final (_, repo, _, _) = await mediaSendSetup();
    final at = DateTime.utc(2026, 11, 1);
    for (final (id, sender, i) in [
      ('a0', 'u_test', 0),
      ('x1', 'u_evil', 1),
      ('a2', 'u_test', 2),
    ]) {
      await repo.db.messagesDao.upsertMessage(
        MessagesTableCompanion.insert(
          localId: id,
          conversationId: 'g1',
          senderId: sender,
          type: 'image',
          encryptedBody: '',
          iv: '',
          albumId: const Value('a0'),
          albumIndex: Value(i),
          createdAt: at,
          updatedAt: at,
        ),
      );
    }
    final c = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(repo.db)],
    );
    addTearDown(c.dispose);
    final sub = c.listen(albumRowsProvider(const AlbumKey('g1', 'a0')), (_, _) {});
    addTearDown(sub.close);
    final rows = await c.read(albumRowsProvider(const AlbumKey('g1', 'a0')).future);
    expect(rows.map((r) => r.localId), ['a0', 'a2']);
  });

  test('schema v12 → v13 keeps message rows, album columns null', () async {
    final dir = await Directory.systemTemp.createTemp('album_v13');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/kuch_bhi.sqlite';

    // A v13 database's DDL minus the two new columns = the v12 shape.
    final seed = AppDatabase.forExecutor(NativeDatabase(File(path)));
    final at = DateTime.utc(2026, 10, 1);
    await seed.messagesDao.upsertMessage(
      MessagesTableCompanion.insert(
        localId: 'old1',
        serverId: const Value('srvold000000001'),
        conversationId: 'g1',
        senderId: 'u_test',
        type: 'image',
        encryptedBody: 'c',
        iv: 'i',
        createdAt: at,
        updatedAt: at,
      ),
    );
    await seed.close();
    final db12 = raw.sqlite3.open(path);
    db12.execute('ALTER TABLE messages_table DROP COLUMN album_id');
    db12.execute('ALTER TABLE messages_table DROP COLUMN album_index');
    db12.execute('ALTER TABLE messages_table DROP COLUMN disappear_after');
    db12.execute('PRAGMA user_version = 12');
    db12.dispose();

    final db = AppDatabase.forExecutor(NativeDatabase(File(path)));
    addTearDown(db.close);
    final rows = await db.select(db.messagesTable).get();
    expect(rows, hasLength(1));
    expect(rows.single.serverId, 'srvold000000001');
    expect((rows.single.albumId, rows.single.albumIndex), (null, null));
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    expect(v.data.values.first, 14);
  });
}
