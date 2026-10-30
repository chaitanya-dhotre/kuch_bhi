import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/local/database/app_database.dart';
import '../../../data/local/database/tables/media_blob_table.dart';
import '../../chat/providers/chat_provider.dart';

/// Why a full-file load came back empty, as far as the blob row tells.
enum MediaBlobStatus { other, expired, cantDecrypt }

/// D4: a read-only look at the blob row (no write, no pipeline call). The
/// store never retries a `failed` blob, so these two get no Try again.
final mediaBlobStatusProvider =
    FutureProvider.autoDispose.family<MediaBlobStatus, MediaRef>((ref, r) async {
  final row = await ref.read(appDatabaseProvider).mediaBlobDao.byId(r.blobId);
  if (row?.state != BlobState.failed) return MediaBlobStatus.other;
  return switch (row!.errorClass) {
    'expired' || 'dead_link' => MediaBlobStatus.expired,
    'decrypt' || 'verify' => MediaBlobStatus.cantDecrypt,
    _ => MediaBlobStatus.other,
  };
});

/// The full file when it is already decrypted on disk, else null. Read-only:
/// it watches the blob row and never starts a download. Pass a full-file ref.
final mediaFullLocalProvider =
    StreamProvider.autoDispose.family<File?, MediaRef>((ref, r) => ref
        .read(appDatabaseProvider)
        .mediaBlobDao
        .watchById(r.blobId)
        .map((row) {
          final path = row?.state == BlobState.ready ? row!.localPath : null;
          return path != null && File(path).existsSync() ? File(path) : null;
        }));

/// F1: save and share, behind one provider so tests never hit a plugin.
class MediaActions {
  const MediaActions();

  /// Returns false when gallery access is refused.
  Future<bool> save(String path, {required bool video}) async {
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) return false;
    video ? await Gal.putVideo(path) : await Gal.putImage(path);
    return true;
  }

  Future<void> share(String path) => Share.shareXFiles([XFile(path)]);
}

final mediaActionsProvider = Provider<MediaActions>((ref) => const MediaActions());
