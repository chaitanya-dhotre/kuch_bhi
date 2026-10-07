import 'package:drift/drift.dart';

/// Outbox FSM states (spec §5.2 / brief interface).
///
/// Stored via drift's `textEnum` → the enum's `.name` (e.g.
/// `'failedTerminal'`; the spec prose writes the same state
/// `failed_terminal` — domain-identical, storage spelling differs).
enum OutboxState { queued, sending, sent, failedTerminal }

/// The outbox table IS the queue (spec §5.2): one row per outgoing op,
/// surviving process kill. `op_id` is the client-generated 15-char
/// `[a-z0-9]` id (see `core/utils/op_id.dart`) that becomes the
/// PocketBase record id on create — the idempotency key.
class OutboxTable extends Table {
  /// Client-generated op id — also the future server record id.
  TextColumn get opId => text()();

  /// 'text_send' | 'media_upload' | 'reaction' | 'pin' | 'star' | 'delete' | …
  TextColumn get kind => text()();

  /// Local message/blob id this op acts on.
  TextColumn get ref => text()();

  TextColumn get conversationId => text()();

  /// Monotonic per-conversation FIFO order.
  IntColumn get seq => integer()();

  TextColumn get state => textEnum<OutboxState>()
      .withDefault(const Constant('queued'))();

  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// Backoff deadline for transient failures (null = due immediately).
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  TextColumn get lastError => text().nullable()();

  /// 'id_collision' | 'dead_link' | 'forbidden' | … (spec §6 error classes).
  TextColumn get errorClass => text().nullable()();

  /// op_id of a prerequisite op (e.g. `message_send` → its `media_upload`).
  TextColumn get dependsOn => text().nullable()();

  @override
  Set<Column> get primaryKey => {opId};
}
