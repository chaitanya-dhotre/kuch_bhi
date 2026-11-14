/// Bug wave 2 §6: a blackholed socket must not hold a media load, the
/// Media & Docs page or the starred list forever. Each network call gives up
/// after 8s of silence and falls into the path the code already has for
/// offline. Real time: about 8s per test.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/media_blob_table.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/infrastructure/media/media_blob_store.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/infrastructure/services/media_gallery_service.dart';

import 'char_harness.dart';

http.Response _record(String messageId) => http.Response(
  jsonEncode({
    'page': 1,
    'perPage': 1,
    'totalItems': 1,
    'totalPages': 1,
    'items': [
      {
        'id': 'mrec_$messageId',
        'collectionId': 'message_media',
        'collectionName': 'message_media',
        'created': '2026-10-07T10:00:00.000Z',
        'updated': '2026-10-07T10:00:00.000Z',
        'message_id': messageId,
        'file': 'blob.bin.enc',
        'file_iv': '',
        'file_name': 'blob.bin',
        'mime_type': 'image/jpeg',
        'expires_at': '',
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'media download: a stall before the headers, a stall mid-body and a '
    'stalled record lookup each end as queued, not a forever spinner',
    () async {
      final never = Completer<http.StreamedResponse>();
      // s1: the file request never answers. s2: headers, then the body stops.
      // s3: the record lookup itself never answers.
      final mock = MockClient.streaming((req, _) async {
        final path = req.url.toString();
        if (path.contains('/api/collections/')) {
          if (path.contains('s3')) return never.future;
          final id = path.contains('s1') ? 's1' : 's2';
          final r = _record(id);
          return http.StreamedResponse(
            Stream.value(r.bodyBytes),
            200,
            headers: r.headers,
          );
        }
        if (path.contains('mrec_s1')) return never.future;
        final body = StreamController<List<int>>();
        body.add(utf8.encode('first bytes'));
        return http.StreamedResponse(body.stream, 200);
      });
      final h = charHarness(clientFactory: () => mock);
      addTearDown(h.close);
      final parent = await Directory.systemTemp.createTemp('media_stall');
      addTearDown(() => parent.delete(recursive: true));
      final store = MediaBlobStore(
        dao: h.db.mediaBlobDao,
        messages: h.db.messagesDao,
        pbClient: h.pbClient,
        encryption: h.encryption,
        resolveKey: (_) async => [fixtureGroupKey],
        epoch: () => 0,
        cacheDir: () async => parent,
        httpClient: mock,
      );
      addTearDown(store.dispose);

      final clock = Stopwatch()..start();
      final results = await Future.wait([
        for (final id in ['s1_f', 's2_f', 's3_f'])
          store.requestBlob(id, 'test'),
      ]).timeout(const Duration(seconds: 20));
      expect(results, [null, null, null]);
      expect(clock.elapsed, lessThan(const Duration(seconds: 12)));
      for (final id in ['s1_f', 's2_f', 's3_f']) {
        final row = await h.db.mediaBlobDao.byId(id);
        expect(
          row!.state,
          BlobState.queued,
          reason: '$id: a stall is offline, never a terminal failure',
        );
      }
    },
  );

  test('Media & Docs page and the starred list give up after 8s; starred '
      'falls back to the stars on this phone', () async {
    final mock = MockClient((_) => Completer<http.Response>().future);
    final h = charHarness(clientFactory: () => mock);
    addTearDown(h.close);
    await seedConversationAndKey(h);
    await h.db.messagesDao.upsertMessage(
      MessagesTableCompanion.insert(
        localId: 'loc_1',
        conversationId: 'g1',
        senderId: 'u_test',
        type: 'text',
        encryptedBody: 'x',
        iv: '',
        serverId: const Value('srv1'),
        isStarred: const Value(true),
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    final clock = Stopwatch()..start();
    final page = MediaGalleryService(
      h.pbClient,
    ).fetchMediaPage((conversationId: 'g1', mediaType: 'image'));
    final starred = buildRepo(h).getStarredMessages('g1');
    await expectLater(page, throwsA(isA<TimeoutException>()));
    final stars = await starred.timeout(const Duration(seconds: 20));
    expect(stars.map((m) => m.serverId), ['srv1']);
    expect(clock.elapsed, lessThan(const Duration(seconds: 12)));
  });

  // Device round 2: a 5-week-old photo whose server record is gone sat on
  // the shimmer for the 45s upload-race wait before offering a retry.
  test('an old message with no media record resolves at once, not after '
      'the 45s wait for a just-sent upload', () async {
    final mock = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'page': 1,
          'perPage': 1,
          'totalItems': 0,
          'totalPages': 0,
          'items': [],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final h = charHarness(clientFactory: () => mock);
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final sent = DateTime.now().subtract(const Duration(days: 37));
    await h.db.messagesDao.upsertMessage(
      MessagesTableCompanion.insert(
        localId: 'loc_old',
        conversationId: 'g1',
        senderId: 'u_test',
        type: 'image',
        encryptedBody: 'x',
        iv: '',
        serverId: const Value('old1'),
        createdAt: sent,
        updatedAt: sent,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        messageRepositoryProvider.overrideWithValue(buildRepo(h)),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    addTearDown(container.dispose);

    final clock = Stopwatch()..start();
    final file = await container
        .read(mediaFileProvider(MediaRef('g1', 'old1', thumb: true)).future)
        .timeout(const Duration(seconds: 20));
    expect(file, isNull);
    expect(clock.elapsed, lessThan(const Duration(seconds: 10)));
  });

  // Device round 2 (user OK, 2026-10-31): a record the server no longer has,
  // on a message over a day old, is gone for good: failed/dead_link, so the
  // bubble says "No longer available" instead of a retry that cannot work.
  test('no media record: over a day old → failed dead_link; a just-sent '
      'one stays queued for the upload race', () async {
    final mock = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'page': 1,
          'perPage': 1,
          'totalItems': 0,
          'totalPages': 0,
          'items': [],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final h = charHarness(clientFactory: () => mock);
    addTearDown(h.close);
    final parent = await Directory.systemTemp.createTemp('media_gone');
    addTearDown(() => parent.delete(recursive: true));
    Future<void> message(String id, Duration age) {
      final at = DateTime.now().subtract(age);
      return h.db.messagesDao.upsertMessage(
        MessagesTableCompanion.insert(
          localId: 'loc_$id',
          conversationId: 'g1',
          senderId: 'u_test',
          type: 'image',
          encryptedBody: 'x',
          iv: '',
          serverId: Value(id),
          createdAt: at,
          updatedAt: at,
        ),
      );
    }

    await message('old1', const Duration(days: 37));
    await message('new1', const Duration(minutes: 1));
    final store = MediaBlobStore(
      dao: h.db.mediaBlobDao,
      messages: h.db.messagesDao,
      pbClient: h.pbClient,
      encryption: h.encryption,
      resolveKey: (_) async => [fixtureGroupKey],
      epoch: () => 0,
      cacheDir: () async => parent,
      httpClient: mock,
    );
    addTearDown(store.dispose);

    expect(await store.requestBlob('old1_t', 'test'), isNull);
    expect(await store.requestBlob('new1_t', 'test'), isNull);
    final old = await h.db.mediaBlobDao.byId('old1_t');
    expect(old!.state, BlobState.failed);
    expect(old.errorClass, 'dead_link');
    expect((await h.db.mediaBlobDao.byId('new1_t'))!.state, BlobState.queued);
  });
}
