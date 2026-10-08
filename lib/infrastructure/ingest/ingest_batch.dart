import '../../../data/local/database/app_database.dart';

/// Where an [IngestBatch] came from (spec §7 source tags: `sse`, `fetch`,
/// `drain-ack`). Pure metadata — identical batches write identically
/// regardless of source (Task 6 test 1 commits the same batch under `sse`
/// and `fetch`); the tag rides along for logs and future per-source policy.
enum IngestSource { sse, fetch, drainAck }

/// One message row to upsert (keyed by server id) inside a boundary
/// commit. The repo keeps record parsing, decrypt and flag preservation
/// (`_companionFromRecord` builds this companion); the boundary only
/// writes it — orchestration vs. write split (spec §4).
class MessageUpsert {
  const MessageUpsert(this.row);

  /// Fully-built companion — required columns set, optional columns either
  /// carried from the existing row or explicitly `Value(...)`.
  final MessagesTableCompanion row;
}

/// Per-conversation sync-cursor advance carried INTO the commit
/// transaction (spec §7: the cursor moves with the batch — an SSE gap plus
/// a pull fetch can neither skip nor double-apply).
class CursorDelta {
  const CursorDelta({required this.conversationId, required this.to});

  final String conversationId;

  /// Server-side stamp of the newest record in the batch (never the device
  /// clock — same provenance as `_writeCursor` before the extraction).
  final DateTime to;
}

/// Drain-ack payload (Task 2 `handleDrainAck` semantics): stamp
/// [serverId] + `status='sent'` onto the local row that owns [opId]
/// (resolved via `outbox.ref` INSIDE the commit transaction) and flip the
/// op to `sent` in that same transaction (dual-truth rule — spec §5.1/§7).
class OutboxAck {
  const OutboxAck({
    required this.opId,
    required this.serverId,
    required this.senderId,
    required this.conversationId,
  });

  final String opId;
  final String serverId;
  final String senderId;
  final String conversationId;
}

/// One batch of network-sourced record writes — the only shape
/// [IngestBoundary.commit] accepts (spec §7).
///
/// LEDGERED seam vs the brief's 3-field sketch: the optional [ack] field
/// carries the drain-ack payload. It cannot be pre-resolved into a
/// [MessageUpsert] because the `outbox.ref` → localId read happens inside
/// the commit transaction (carry-in 1 — the read joins the txn).
class IngestBatch {
  const IngestBatch({
    this.upserts = const [],
    this.tombstones = const [],
    this.cursorAdvance,
    this.ack,
  });

  /// Message rows to upsert by server id (idempotent — re-committing the
  /// same batch converges on the same row set).
  final List<MessageUpsert> upserts;

  /// Server ids of messages deleted-for-everyone — applied as an
  /// idempotent flag upsert (spec §7: "tombstones upsert like any row";
  /// a missing local row is a no-op, never an insert-from-thin-air).
  final List<String> tombstones;

  /// Cursor advance to apply in the SAME transaction as [upserts].
  final CursorDelta? cursorAdvance;

  /// Drain-ack payload; non-null ⇒ commit also flips `outbox.state` and
  /// stamps `messages.status` atomically.
  final OutboxAck? ack;
}
