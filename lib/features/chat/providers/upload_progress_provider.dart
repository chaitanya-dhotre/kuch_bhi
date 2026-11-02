import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/op_id.dart';
import '../../../data/local/database/app_database.dart' show appDatabaseProvider;
import '../../../domain/entities/message.dart';
import '../../../infrastructure/media/media_blob_store.dart' show mediaBlobId;
import '../../../services/upload_progress.dart';


/// Upload progress (0–1) of an own media message by localId; null when no
/// upload is running for it (waiting for the network, or done). Watch it in
/// build — never await it.
final uploadProgressProvider =
    StreamProvider.autoDispose.family<double?, String>(
  (ref, localId) => uploadTracker.watch(localId),
);

/// True while an own media send still has to upload: its full blob keeps the
/// upload latch until the upload lands or is cancelled. The status column
/// cannot say so (receipts move an acked row to delivered mid-upload).
final uploadPendingProvider = StreamProvider.autoDispose.family<bool, String>(
  (ref, localId) => ref
      .read(appDatabaseProvider)
      .mediaBlobDao
      .watchById(mediaBlobId(localId, thumb: false))
      .map((row) => row?.uploadPending ?? false),
);

/// What a photo/video/voice/document bubble draws from (media-send B3): the
/// id (an own send's op id IS its server id, so it draws from frame one),
/// the local id while its own upload runs, and the status to show (a
/// receipt can reach an acked row mid-upload: keep the clock). One source
/// for the single bubbles and an album's tiles.
({String? mediaId, String? uploadLocalId, String status}) mediaBubbleInputs(
  WidgetRef ref,
  Message message, {
  required bool isMine,
}) {
  final mediaId =
      message.serverId ??
      (isMine && isOpId(message.localId) ? message.localId : null);
  final ownUpload =
      mediaId != null &&
      isMine &&
      isOpId(message.localId) &&
      (ref.watch(uploadPendingProvider(message.localId)).valueOrNull ??
          const {'pending', 'failed'}.contains(message.status));
  return (
    mediaId: mediaId,
    uploadLocalId: ownUpload ? message.localId : null,
    status: ownUpload && message.status != 'failed'
        ? 'pending'
        : message.status,
  );
}
