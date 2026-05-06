import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/conversations_table.dart';
import '../tables/conversation_members_table.dart';

part 'conversations_dao.g.dart';

@DriftAccessor(tables: [ConversationsTable, ConversationMembersTable])
class ConversationsDao extends DatabaseAccessor<AppDatabase>
    with _$ConversationsDaoMixin {
  ConversationsDao(super.db);

  Future<void> upsertConversation(ConversationsTableCompanion conv) =>
      into(conversationsTable).insertOnConflictUpdate(conv);

  /// Watch all conversations ordered by last message time.
  /// This drives the home screen list.
  Stream<List<ConversationsTableData>> watchAllConversations() =>
      (select(conversationsTable)
            ..orderBy([
              (t) => OrderingTerm(
                    expression: t.isPinned,
                    mode: OrderingMode.desc,
                  ),
              (t) => OrderingTerm(
                    expression: t.lastMessageAt,
                    mode: OrderingMode.desc,
                  ),
            ]))
          .watch();

  Future<ConversationsTableData?> getConversationById(String id) =>
      (select(conversationsTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Stream<ConversationsTableData?> watchConversationById(String id) =>
      (select(conversationsTable)..where((t) => t.id.equals(id)))
          .watchSingleOrNull();

  Future<void> updateLastMessage(
    String conversationId,
    String preview,
    DateTime timestamp,
  ) =>
      (update(conversationsTable)
            ..where((t) => t.id.equals(conversationId)))
          .write(ConversationsTableCompanion(
        lastMessagePreview: Value(preview),
        lastMessageAt: Value(timestamp),
        updatedAt: Value(DateTime.now()),
      ));

  Future<void> setPinned(String id, bool pinned) =>
      (update(conversationsTable)..where((t) => t.id.equals(id))).write(
        ConversationsTableCompanion(isPinned: Value(pinned)),
      );

  // --- Members ---

  Future<void> upsertMember(ConversationMembersTableCompanion member) =>
      into(conversationMembersTable).insertOnConflictUpdate(member);

  Future<List<ConversationMembersTableData>> getMembersForConversation(
    String conversationId,
  ) =>
      (select(conversationMembersTable)
            ..where((t) => t.conversationId.equals(conversationId)))
          .get();

  Future<void> updateLastReadMessage(
    String memberId,
    String messageLocalId,
  ) =>
      (update(conversationMembersTable)
            ..where((t) => t.id.equals(memberId)))
          .write(ConversationMembersTableCompanion(
        lastReadMessageId: Value(messageLocalId),
      ));
}
