// delete-everyone-leftovers spec §6 (docs/design/pages/delete-everyone-leftovers.md):
// a message deleted for everyone keeps no ciphertext, no cached text and no
// local media, and no list shows it.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/reply_quote.dart';
import 'package:kuch_bhi/features/media/screens/media_docs_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:pocketbase/pocketbase.dart' show RecordModel;
import 'package:kuch_bhi/infrastructure/ingest/ingest_batch.dart';
import 'package:kuch_bhi/infrastructure/ingest/ingest_boundary.dart';
import 'package:kuch_bhi/infrastructure/services/media_gallery_service.dart';

import 'char_harness.dart';
import 'media_send_harness.dart';

MessagesTableCompanion _row({
  String localId = 'l1',
  String serverId = 'srv1',
  String type = 'text',
  bool deleted = false,
  bool starred = false,
  String status = 'read',
}) =>
    MessagesTableCompanion.insert(
      localId: localId,
      serverId: Value(serverId),
      conversationId: 'g1',
      senderId: 'u_peer',
      type: type,
      encryptedBody: 'ct',
      iv: 'iv',
      isDeletedForEveryone: Value(deleted),
      isStarred: Value(starred),
      status: Value(status),
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 2),
    );

(IngestBoundary, List<String>) _boundary(AppDatabase db) {
  final forgotten = <String>[];
  return (
    IngestBoundary(
      db: db,
      epoch: () => 0,
      authValid: () => true,
      forgetMedia: (sid) async => forgotten.add(sid),
    ),
    forgotten,
  );
}

/// Drift closes a watched query on a zero-length timer: unmount and let it
/// fire, or the test ends with a pending timer.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<MessagesTableData> _get(AppDatabase db, String localId) async =>
    (await db.messagesDao.getMessageByLocalId(localId))!;

