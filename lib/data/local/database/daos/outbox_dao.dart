import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/outbox_table.dart';

part 'outbox_dao.g.dart';

@DriftAccessor(tables: [OutboxTable])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db);

  /// Inserts [row] — runs inside the CALLER'S transaction when one is open
  /// (spec §5.2 enqueue atomicity: message row + outbox row in ONE Drift
  /// transaction, so a kill between them is impossible by construction).
  Future<void> enqueue(OutboxTableCompanion row) =>
      into(outboxTable).insert(row);

  Future<OutboxTableData?> byId(String opId) =>
      (select(outboxTable)..where((t) => t.opId.equals(opId)))
          .getSingleOrNull();

  /// Ops due NOW: queued, backoff elapsed (or none), FIFO by
  /// `(conversationId, seq)` (spec §6 ordering).
  Future<List<OutboxTableData>> due(DateTime now) =>
      (select(outboxTable)
            ..where((t) =>
                t.state.equalsValue(OutboxState.queued) &
                (t.nextAttemptAt.isNull() |
                    t.nextAttemptAt.isSmallerOrEqualValue(now)))
            ..orderBy([
              (t) => OrderingTerm(expression: t.conversationId),
              (t) => OrderingTerm(expression: t.seq),
            ]))
          .get();

  /// FSM transition. Optional fields are written only when provided —
  /// `failedTerminal` passes `lastError` + `errorClass` together.
  Future<void> setState(
    String opId,
    OutboxState state, {
    int? attempts,
    DateTime? nextAttemptAt,
    String? lastError,
    String? errorClass,
  }) =>
      (update(outboxTable)..where((t) => t.opId.equals(opId))).write(
        OutboxTableCompanion(
          state: Value(state),
          attempts: attempts == null ? const Value.absent() : Value(attempts),
          nextAttemptAt: nextAttemptAt == null
              ? const Value.absent()
              : Value(nextAttemptAt),
          lastError:
              lastError == null ? const Value.absent() : Value(lastError),
          errorClass:
              errorClass == null ? const Value.absent() : Value(errorClass),
        ),
      );

  /// Next per-conversation seq (max + 1) — call INSIDE the enqueue txn.
  Future<int> nextSeq(String conversationId) async {
    final newest = await (select(outboxTable)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.seq, mode: OrderingMode.desc),
          ])
          ..limit(1))
        .getSingleOrNull();
    return (newest?.seq ?? 0) + 1;
  }

  Future<List<OutboxTableData>> all() =>
      (select(outboxTable)
            ..orderBy([
              (t) => OrderingTerm(expression: t.conversationId),
              (t) => OrderingTerm(expression: t.seq),
            ]))
          .get();

  Future<List<OutboxTableData>> forConversation(String conversationId) =>
      (select(outboxTable)
            ..where((t) => t.conversationId.equals(conversationId))
            ..orderBy([(t) => OrderingTerm(expression: t.seq)]))
          .get();
}
