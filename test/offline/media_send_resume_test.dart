/// Media send D (resume, failure classes, cancel, stall): an offline or
/// interrupted upload stays `pending` with its files and finishes on
/// resume; re-runs converge on one message and one media record.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/infrastructure/media/media_blob_store.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/upload_progress.dart';

import 'char_harness.dart';
import 'media_send_harness.dart';

Future<String> _send(MessageRepositoryImpl repo, Directory tmp, String name,
    {String type = 'document'}) async {
  final before = await repo.db.messagesDao.watchMessages('g1').first;
  await repo.sendMediaMessage(
    conversationId: 'g1',
    mediaType: type,
    mediaFile: await tempFile(tmp, name),
    durationSeconds: type == 'voice' ? 4 : null,
    durationText: type == 'voice' ? '0:04' : null,
  );
  final rows = await repo.db.messagesDao.watchMessages('g1').first;
  return rows
      .map((r) => r.localId)
      .firstWhere((id) => !before.any((b) => b.localId == id));
}

Future<String> _status(CharHarness h, String id) async =>
    (await h.db.messagesDao.getMessageByLocalId(id))?.status ?? 'gone';

void main() {
  setUp(bodyCache.clear);

  test('offline at Step B → pending, files kept; reconnect → one row, sent',
      () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.offline = true;
    final id = await _send(repo, tmp, 'note.m4a', type: 'voice');
    await until(() async => server.offline && uploadTracker.ticket(id) == null);
    expect(await _status(h, id), 'pending');
    final blob = await h.db.mediaBlobDao.byId(mediaBlobId(id, thumb: false));
    expect(blob!.uploadPending, isTrue);
    expect(File(blob.localPath!).existsSync(), isTrue);

    server.offline = false;
    await repo.resumeMediaUploads();
    expect(await _status(h, id), 'sent');
    expect(await h.db.messagesDao.watchMessages('g1').first, hasLength(1));
    expect(server.createBodies.single['encrypted_body'], isNotEmpty);
  });

  test('lost create ack → re-create hits the duplicate id → ownership check → '
      'sent, not failed', () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.loseMessageAck = true;
    final id = await _send(repo, tmp, 'a.pdf');
    await until(() async => uploadTracker.ticket(id) == null);
    expect(await _status(h, id), 'pending');

    await repo.resumeMediaUploads();
    expect(server.createOrder, [id, id]);
    expect(await _status(h, id), 'sent');
    expect(server.mediaUploads, 1);
  });

  test('lost media ack → the re-run finds the media record, no second upload',
      () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.loseMediaAck = true;
    final id = await _send(repo, tmp, 'b.pdf');
    await until(() async => uploadTracker.ticket(id) == null);
    expect(await _status(h, id), 'pending');

    await repo.resumeMediaUploads();
    expect(await _status(h, id), 'sent');
    expect(server.mediaUploads, 1, reason: 'counted uploads');
    expect((await h.db.messagesDao.getMessageByLocalId(id))!.mediaId,
        server.media.keys.single);
  });

  test('413 → failed (terminal); Try again re-runs once', () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.mediaStatus = 413;
    final id = await _send(repo, tmp, 'big.pdf');
    await until(() async => await _status(h, id) == 'failed');

    await repo.resumeMediaUploads(); // a resume pass skips failed rows
    expect(server.mediaUploads, 1);

    server.mediaStatus = null;
    await repo.retryMessage(id);
    await until(() async => await _status(h, id) == 'sent');
    expect(server.mediaUploads, 2);
  });

  test('a transport timeout (the stall error) → pending', () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.mediaGate = Completer<void>();
    final id = await _send(repo, tmp, 'c.pdf');
    await until(() async => server.mediaUploads == 1);
    // What the ticket throws when no bytes move for 8s (proved below).
    uploadTracker.ticket(id)!.guard(Future<void>.value()).ignore();
    server.offline = true;
    server.mediaGate!.completeError(TimeoutException('stalled'));
    await until(() async => uploadTracker.ticket(id) == null);
    expect(await _status(h, id), 'pending');
  });

  test('two pending rows resume oldest first, one at a time', () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.offline = true;
    final first = await _send(repo, tmp, '1.pdf');
    final second = await _send(repo, tmp, '2.pdf');
    await until(() async =>
        uploadTracker.ticket(first) == null &&
        uploadTracker.ticket(second) == null);

    server.offline = false;
    await repo.resumeMediaUploads();
    expect(server.createOrder, [first, second]);
    expect(server.maxInFlightMedia, 1);
    expect(await _status(h, first), 'sent');
    expect(await _status(h, second), 'sent');
  });

  test('cancel mid-upload → row, blobs and files gone, server mark once',
      () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.mediaGate = Completer<void>();
    final id = await _send(repo, tmp, 'd.pdf');
    await until(() async => server.mediaUploads == 1);
    final path =
        (await h.db.mediaBlobDao.byId(mediaBlobId(id, thumb: false)))!.localPath!;

    expect(await repo.cancelMediaUpload(id), isTrue);
    expect(await h.db.messagesDao.watchMessages('g1').first, isEmpty,
        reason: 'hidden at once');
    await until(() async => await _status(h, id) == 'gone');
    expect(await h.db.mediaBlobDao.byMessageId(id), isEmpty);
    expect(File(path).existsSync(), isFalse);
    server.mediaGate!.complete();
    await until(() async => uploadTracker.ticket(id) == null);
    expect(server.marks, [id]);
    expect(server.messages[id]!['is_deleted_for_everyone'], isTrue);
  });

  test('cancel offline → gone locally; the mark is sent by the next resume',
      () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.offline = true;
    final id = await _send(repo, tmp, 'e.pdf');
    await until(() async => uploadTracker.ticket(id) == null);

    expect(await repo.cancelMediaUpload(id), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await h.db.messagesDao.watchMessages('g1').first, isEmpty);
    expect(await h.db.mediaBlobDao.byMessageId(id), isEmpty);
    // Wave 4: the kept row's status is now the cancel tombstone.
    expect(await _status(h, id), 'cancelled', reason: 'hidden row kept for the mark');

    server.offline = false;
    await repo.resumeMediaUploads();
    expect(server.marks, [id], reason: 'never created → 404 → done');
    expect(await _status(h, id), 'gone');
    expect(server.messages, isEmpty, reason: 'no upload after a cancel');
  });

  test('a receipt moving an uploading row to delivered: resume still uploads, '
      'no downgrade to sent; cancel follows the upload latch', () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.offline = true;
    final id = await _send(repo, tmp, 'r.pdf');
    await until(() async => uploadTracker.ticket(id) == null);
    await h.db.messagesDao.updateMessageStatus(id, 'delivered'); // a receipt

    server.offline = false;
    await repo.resumeMediaUploads();
    final row = (await h.db.messagesDao.getMessageByLocalId(id))!;
    expect(row.mediaId, server.media.keys.single, reason: 'resumed + uploaded');
    expect(row.status, 'delivered', reason: 'never downgraded to sent');
    final blob = await h.db.mediaBlobDao.byId(mediaBlobId(id, thumb: false));
    expect(blob!.uploadPending, isFalse);
    expect(await repo.cancelMediaUpload(id), isFalse,
        reason: 'an uploaded message is never deleted by the upload ✕');
    expect(server.marks, isEmpty);
  });

  group('UploadTicket (fake clock)', () {
    testWidgets('no bytes pulled for 8s → the guarded request fails with a '
        'timeout', (tester) async {
      final t = UploadTicket(() {})..total = 10;
      Object? error;
      t.guard(Completer<void>().future).catchError((Object e) => error = e);
      await tester.pump(const Duration(seconds: 7));
      expect(error, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(error, isA<TimeoutException>());
    });

    testWidgets('each pulled chunk counts and re-arms the bound; cancel errors '
        'the request and the stream', (tester) async {
      final ticks = <double>[];
      late final UploadTicket t;
      t = UploadTicket(() => ticks.add(t.progress));
      final bytes = Uint8List(300 * 1024);
      t.total = bytes.length;
      Object? error;
      t.guard(Completer<void>().future).catchError((Object e) => error = e);
      final it = StreamIterator(t.counted(bytes));
      await it.moveNext();
      await tester.pump(const Duration(seconds: 6));
      await it.moveNext();
      await tester.pump(const Duration(seconds: 6));
      expect(error, isNull, reason: 'a pull re-armed the 8s bound');
      expect(ticks.first, closeTo(128 / 300, 0.01));
      t.cancel();
      await tester.pump();
      expect(error, isA<UploadCancelled>());
      await expectLater(it.moveNext(), throwsA(isA<UploadCancelled>()));
    });
  });
}
