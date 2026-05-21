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
              (t) => OrderingTerm(
                    expression: t.createdAt,
                    mode: OrderingMode.desc,
                  )
            ]))
          .watch();

  Future<void> upsertMessage(MessagesTableCompanion msg) =>
      into(messagesTable).insertOnConflictUpdate(msg);

  Future<MessagesTableData?> getMessageByLocalId(String localId) =>
      (select(messagesTable)..where((t) => t.localId.equals(localId)))
          .getSingleOrNull();

  Future<MessagesTableData?> getMessageByServerId(String serverId) =>
      (select(messagesTable)..where((t) => t.serverId.equals(serverId)))
          .getSingleOrNull();

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
  Future<List<MessagesTableData>> getPendingMessages() async {
    await deleteStuckPendingMessages();
    return (select(messagesTable)
          ..where((t) =>
              t.status.equals('pending') | t.status.equals('failed'))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  Future<void> deleteStuckPendingMessages() =>
      (delete(messagesTable)
            ..where((t) =>
                (t.status.equals('pending') | t.status.equals('failed')) &
                t.serverId.isNull() &
                t.createdAt.isSmallerThanValue(
                  DateTime.now().subtract(const Duration(hours: 24)),
                )))
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

  // ── Receipts ───────────────────────────────────────────────────

  Future<void> upsertReceipt(MessageReceiptsTableCompanion receipt) =>
      into(messageReceiptsTable).insertOnConflictUpdate(receipt);

  Future<List<MessageReceiptsTableData>> getReceiptsForMessage(
          String messageLocalId) =>
      (select(messageReceiptsTable)
            ..where((t) => t.messageLocalId.equals(messageLocalId)))
          .get();
}
