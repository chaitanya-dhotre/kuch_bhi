/// Wave 4 (media-send review SHOULDs 4 and 6, burst-send follow-up):
///  - a cancel made offline after the create ack stays cancelled when a page
///    fetch, a live update or a receipt brings the server copy back;
///  - deleting an own media row that still holds its upload latch frees the
///    pinned blobs;
///  - a text queued behind a media send stays behind it at the media ack.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/infrastructure/ingest/ingest_batch.dart';
import 'package:kuch_bhi/infrastructure/media/media_blob_store.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/upload_progress.dart';

import 'media_send_harness.dart';

Future<String> _sendDoc(MessageRepositoryImpl repo, Directory tmp, String name) async {
  final before = await repo.db.messagesDao.watchMessages('g1').first;
  await repo.sendMediaMessage(
    conversationId: 'g1',
    mediaType: 'document',
    mediaFile: await tempFile(tmp, name),
  );
  final rows = await repo.db.messagesDao.watchMessages('g1').first;
  return rows
      .map((r) => r.localId)
      .firstWhere((id) => !before.any((b) => b.localId == id));
}

void main() {
  setUp(bodyCache.clear);

  test('offline cancel after the create ack: a page fetch, a live update and '
      'a receipt keep it hidden; the next resume marks the server copy',
      () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.mediaGate = Completer<void>(); // create acked, upload held
    final id = await _sendDoc(repo, tmp, 'c.pdf');
    await until(() async => server.mediaUploads == 1);
    expect(server.messages[id], isNotNull, reason: 'create acked');
    // A live update read the row just before the cancel (review: the ingest
    // commits companions built from a row read before its decrypt step).
    final stale = repo.ssePinDeleteCompanion(
      existing: (await h.db.messagesDao.getMessageByLocalId(id))!,
      serverPinned: false,
      serverDeleted: false,
    );

    server.offline = true;
    expect(await repo.cancelMediaUpload(id), isTrue);
    server.mediaGate!.complete();
    await until(() async => uploadTracker.ticket(id) == null);
    expect(server.marks, isEmpty, reason: 'offline: the mark is deferred');
    expect(await h.db.messagesDao.watchMessages('g1').first, isEmpty);

    // Back online, but a page fetch lands before any resume pass.
    server.offline = false;
    await repo.loadMoreMessages('g1', 0);
    expect(await h.db.messagesDao.watchMessages('g1').first, isEmpty,
        reason: 'the server copy (not deleted yet) must not bring it back');

    await repo.ingestBoundary.commit(
      IngestBatch(upserts: [MessageUpsert(stale)]),
      IngestSource.sse,
    );
    expect(await h.db.messagesDao.watchMessages('g1').first, isEmpty,
        reason: 'a live update built before the cancel keeps it too');

    await h.db.messagesDao.updateMessageStatus(id, 'delivered'); // a receipt
    expect((await h.db.messagesDao.getMessageByLocalId(id))!.status,
        'cancelled', reason: 'fetch, live update and receipt kept the tombstone');
    await repo.resumeMediaUploads();
    expect(server.marks, [id], reason: 'resume still finds the cancel');
    expect(server.messages[id]!['is_deleted_for_everyone'], isTrue);
    expect(await h.db.messagesDao.getMessageByLocalId(id), isNull);
  });

  test('deleting a failed own media row frees its latched blobs', () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.mediaStatus = 413; // terminal: the row stays failed, latch kept
    final id = await _sendDoc(repo, tmp, 'big.pdf');
    await until(() async =>
        (await h.db.messagesDao.getMessageByLocalId(id))?.status == 'failed');
    final blob = (await h.db.mediaBlobDao.byId(mediaBlobId(id, thumb: false)))!;
    expect(blob.uploadPending, isTrue);

    await repo.deleteMessage(id);
    expect(await h.db.mediaBlobDao.byMessageId(id), isEmpty,
        reason: 'no blob row left pinned by the upload latch');
    expect(File(blob.localPath!).existsSync(), isFalse);
    expect(await h.db.messagesDao.watchMessages('g1').first, isEmpty);
    await until(() async => server.marks.contains(id),
        reason: 'receivers never keep the empty server copy');
    expect(server.messages[id]!['is_deleted_for_everyone'], isTrue);
  });

  test('delete for me while the upload runs: never unsent, the upload '
      'finishes and frees the latch', () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.mediaGate = Completer<void>();
    final id = await _sendDoc(repo, tmp, 'up.pdf');
    await until(() async => server.mediaUploads == 1);

    await repo.deleteMessage(id);
    final row = (await h.db.messagesDao.getMessageByLocalId(id))!;
    expect(row.isDeletedForMe, isTrue);
    expect(row.isDeletedForEveryone, isFalse);
    server.mediaGate!.complete();
    await until(() async => uploadTracker.ticket(id) == null);
    expect(server.marks, isEmpty, reason: 'receivers keep the photo');
    final blob = (await h.db.mediaBlobDao.byId(mediaBlobId(id, thumb: false)))!;
    expect(blob.uploadPending, isFalse, reason: 'evictable once sent');
  });

  test('delete for everyone while the upload runs = a cancel: no upload '
      'finishes, blobs freed', () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.mediaGate = Completer<void>();
    final id = await _sendDoc(repo, tmp, 'all.pdf');
    await until(() async => server.mediaUploads == 1);

    await repo.deleteMessage(id, forEveryone: true);
    expect(await h.db.mediaBlobDao.byMessageId(id), isEmpty,
        reason: 'not pinned by the latch if the app dies now');
    server.mediaGate!.complete();
    await until(() async => uploadTracker.ticket(id) == null);
    await until(() async => await h.db.messagesDao.getMessageByLocalId(id) == null);
    expect(server.messages[id]!['is_deleted_for_everyone'], isTrue);
  });

  test('cancel while the create is in flight: the 404 keeps the row, so a '
      'late mark that fails is retried by the next resume', () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    server.createGate = Completer<void>();
    final id = await _sendDoc(repo, tmp, 'late.pdf');
    await until(() async => server.createBodies.isNotEmpty);

    expect(await repo.cancelMediaUpload(id), isTrue);
    await until(() async => server.marks.contains(id)); // answered 404
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((await h.db.messagesDao.getMessageByLocalId(id))?.status,
        'cancelled', reason: 'kept while its create is still in flight');

    server.offline = true; // the create lands; the upload's own mark fails
    server.createGate!.complete();
    await until(() async => uploadTracker.ticket(id) == null);
    expect(server.messages[id]!['is_deleted_for_everyone'], isFalse);

    server.offline = false;
    await repo.loadMoreMessages('g1', 0); // the unmarked copy, before resume
    expect(await h.db.messagesDao.watchMessages('g1').first, isEmpty,
        reason: 'no second, visible row for the cancelled send');
    await repo.resumeMediaUploads();
    expect(server.messages[id]!['is_deleted_for_everyone'], isTrue,
        reason: 'receivers never keep the empty copy');
    expect(await h.db.messagesDao.getMessageByLocalId(id), isNull);
  });

  test('a text queued behind a media send stays behind it at the media ack',
      () async {
    final (h, repo, server, tmp) = await mediaSendSetup();
    await repo.outboxWorker.onAuthPaused(true); // the text stays queued
    server.offline = true;
    final doc = await _sendDoc(repo, tmp, 'first.pdf');
    await until(() async => uploadTracker.ticket(doc) == null);
    await repo.sendMessage(conversationId: 'g1', plaintext: 'second');
    final text = (await h.db.messagesDao.watchMessages('g1').first)
        .firstWhere((r) => r.localId != doc)
        .localId;

    Future<List<String>> oldestFirst() async =>
        (await h.db.messagesDao.watchMessages('g1').first)
            .reversed
            .map((r) => r.localId)
            .toList();
    expect(await oldestFirst(), [doc, text]);

    // The media ack carries the server's clock (an hour ahead here).
    server.offline = false;
    await repo.resumeMediaUploads();
    expect(server.createBodies.first['id'], doc,
        reason: 'the media create sends its own id');
    expect(await oldestFirst(), [doc, text], reason: 'after the media ack');

    final op = (await h.db.outboxDao.forConversation('g1')).single;
    await repo.sendOutboxOp(op);
    expect(await oldestFirst(), [doc, text], reason: 'after the text ack');
  });
}
