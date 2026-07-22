import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'daos/users_dao.dart';
import 'daos/conversations_dao.dart';
import 'daos/messages_dao.dart';
import 'daos/friends_dao.dart';
import 'daos/settings_dao.dart';

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
  ],
  daos: [
    UsersDao,
    ConversationsDao,
    MessagesDao,
    FriendsDao,
    SettingsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4;

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
