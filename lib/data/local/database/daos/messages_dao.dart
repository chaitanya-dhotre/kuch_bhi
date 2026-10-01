import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/messages_table.dart';
import '../tables/message_receipts_table.dart';

part 'messages_dao.g.dart';

@DriftAccessor(tables: [MessagesTable, MessageReceiptsTable])
class MessagesDao extends DatabaseAccessor<AppDatabase>
    with _$MessagesDaoMixin {
  MessagesDao(super.db);

  /// Reactive stream — emits automatically whenever the table changes.
  /// No limit: shows all cached messages. More are fetched from server
  /// via loadMoreMessages() and saved here, which auto-triggers a re-emit.
  Stream<List<MessagesTableData>> watchMessages(String conversationId) =>
      (select(messagesTable)
            ..where((t) =>
                t.conversationId.equals(conversationId) &
                t.isDeletedForMe.equals(false) &
                t.isDeletedForEveryone.equals(false))
            ..orderBy([
              // Primary: canonical timestamp (server time once synced).
              (t) => OrderingTerm(
                    expression: t.createdAt,
                    mode: OrderingMode.desc,
                  ),
              // Stable tiebreaker so identical timestamps sort the SAME on
              // every device (avoids per-device reordering).
              (t) => OrderingTerm(
                    expression: t.serverId,
                    mode: OrderingMode.desc,
                  ),
              (t) => OrderingTerm(
                    expression: t.localId,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .watch();

  Future<void> upsertMessage(MessagesTableCompanion msg) =>
      into(messagesTable).insertOnConflictUpdate(msg);

  Future<MessagesTableData?> getMessageByLocalId(String localId) =>
      (select(messagesTable)..where((t) => t.localId.equals(localId)))
          .getSingleOrNull();

  /// Tolerant of duplicate rows (cross-isolate races can produce them until
  /// [dedupByServerId] runs): prefers the row that already has decrypted
  /// content, falling back to the first.
  Future<MessagesTableData?> getMessageByServerId(String serverId) async {
    final rows = await (select(messagesTable)
          ..where((t) => t.serverId.equals(serverId)))
        .get();
    if (rows.isEmpty) return null;
    if (rows.length == 1) return rows.first;
    return rows.firstWhere((r) => r.decryptedBody != null,
        orElse: () => rows.first);
  }

  /// Looks up a locally-cached system message by exact body (used to guard
  /// against duplicate "X joined the group" bubbles). Plain loop — no
  /// package:collection dependency in this DAO.
  Future<MessagesTableData?> findSystemMessage(
      String conversationId, String senderId, String body) async {
    final rows = await (select(messagesTable)
          ..where((t) =>
              t.conversationId.equals(conversationId) &
              t.senderId.equals(senderId) &
              t.type.equals('system'))
          ..limit(50))
        .get();
    for (final m in rows) {
      if ((m.decryptedBody ?? '') == body) return m;
    }
    return null;
  }

  /// Removes duplicate rows sharing one serverId. The FCM background isolate
  /// writes through its own AppDatabase instance, so it can race the main
  /// isolate's insert — both see "no row yet" and insert independently.
  /// Keeps the best row (decrypted > oldest) and deletes the rest.
  Future<void> dedupByServerId() async {
    final rows = await (select(messagesTable)
          ..where((t) => t.serverId.isNotNull()))
        .get();
    final byServer = <String, List<MessagesTableData>>{};
    for (final r in rows) {
      byServer.putIfAbsent(r.serverId!, () => []).add(r);
    }
    for (final entry in byServer.entries) {
      final dups = entry.value;
      if (dups.length < 2) continue;
      dups.sort((a, b) {
        // Decrypted content wins; then prefer a real UUID localId (not the
        // serverId placeholder used by the background isolate); then oldest.
        final aDec = a.decryptedBody != null ? 0 : 1;
        final bDec = b.decryptedBody != null ? 0 : 1;
        if (aDec != bDec) return aDec - bDec;
        final aPlaceholder = a.localId == a.serverId ? 1 : 0;
        final bPlaceholder = b.localId == b.serverId ? 1 : 0;
        if (aPlaceholder != bPlaceholder) return aPlaceholder - bPlaceholder;
        return a.createdAt.compareTo(b.createdAt);
      });
      for (final extra in dups.skip(1)) {
        await (delete(messagesTable)
              ..where((t) => t.localId.equals(extra.localId)))
            .go();
      }
    }
  }

  Future<void> updateMessageStatus(String localId, String status) =>
      (update(messagesTable)..where((t) => t.localId.equals(localId))).write(
        MessagesTableCompanion(
          status:    Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> setServerId(String localId, String serverId) =>
      (update(messagesTable)..where((t) => t.localId.equals(localId))).write(
        MessagesTableCompanion(serverId: Value(serverId)),
      );

  Future<void> cacheDecryptedBody(String localId, String decrypted) =>
      (update(messagesTable)..where((t) => t.localId.equals(localId))).write(
        MessagesTableCompanion(decryptedBody: Value(decrypted)),
      );

  /// Get pending messages for retry.
  Future<List<MessagesTableData>> getPendingMessages() =>
      (select(messagesTable)
            ..where((t) =>
                t.status.equals('pending') | t.status.equals('failed'))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .get();

  /// Deletes locally-expired disappearing messages. Safe: only removes
  /// messages whose expiry timestamp has passed — never unsent drafts.
  Future<void> deleteExpiredMessages() =>
      (delete(messagesTable)
            ..where((t) =>
                t.expiresAt.isNotNull() &
                t.expiresAt.isSmallerThanValue(DateTime.now())))
          .go();

  Future<List<MessagesTableData>> getStarredMessages(String conversationId) =>
      (select(messagesTable)
            ..where((t) =>
                t.conversationId.equals(conversationId) &
                t.isStarred.equals(true)))
          .get();

  Future<List<MessagesTableData>> getPinnedMessages(String conversationId) =>
      (select(messagesTable)
            ..where((t) =>
                t.conversationId.equals(conversationId) &
                t.isPinned.equals(true)))
          .get();

  /// Reactive pinned messages — updates live as pins change locally or sync in.
  Stream<List<MessagesTableData>> watchPinnedMessages(String conversationId) =>
      (select(messagesTable)
            ..where((t) =>
                t.conversationId.equals(conversationId) &
                t.isPinned.equals(true) &
                t.isDeletedForEveryone.equals(false))
            ..orderBy([
              (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
            ]))
          .watch();

  // ── Receipts ───────────────────────────────────────────────────

  Future<void> upsertReceipt(MessageReceiptsTableCompanion receipt) =>
      into(messageReceiptsTable).insertOnConflictUpdate(receipt);

  Future<List<MessageReceiptsTableData>> getReceiptsForMessage(
          String messageLocalId) =>
      (select(messageReceiptsTable)
            ..where((t) => t.messageLocalId.equals(messageLocalId)))
          .get();
}
