import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database/app_database.dart' show appDatabaseProvider;
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
