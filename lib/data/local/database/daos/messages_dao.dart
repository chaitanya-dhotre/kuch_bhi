import 'package:drift/drift.dart';
import '../../../../core/decrypt/body_cache.dart';
import '../../../../core/utils/chunk_ids.dart';
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

  /// Total rows for a conversation (unfiltered) — pins the outbox core
  /// invariants "rollback leaves 0 / echo leaves exactly 1" in tests.
  Future<int> countForConversation(String conversationId) async {
    final cnt = countAll();
    final q = selectOnly(messagesTable)
      ..addColumns([cnt])
      ..where(messagesTable.conversationId.equals(conversationId));
    return (await q.getSingle()).read(cnt) ?? 0;
  }

  /// True when any cached row exists for the conversation (warm vs cold
  /// fetch decision — cold fetches the latest page, warm fetches only the
  /// cursor delta).
  Future<bool> hasAnyMessages(String conversationId) async {
    final row = await (select(messagesTable)
          ..where((t) => t.conversationId.equals(conversationId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Existing rows for a batch of server ids (batched-cache flag
  /// preservation). Missing ids are simply absent from the result.
  /// Chunked at 500 — SQLite bind-variable caps (999 on older Android)
  /// made oversized catch-up deltas fail permanently (review I3).
  Future<List<MessagesTableData>> getMessagesByServerIds(
      List<String> serverIds) async {
    if (serverIds.isEmpty) return [];
    final out = <MessagesTableData>[];
    for (final chunk in chunkIds(serverIds, 500)) {
      out.addAll(await (select(messagesTable)
            ..where((t) => t.serverId.isIn(chunk)))
          .get());
    }
    return out;
  }

  /// Upsert keyed on serverId (UNIQUE index target). Used by the FCM
  /// background isolate whose rows are deterministic (localId == serverId):
  /// when the main isolate already cached the message under a UUID key,
  /// this UPDATES that row instead of inserting a duplicate bubble.
  Future<void> upsertMessageByServerId(MessagesTableCompanion msg) {
    assert(msg.serverId.present && msg.serverId.value != null);
    return into(messagesTable).insert(
      msg,
      onConflict: DoUpdate(
        // Never rewrite localId on conflict — the existing row keeps its
        // UUID PK; only the content fields update.
        (_) => msg.copyWith(localId: const Value.absent()),
        target: [messagesTable.serverId],
      ),
    );
  }

  /// Deletes any OTHER row already holding [serverId] — called right before
  /// stamping a freshly-sent optimistic row with its server id, so the
  /// UPDATE cannot violate the unique index when the FCM isolate pre-cached
  /// the same message.
  Future<void> deleteByServerIdExcept(String serverId, String keepLocalId) =>
      (delete(messagesTable)
            ..where((t) =>
                t.serverId.equals(serverId) &
                t.localId.equals(keepLocalId).not()))
          .go();

  /// Removes existing rows for a batch of server ids so a following batch
  /// INSERT cannot collide (previously-cached rows hit the PK, FCM bg
  /// placeholders hit the unique serverId index — and ONE collision aborts
  /// the whole Drift batch, dropping the entire fetch). The batch rebuilds
  /// them from companions that carry the preserved flags. Chunked at 500
  /// for the same bind-variable cap as [getMessagesByServerIds].
  Future<void> deleteByServerIds(List<String> serverIds) async {
    if (serverIds.isEmpty) return;
    for (final chunk in chunkIds(serverIds, 500)) {
      await (delete(messagesTable)..where((t) => t.serverId.isIn(chunk)))
          .go();
    }
  }

  /// Stuck non-media rows whose ciphertext never decrypted (review I1:
  /// transient heal failures were previously skipped over forever by the
  /// cursor). Excludes pending optimistic rows (no serverId, `__pending__`
  /// marker) and media (their body is optional).
  ///
  /// T9 (column dropped): the old `decrypted_body IS NULL` filter becomes
  /// the state projection the T7 report ledgered — `decrypt_state IN
  /// ('pending','key_missing')` (exactly the states whose body is absent;
  /// `ready` rows re-decrypt lazily through the provider, `failed` is
  /// terminal, `__pending__`/media excluded as before).
  Future<List<MessagesTableData>> getUndecryptableRows(
      String conversationId,
      {int limit = 40}) =>
      (select(messagesTable)
            ..where((t) =>
                t.conversationId.equals(conversationId) &
                t.serverId.isNotNull() &
                t.isDeletedForMe.equals(false) &
                t.isDeletedForEveryone.equals(false) &
                t.decryptState.isIn(['pending', 'key_missing']) &
                t.type.isNotIn(['image', 'video', 'voice', 'document', 'file']) &
                t.encryptedBody.isNotValue('__pending__'))
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt,
                mode: OrderingMode.desc)])
            ..limit(limit))
          .get();

  Future<MessagesTableData?> getMessageByLocalId(String localId) =>
      (select(messagesTable)..where((t) => t.localId.equals(localId)))
          .getSingleOrNull();

  /// Single row for a serverId — the unique index guarantees one.
  /// Prefers the row whose body is RESIDENT in the session cache (legacy
  /// dupes may exist on devices that haven't run the v6 migration yet —
  /// pre-T9 this preferred a non-null `decryptedBody`; the cache is the
  /// same "already decrypted" predicate post-drop).
  Future<MessagesTableData?> getMessageByServerId(String serverId) async {
    final rows = await (select(messagesTable)
          ..where((t) => t.serverId.equals(serverId)))
        .get();
    if (rows.isEmpty) return null;
    if (rows.length == 1) return rows.first;
    return rows.firstWhere((r) => bodyCache.get(r.localId) != null,
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
      // T9: bodies live in the session cache — compare there (resident-
      // only; a cold cache degrades this guard to "no match", never a
      // false positive).
      if ((bodyCache.get(m.localId) ?? '') == body) return m;
    }
    return null;
  }

  Future<void> updateMessageStatus(String localId, String status) =>
      (update(messagesTable)..where((t) => t.localId.equals(localId))).write(
        MessagesTableCompanion(
          status:    Value(status),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Hard-deletes one local row — discardOp's cascade for an op whose
  /// message never reached the server (no server tombstone needed).
  Future<void> deleteByLocalId(String localId) =>
      (delete(messagesTable)..where((t) => t.localId.equals(localId))).go();

  /// Repair/self-heal success lands plaintext together with the state
  /// flip (Task 7): a `key_missing`/`pending` row that just decrypted
  /// reads `decrypt_state='ready'` — otherwise the state would lag the
  /// body until the next full re-cache.
  ///
  /// T9: the plaintext half now lands in the SESSION body cache (spec §3 —
  /// no plaintext at rest); the DB write is the state flip only.
  Future<void> cacheDecryptedBody(String localId, String decrypted) async {
    bodyCache.put(localId, decrypted);
    await (update(messagesTable)..where((t) => t.localId.equals(localId)))
        .write(const MessagesTableCompanion(
      decryptState: Value('ready'),
    ));
  }

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

  /// #71 Prewarm: the conversation-list preview's row — newest non-deleted
  /// message, exactly the shape/order `conversationLastMessageProvider`
  /// (message_body_provider.dart) watches, so the prewarmed row IS the row
  /// the home list renders. Any type: media/system previews are a constant
  /// widget-layer label and the caller skips non-text rows.
  Future<MessagesTableData?> newestVisibleMessage(String conversationId) =>
      (select(messagesTable)
            ..where((t) =>
                t.conversationId.equals(conversationId) &
                t.isDeletedForEveryone.equals(false) &
                t.isDeletedForMe.equals(false))
            ..orderBy([
              (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
              (t) => OrderingTerm(expression: t.serverId, mode: OrderingMode.desc),
              (t) => OrderingTerm(expression: t.localId, mode: OrderingMode.desc),
            ])
            ..limit(1))
          .getSingleOrNull();

  /// C1b: server-authoritative createdAt for a confirmed duplicate-create
  /// recovery. Lands BEFORE the drain-ack stamps serverId — between the
  /// two writes the row is excluded from [maxServerCreatedAt] (serverId
  /// still null), so the watermark can never see a device-clock time.
  Future<void> stampServerCreatedAt(String localId, DateTime createdAt) =>
      (update(messagesTable)..where((t) => t.localId.equals(localId)))
          .write(MessagesTableCompanion(createdAt: Value(createdAt)));

  /// F2b: newest server-backed message timestamp — the LOCAL watermark the
  /// resume delta query filters from. Device clock never participates
  /// (same rule as sync_cursor.dart: server time only).
  Future<DateTime?> maxServerCreatedAt() async {
    final q = selectOnly(messagesTable)
      ..addColumns([messagesTable.createdAt.max()])
      ..where(messagesTable.serverId.isNotNull());
    final row = await q.getSingle();
    return row.read(messagesTable.createdAt.max());
  }

  // ── Receipts ───────────────────────────────────────────────────

  Future<void> upsertReceipt(MessageReceiptsTableCompanion receipt) =>
      into(messageReceiptsTable).insertOnConflictUpdate(receipt);

  Future<List<MessageReceiptsTableData>> getReceiptsForMessage(
          String messageLocalId) =>
      (select(messageReceiptsTable)
            ..where((t) => t.messageLocalId.equals(messageLocalId)))
          .get();
}
