import 'package:drift/drift.dart';

/// Media blob FSM states (spec §9 / brief interface).
///
/// Stored via drift's `textEnum` → the enum's `.name`, so the SQL values
/// are `queued`, `downloading`, `ready`, `failed`, `evicted`.
///
/// - `queued` — waiting for bytes (offline stays here; auto-resumes on
///   reconnect — failed ≠ offline).
/// - `downloading` — the full in-flight pipeline: download → size/hash
///   verify → decrypt.
/// - `ready` — decrypted on disk in the app-private media cache dir.
/// - `failed` — terminal; `error_class` ∈ {dead_link, expired, verify,
///   decrypt}. Never auto-retried.
/// - `evicted` — bytes dropped, metadata retained (re-downloadable).
enum BlobState { queued, downloading, ready, failed, evicted }

/// One row per downloadable media blob (spec §5.3).
///
/// **No `protected` column** — protection is a DERIVED predicate
/// (`upload_pending ∨ message.starred ∨ message.pinned`) computed at
/// eviction time so it cannot drift (spec §5.3).
class MediaBlobTable extends Table {
  /// Blob identity — `'<messageServerId>_<f|t>'` (full / thumb variant);
  /// see `mediaBlobId()` in the MediaBlobStore.
  TextColumn get blobId => text()();

  /// Server id of the owning message — joins `messages_table.server_id`
  /// for the starred/pinned protection predicate and resolves the
  /// conversation id for the E2E key.
  TextColumn get messageId => text()();

  /// Remote reference stamped at record-lookup time: `'<recordId>/<file>'`.
  TextColumn get remoteRef => text().nullable()();

  /// Expected downloaded (ciphertext) size — verify stage; null = unknown.
  IntColumn get expectedSize => integer().nullable()();

  /// Expected sha256 (lowercase hex) of the downloaded bytes — verify
  /// stage; null = unknown.
  TextColumn get expectedHash => text().nullable()();

  /// Absolute path of the decrypted file (app-private dir).
  TextColumn get localPath => text().nullable()();

  /// Decrypted file size in bytes (eviction accounting for `ready` rows).
  IntColumn get bytes => integer().withDefault(const Constant(0))();

  DateTimeColumn get lastAccess => dateTime()();

  TextColumn get state => textEnum<BlobState>()
      .withDefault(const Constant('queued'))();

  /// Set iff `state = failed` — one of spec §9's error classes:
  /// `'dead_link' | 'expired' | 'verify' | 'decrypt'`.
  TextColumn get errorClass => text().nullable()();

  /// Outgoing-upload latch (spec §5.3): a blob whose only copy feeds a
  /// pending upload is protected from eviction. Derived protection input
  /// — NOT a `protected` flag.
  BoolColumn get uploadPending =>
      boolean().withDefault(const Constant(false))();

  /// Media metadata as JSON (`width`, `height`, `durationSeconds`,
  /// `expiresAt`, `mimeType`, `fileName`; own sends add `quality`) — a cache
  /// hit returns it so the bubble keeps its shape, expiry and name after a
  /// restart. Null on rows written before v12.
  TextColumn get meta => text().nullable()();

  @override
  Set<Column> get primaryKey => {blobId};
}
