import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/messages_table.dart';
import '../tables/message_receipts_table.dart';

part 'messages_dao.g.dart';

@DriftAccessor(tables: [MessagesTable, MessageReceiptsTable])
class MessagesDao extends DatabaseAccessor<AppDatabase>
    with _$MessagesDaoMixin {
  MessagesDao(super.db);

  /// Insert a new message. Uses upsert to prevent duplicates
  /// when the same message arrives via FCM and real-time subscription.
  Future<void> upsertMessage(MessagesTableCompanion message) =>
      into(messagesTable).insertOnConflictUpdate(message);

  /// Watch messages for a conversation, paginated.
  /// Returns newest first — the UI reverses the list.
  Stream<List<MessagesTableData>> watchMessages(
    String conversationId, {
    int limit = 40,
    int offset = 0,
  }) =>
      (select(messagesTable)
            ..where((t) =>
                t.conversationId.equals(conversationId) &
                t.isDeletedForMe.equals(false))
            ..orderBy([
              (t) => OrderingTerm(
                    expression: t.createdAt,
                    mode: OrderingMode.desc,
                  )
            ])
            ..limit(limit, offset: offset))
          .watch();

  Future<MessagesTableData?> getMessageByLocalId(String localId) =>
      (select(messagesTable)..where((t) => t.localId.equals(localId)))
          .getSingleOrNull();

  Future<MessagesTableData?> getMessageByServerId(String serverId) =>
      (select(messagesTable)..where((t) => t.serverId.equals(serverId)))
          .getSingleOrNull();

  /// Update status after server confirms receipt.
  Future<void> updateMessageStatus(String localId, String status) =>
      (update(messagesTable)..where((t) => t.localId.equals(localId))).write(
        MessagesTableCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Set serverId once PocketBase returns the record ID.
  Future<void> setServerId(String localId, String serverId) =>
      (update(messagesTable)..where((t) => t.localId.equals(localId))).write(
        MessagesTableCompanion(serverId: Value(serverId)),
      );

  /// Cache decrypted body to avoid re-decrypting on every rebuild.
  Future<void> cacheDecryptedBody(String localId, String decrypted) =>
      (update(messagesTable)..where((t) => t.localId.equals(localId))).write(
        MessagesTableCompanion(decryptedBody: Value(decrypted)),
      );

  /// Get all pending messages to retry sending.
  Future<List<MessagesTableData>> getPendingMessages() =>
      (select(messagesTable)
            ..where((t) => t.status.equals('pending'))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .get();

  /// Starred messages for a conversation.
  Future<List<MessagesTableData>> getStarredMessages(
          String conversationId) =>
      (select(messagesTable)
            ..where((t) =>
                t.conversationId.equals(conversationId) &
                t.isStarred.equals(true)))
          .get();

  /// Pinned messages for a conversation.
  Future<List<MessagesTableData>> getPinnedMessages(
          String conversationId) =>
      (select(messagesTable)
            ..where((t) =>
                t.conversationId.equals(conversationId) &
                t.isPinned.equals(true)))
          .get();

  /// Full-text search within a conversation (case-insensitive).
  Future<List<MessagesTableData>> searchMessages(
    String conversationId,
    String query,
  ) =>
      (select(messagesTable)
            ..where((t) =>
                t.conversationId.equals(conversationId) &
                t.decryptedBody.like('%$query%')))
          .get();

  // --- Receipts ---

  Future<void> upsertReceipt(MessageReceiptsTableCompanion receipt) =>
      into(messageReceiptsTable).insertOnConflictUpdate(receipt);

  Future<List<MessageReceiptsTableData>> getReceiptsForMessage(
          String messageLocalId) =>
      (select(messageReceiptsTable)
            ..where((t) => t.messageLocalId.equals(messageLocalId)))
          .get();

  Stream<List<MessageReceiptsTableData>> watchReceiptsForMessage(
          String messageLocalId) =>
      (select(messageReceiptsTable)
            ..where((t) => t.messageLocalId.equals(messageLocalId)))
          .watch();
}