void main() {
  setUp(bodyCache.clear);

  group('B1/B2 ingest', () {
    test('a tombstone blanks the row, drops the cached text and forgets the '
        'media once; a repeat is a no-op', () async {
      final h = charHarness();
      addTearDown(h.close);
      final (b, forgotten) = _boundary(h.db);
      await h.db.messagesDao.upsertMessage(_row());
      bodyCache.put('l1', 'secret');

      await b.commit(const IngestBatch(tombstones: ['srv1']), IngestSource.sse);
      final r = await _get(h.db, 'l1');
      expect(r.isDeletedForEveryone, isTrue);
      expect(r.encryptedBody, '');
      expect(r.iv, '');
      expect(bodyCache.get('l1'), isNull);
      expect(forgotten, ['srv1']);

      await b.commit(const IngestBatch(tombstones: ['srv1']), IngestSource.sse);
      expect(forgotten, ['srv1'], reason: 'already deleted: no second forget');
    });

    test('an upsert carrying the flag is blanked and forgets once', () async {
      final h = charHarness();
      addTearDown(h.close);
      final (b, forgotten) = _boundary(h.db);
      await h.db.messagesDao.upsertMessage(_row());
      bodyCache.put('l1', 'secret');

      final batch = IngestBatch(upserts: [MessageUpsert(_row(deleted: true))]);
      await b.commit(batch, IngestSource.fetch);
      final r = await _get(h.db, 'l1');
      expect((r.isDeletedForEveryone, r.encryptedBody, r.iv), (true, '', ''));
      expect(bodyCache.get('l1'), isNull);
      expect(forgotten, ['srv1']);

      bodyCache.put('l1', 'decrypted again by a fetch');
      await b.commit(batch, IngestSource.fetch);
      expect(forgotten, ['srv1']);
      expect(bodyCache.get('l1'), isNull, reason: 'the cache is always dropped');
    });

    test('a live row is left alone', () async {
      final h = charHarness();
      addTearDown(h.close);
      final (b, forgotten) = _boundary(h.db);
      await b.commit(
        IngestBatch(upserts: [MessageUpsert(_row())]),
        IngestSource.fetch,
      );
      final r = await _get(h.db, 'l1');
      expect((r.encryptedBody, r.iv), ('ct', 'iv'));
      expect(forgotten, isEmpty);
    });

    test('a cancelled own send that the server copy re-delivers is blanked',
        () async {
      final h = charHarness();
      addTearDown(h.close);
      final (b, _) = _boundary(h.db);
      await h.db.messagesDao
          .upsertMessage(_row(deleted: true, status: 'cancelled'));
      await b.commit(
        IngestBatch(upserts: [MessageUpsert(_row())]),
        IngestSource.sse,
      );
      final r = await _get(h.db, 'l1');
      expect((r.isDeletedForEveryone, r.status), (true, 'cancelled'));
      expect((r.encryptedBody, r.iv), ('', ''));
    });
  });

  test('start-up sweep: blanks old deleted rows and lists their media; a '
      'second run finds nothing', () async {
    final h = charHarness();
    addTearDown(h.close);
    final dao = h.db.messagesDao;
    await dao.upsertMessage(_row(localId: 'a', serverId: 'sa', deleted: true));
    await dao.upsertMessage(_row(localId: 'b', serverId: 'sb'));
    await dao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'c',
      serverId: const Value('sc'),
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'image',
      encryptedBody: '',
      iv: '',
      isDeletedForEveryone: const Value(true),
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 2),
    ));
    await h.db.mediaBlobDao.insert(MediaBlobTableCompanion.insert(
      blobId: 'sc_f',
      messageId: 'sc',
      lastAccess: DateTime.now(),
    ));

    expect(await dao.blankDeletedForEveryone(), {'sa', 'sc'});
    expect((await _get(h.db, 'a')).encryptedBody, '');
    expect((await _get(h.db, 'b')).encryptedBody, 'ct', reason: 'live row kept');

    await h.db.mediaBlobDao.deleteByMessageId('sc'); // what forgetLocal does
    expect(await dao.blankDeletedForEveryone(), isEmpty);
  });

  test('BodyCache.remove drops one id and keeps the rest', () {
    final c = BodyCache()
      ..put('a', '1')
      ..put('b', '2');
    c.remove('a');
    expect((c.get('a'), c.get('b')), (null, '2'));
  });

  test('S1: offline Starred leaves out a deleted message', () async {
    final h = charHarness();
    addTearDown(h.close);
    final dao = h.db.messagesDao;
    await dao.upsertMessage(_row(localId: 'a', serverId: 'sa', starred: true));
    await dao.upsertMessage(
        _row(localId: 'b', serverId: 'sb', starred: true, deleted: true));
    final rows = await dao.getStarredMessages('g1');
    expect(rows.map((r) => r.localId), ['a']);
  });

  test('G1: the gallery query leaves out deleted messages', () {
    expect(
      MediaGalleryService.pageFilter((conversationId: 'g1', mediaType: 'image')),
      'conversation_id="g1"&&media_type="image"'
      '&&message_id.is_deleted_for_everyone=false',
    );
  });

  group('repo', () {
    Future<String> sendAndWait(dynamic repo, String text,
        {String? replyTo}) async {
      final before = await repo.db.messagesDao.watchMessages('g1').first;
      await repo.sendMessage(
          conversationId: 'g1', plaintext: text, replyToLocalId: replyTo);
      final rows = await repo.db.messagesDao.watchMessages('g1').first;
      final id = (rows as List<MessagesTableData>)
          .map((r) => r.localId)
          .firstWhere((id) => !(before as List<MessagesTableData>)
              .any((b) => b.localId == id));
      await until(() async =>
          (await repo.db.messagesDao.getMessageByLocalId(id))?.serverId !=
          null);
      return id;
    }

    test('R1: a reply uploads no preview of its parent', () async {
      final (_, repo, server, _) = await mediaSendSetup();
      final parent = await sendAndWait(repo, 'the parent text');
      await sendAndWait(repo, 'a reply', replyTo: parent);
      final body = server.createBodies.last;
      expect(body['reply_to_id'], isNotEmpty);
      expect(body['reply_preview'], '');
    });

    test('my delete for everyone blanks the row, drops the cached text and '
        'deletes the local media; delete for me keeps the body', () async {
      final (h, repo, _, tmp) = await mediaSendSetup();
      final id = await sendAndWait(repo, 'oops');
      final sid = (await _get(h.db, id)).serverId!;
      final file = await tempFile(tmp, 'clear.jpg', 10);
      await repo.mediaBlobStore.dao.upsert(MediaBlobTableCompanion.insert(
        blobId: '${sid}_f',
        messageId: sid,
        localPath: Value(file.path),
        lastAccess: DateTime.now(),
      ));
      bodyCache.put(id, 'oops');

      await repo.deleteMessage(id, forEveryone: true);
      final r = await _get(h.db, id);
      expect((r.isDeletedForEveryone, r.encryptedBody, r.iv), (true, '', ''));
      expect(bodyCache.get(id), isNull);
      expect(File(file.path).existsSync(), isFalse);
      expect(await repo.mediaBlobStore.dao.byMessageId(sid), isEmpty);

      final keep = await sendAndWait(repo, 'only for me');
      await repo.deleteMessage(keep);
      expect((await _get(h.db, keep)).encryptedBody, isNotEmpty);
    });

    test('sweepDeletedForEveryone removes media left by an old build',
        () async {
      final (h, repo, _, tmp) = await mediaSendSetup();
      await h.db.messagesDao.upsertMessage(
          _row(localId: 'old', serverId: 'sold', type: 'image', deleted: true));
      final file = await tempFile(tmp, 'old.jpg', 10);
      await repo.mediaBlobStore.dao.upsert(MediaBlobTableCompanion.insert(
        blobId: 'sold_f',
        messageId: 'sold',
        localPath: Value(file.path),
        lastAccess: DateTime.now(),
      ));

      await repo.sweepDeletedForEveryone();
      expect((await _get(h.db, 'old')).encryptedBody, '');
      expect(File(file.path).existsSync(), isFalse);
    });
  });

  group('live (device round 1: these updated only after a reopen)', () {
    MessagesTableCompanion flag(String localId) => MessagesTableCompanion(
          localId: Value(localId),
          isDeletedForEveryone: const Value(true),
        );

    Future<void> markDeleted(AppDatabase db, String localId) =>
        (db.update(db.messagesTable)
              ..where((t) => t.localId.equals(localId)))
            .write(flag(localId));

    testWidgets('an open quote turns into Message not available when its '
        'parent is deleted', (tester) async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      await db.messagesDao.upsertMessage(
          _row(localId: 'p', serverId: 'sp', type: 'image'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            mediaFileProvider.overrideWith((ref, r) async => null),
          ],
          child: MaterialApp(
            theme: warmPopLight(),
            home: const Scaffold(
              body: ReplyQuote(
                  senderName: 'Aanya', replyToId: 'p', conversationId: 'g1'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Message not available'), findsNothing);

      await markDeleted(db, 'p');
      await tester.pumpAndSettle();
      expect(find.text('Message not available'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('an open Docs tab drops a document whose message is deleted',
        (tester) async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      await db.messagesDao.upsertMessage(
          _row(localId: 'd', serverId: 'sd', type: 'document'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            isOnlineProvider.overrideWith((ref) => Stream.value(true)),
            mediaPageProvider.overrideWith((ref, key) async => [
                  if (key.mediaType == 'document')
                    RecordModel({
                      'id': 'm1',
                      'message_id': 'sd',
                      'file_name': 'notes.pdf',
                      'file_size': 2048,
                      'created': '2026-10-01 10:00:00Z',
                    }),
                ]),
          ],
          child: MaterialApp(
            theme: warmPopLight(),
            home: const MediaDocsScreen(conversationId: 'g1'),
          ),
        ),
      );
      await tester.tap(find.text('Docs'));
      await tester.pumpAndSettle();
      expect(find.text('notes.pdf'), findsOneWidget);

      await markDeleted(db, 'd');
      await tester.pumpAndSettle();
      expect(find.text('notes.pdf'), findsNothing);
      await _unmount(tester);
    });

    test('watchDeletedServerIds emits a newly deleted id, and only on change',
        () async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      await db.messagesDao.upsertMessage(_row(localId: 'a', serverId: 'sa'));
      final seen = <Set<String>>[];
      final sub =
          db.messagesDao.watchDeletedServerIds('g1').listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      await db.messagesDao
          .upsertMessage(_row(localId: 'b', serverId: 'sb')); // not deleted
      await pumpEventQueue();
      await markDeleted(db, 'a');
      await pumpEventQueue();
      expect(seen, [<String>{}, {'sa'}]);
    });
  });

  testWidgets('Q1: a quote of a deleted parent says Message not available, '
      'with no icon or thumbnail', (tester) async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    await db.messagesDao.upsertMessage(
        _row(localId: 'p', serverId: 'sp', type: 'image', deleted: true));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const Scaffold(
            body: ReplyQuote(
                senderName: 'Aanya', replyToId: 'p', conversationId: 'g1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Message not available'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
    expect(find.byType(Image), findsNothing);
    await _unmount(tester);
  });
}
