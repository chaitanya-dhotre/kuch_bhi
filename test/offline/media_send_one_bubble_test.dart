/// Media send B/C (13.7, 13.8): one row with a pre-assigned id from frame
/// one, the sent file kept as a ready blob, the create ack stamped with the
/// server's time, and a page fetch mid-upload leaving exactly one row.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/utils/op_id.dart';
import 'package:kuch_bhi/data/local/database/tables/media_blob_table.dart';
import 'package:kuch_bhi/infrastructure/media/media_blob_store.dart';

import 'media_send_harness.dart';

void main() {
  setUp(bodyCache.clear);

  for (final type in ['image', 'video', 'voice', 'document']) {
    test('$type: one row, ready blobs, server-time stamp, one row after a '
        'mid-upload page fetch, sent file kept', () async {
      final (h, repo, server, tmp) = await mediaSendSetup();
      server.mediaGate = Completer<void>();
      final withThumb = type == 'image' || type == 'video';
      final file = await tempFile(tmp, 'sent_$type.bin');
      final thumb = withThumb ? await tempFile(tmp, 'thumb_$type.jpg', 2000) : null;

      await repo.sendMediaMessage(
        conversationId: 'g1',
        mediaType: type,
        mediaFile: file,
        thumbnailFile: thumb,
        durationSeconds: type == 'voice' || type == 'video' ? 12 : null,
        durationText: type == 'voice' ? '0:12' : null,
      );

      // B1/B2: one row, a 15-char record id, ready blobs with the latch.
      var rows = await h.db.messagesDao.watchMessages('g1').first;
      expect(rows, hasLength(1));
      final localId = rows.single.localId;
      expect(isOpId(localId), isTrue);
      final full = await h.db.mediaBlobDao.byId(mediaBlobId(localId, thumb: false));
      expect(full!.state, BlobState.ready);
      expect(full.uploadPending, isTrue);
      expect(full.localPath, contains('/media_clear/${localId}_f_'));
      expect(File(full.localPath!).existsSync(), isTrue);
      final t = await h.db.mediaBlobDao.byId(mediaBlobId(localId, thumb: true));
      expect(t == null, !withThumb);
      if (withThumb) expect(t!.uploadPending, isTrue);

      // B4: the create carries the id; the ack stamps serverId + server time.
      await until(() async => server.mediaUploads == 1, reason: 'upload starts');
      expect(server.createBodies.single['id'], localId);
      final acked = (await h.db.messagesDao.getMessageByLocalId(localId))!;
      expect(acked.serverId, localId);
      expect(acked.status, 'pending');
      expect(acked.createdAt.toUtc(), DateTime.parse(serverCreated),
          reason: 'server created, never device time');

      // B5: page fetches while the upload is in flight leave ONE row.
      await repo.loadMoreMessages('g1', 0);
      final sub = repo.watchMessages('g1').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 300));
      unawaited(sub.cancel()); // the repo stream's generator never finishes here
      rows = await h.db.messagesDao.watchMessages('g1').first;
      expect(rows, hasLength(1), reason: '13.7: no second bubble');
      expect(rows.single.localId, localId);

      // Step D: mediaId + sent, latch cleared, the sent file still on disk.
      server.mediaGate!.complete();
      await until(() async =>
          (await h.db.messagesDao.getMessageByLocalId(localId))!.status ==
          'sent');
      final sent = (await h.db.messagesDao.getMessageByLocalId(localId))!;
      expect(sent.mediaId, server.media.keys.single);
      expect(sent.createdAt.toUtc(), DateTime.parse(serverCreated));
      final after = await h.db.mediaBlobDao.byId(mediaBlobId(localId, thumb: false));
      expect(after!.uploadPending, isFalse);
      expect(File(after.localPath!).existsSync(), isTrue,
          reason: '13.8: the sender keeps the file');
      expect(server.media.values.single['file_name'], 'sent_$type.bin',
          reason: 'the server gets the real name, not the store prefix');
    });
  }

  test('insert transaction throws → no row, no blob row, moved files deleted',
      () async {
    final (h, repo, _, tmp) = await mediaSendSetup();
    final file = await tempFile(tmp, 'photo.jpg');
    final missingThumb = File('${tmp.path}/gone.jpg'); // makes the 2nd move throw

    await expectLater(
      repo.sendMediaMessage(
        conversationId: 'g1',
        mediaType: 'image',
        mediaFile: file,
        thumbnailFile: missingThumb,
      ),
      throwsA(anything),
    );

    expect(await h.db.messagesDao.watchMessages('g1').first, isEmpty);
    expect(await h.db.mediaBlobDao.byState(BlobState.ready), isEmpty);
    final cache = Directory('${tmp.path}/media_clear');
    expect(cache.listSync(), isEmpty, reason: 'the moved photo was deleted');
  });
}
