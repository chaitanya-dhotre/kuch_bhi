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

  Stream<List<ConversationsTableData>> watchAllConversations() =>
      (select(conversationsTable)
            ..orderBy([
              (t) => OrderingTerm(
                  expression: t.isPinned, mode: OrderingMode.desc),
              (t) => OrderingTerm(
                  expression: t.lastMessageAt, mode: OrderingMode.desc),
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
        lastMessageAt:      Value(timestamp),
        updatedAt:          Value(DateTime.now()),
      ));

  Future<void> setPinned(String id, bool pinned) =>
      (update(conversationsTable)..where((t) => t.id.equals(id))).write(
        ConversationsTableCompanion(isPinned: Value(pinned)),
      );

  // ── Members ───────────────────────────────────────────────────

  Future<void> upsertMember(ConversationMembersTableCompanion m) =>
      into(conversationMembersTable).insertOnConflictUpdate(m);

  Future<List<ConversationMembersTableData>> getMembersForConversation(
          String conversationId) =>
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

  // ── Find direct conversation ───────────────────────────────────

  /// Returns the conversation ID of the existing direct chat between
  /// two users, or null if none exists locally.
  Future<String?> findDirectConversationId(
    String myId,
    String otherId,
  ) async {
    final mine = await (select(conversationMembersTable)
          ..where((t) => t.userId.equals(myId)))
        .get();

    final theirs = await (select(conversationMembersTable)
          ..where((t) => t.userId.equals(otherId)))
        .get();

    final myIds    = mine.map((m)   => m.conversationId).toSet();
    final theirIds = theirs.map((m) => m.conversationId).toSet();
    final common   = myIds.intersection(theirIds);

    String? bestId;
    DateTime? bestLastMessageAt;
    DateTime? bestCreatedAt;

    for (final id in common) {
      final conv = await (select(conversationsTable)
            ..where((t) => t.id.equals(id) & t.type.equals('direct')))
          .getSingleOrNull();
      if (conv == null) continue;

      final candidateLastMessageAt = conv.lastMessageAt;
      final candidateCreatedAt = conv.createdAt;

      final shouldReplace = bestId == null ||
          (candidateLastMessageAt != null &&
              (bestLastMessageAt == null ||
                  candidateLastMessageAt.isAfter(bestLastMessageAt))) ||
          (candidateLastMessageAt == bestLastMessageAt &&
              candidateCreatedAt.isAfter(bestCreatedAt ?? DateTime.fromMillisecondsSinceEpoch(0)));

      if (shouldReplace) {
        bestId = id;
        bestLastMessageAt = candidateLastMessageAt;
        bestCreatedAt = candidateCreatedAt;
      }
    }
    return bestId;
  }
}
