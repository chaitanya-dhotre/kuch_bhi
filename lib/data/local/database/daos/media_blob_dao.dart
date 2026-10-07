import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/media_blob_table.dart';

part 'media_blob_dao.g.dart';

/// Data layer for `media_blob_table` (spec §5.3 / §9).
///
/// The MediaBlobStore is the SOLE writer of blob rows (spec §4) — this
/// dao exposes only the primitives the store's FSM needs. Pattern mirrors
/// `OutboxDao`: [setState] writes only the fields it is handed.
@DriftAccessor(tables: [MediaBlobTable])
class MediaBlobDao extends DatabaseAccessor<AppDatabase>
    with _$MediaBlobDaoMixin {
  MediaBlobDao(super.db);

  /// Raw insert (store row-creation + tests). `insertOrIgnore` so two
  /// concurrent [MediaBlobStore.requestBlob] calls for a fresh id cannot
  /// race on the primary key.
  Future<void> insert(Insertable<MediaBlobTableData> row) =>
      into(mediaBlobTable).insert(row, mode: InsertMode.insertOrIgnore);

  Future<MediaBlobTableData?> byId(String blobId) =>
      (select(mediaBlobTable)..where((t) => t.blobId.equals(blobId)))
          .getSingleOrNull();

  /// FSM transition. Optional fields are written only when provided —
  /// `failed` passes `errorClass`, `ready` passes `localPath`/`bytes`/
  /// `lastAccess` together.
  Future<void> setState(
    String blobId,
    BlobState state, {
    String? errorClass,
    String? remoteRef,
    String? localPath,
    int? bytes,
    DateTime? lastAccess,
  }) =>
      (update(mediaBlobTable)..where((t) => t.blobId.equals(blobId))).write(
        MediaBlobTableCompanion(
          state: Value(state),
          errorClass: errorClass == null
              ? const Value.absent()
              : Value(errorClass),
          remoteRef: remoteRef == null
              ? const Value.absent()
              : Value(remoteRef),
          localPath:
              localPath == null ? const Value.absent() : Value(localPath),
          bytes: bytes == null ? const Value.absent() : Value(bytes),
          lastAccess: lastAccess == null
              ? const Value.absent()
              : Value(lastAccess),
        ),
      );

  /// Resets ALL `downloading` rows to `queued` (spec §9 startup janitor —
  /// process died mid-pipeline, orphan `.part` file cleaned alongside).
  Future<void> resetDownloadingToQueued() =>
      (update(mediaBlobTable)..where((t) => t.state.equalsValue(BlobState.downloading)))
          .write(const MediaBlobTableCompanion(state: Value(BlobState.queued)));

  Future<List<MediaBlobTableData>> byState(BlobState state) =>
      (select(mediaBlobTable)..where((t) => t.state.equalsValue(state)))
          .get();

  /// Eviction source: `ready` rows in LRU order (oldest access first).
  /// The derived-protected predicate (`upload_pending ∨ starred ∨ pinned`)
  /// is applied by the store against each row — spec §5.3 says the
  /// predicate is computed at eviction time, never stored.
  Future<List<MediaBlobTableData>> readyLru() =>
      (select(mediaBlobTable)
            ..where((t) => t.state.equalsValue(BlobState.ready))
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.lastAccess, mode: OrderingMode.asc),
            ]))
          .get();

  /// SUM(bytes) over `ready` rows — the cache-size figure the watermark
  /// trigger and eviction loop measure (evicted rows keep metadata but
  /// their bytes are no longer on disk).
  Future<int> readyTotalBytes() async {
    final sum = mediaBlobTable.bytes.sum();
    final row = await (selectOnly(mediaBlobTable)
          ..addColumns([sum])
          ..where(mediaBlobTable.state.equalsValue(BlobState.ready)))
        .getSingle();
    return row.read(sum) ?? 0;
  }
}
