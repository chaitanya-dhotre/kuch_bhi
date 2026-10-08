import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'migrations/dedup_sql.dart';
import 'tables/users_table.dart';
import 'tables/conversations_table.dart';
import 'tables/conversation_members_table.dart';
import 'tables/messages_table.dart';
import 'tables/message_receipts_table.dart';
import 'tables/message_media_table.dart';
import 'tables/friendships_table.dart';
import 'tables/friend_requests_table.dart';
import 'tables/reactions_table.dart';
import 'tables/app_settings_table.dart';
import 'tables/message_drafts_table.dart';
import 'tables/outbox_table.dart';
import 'tables/media_blob_table.dart';
import 'daos/users_dao.dart';
import 'daos/conversations_dao.dart';
import 'daos/messages_dao.dart';
import 'daos/friends_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/outbox_dao.dart';
import 'daos/media_blob_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    UsersTable,
    ConversationsTable,
    ConversationMembersTable,
    MessagesTable,
    MessageReceiptsTable,
    MessageMediaTable,
    FriendshipsTable,
    FriendRequestsTable,
    ReactionsTable,
    AppSettingsTable,
    MessageDraftsTable,
    OutboxTable,
    MediaBlobTable,
  ],
  daos: [
    UsersDao,
    ConversationsDao,
    MessagesDao,
    FriendsDao,
    SettingsDao,
    OutboxDao,
    MediaBlobDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// In-memory constructor for unit tests — no path_provider / platform
  /// channels, no persistence.
  AppDatabase.test() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(messagesTable, messagesTable.mediaId);
          }
          if (from < 3) {
            await m.addColumn(
                conversationsTable, conversationsTable.onlyAdminsCanMessage);
          }
          if (from < 4) {
            await m.addColumn(
                conversationMembersTable, conversationMembersTable.role);
          }
          if (from < 5) {
            await m.addColumn(
                conversationsTable, conversationsTable.unreadCount);
            await m.addColumn(
                conversationsTable, conversationsTable.lastReadLocalId);
          }
          if (from < 6) {
            // Duplicate rows (FCM background-isolate races) would break
            // UNIQUE index creation — dedupe first, then build the index.
            await customStatement(DedupBeforeUniqueIndex.sql);
            await customStatement(
                'CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_server_id '
                'ON messages_table (server_id)');
          }
          if (from < 7) {
            // Offline-first: the Drift table IS the outbox queue (spec §5.2).
            await m.createTable(outboxTable);
          }
          if (from < 8) {
            // MediaBlobStore FSM rows (spec §5.3 / §9) — sole writer.
            await m.createTable(mediaBlobTable);
          }
          if (from < 9) {
            // Always-commit policy (Task 7, spec §5.1): decrypt_state
            // defaults 'ready' so legacy rows (they carry decrypted_body)
            // read as decryptable; key_id nullable — Task 8 wires it.
            await m.addColumn(messagesTable, messagesTable.decryptState);
            await m.addColumn(messagesTable, messagesTable.keyId);
          }
        },
      );
}

/// Opens the SQLite connection. Runs on a background isolate
/// automatically via drift's lazy initialization.
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'kuch_bhi.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// Global Riverpod provider for the database.
/// Use this everywhere — never instantiate AppDatabase directly.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
