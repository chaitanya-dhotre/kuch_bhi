import 'package:drift/drift.dart';

/// Cached conversation metadata for both direct and group chats.
class ConversationsTable extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()(); // 'direct' | 'group'
  TextColumn get name => text().nullable()(); // groups only
  TextColumn get iconUrl => text().nullable()(); // groups only
  TextColumn get createdById => text()();
  // P7 (spec §3 / schema v11): `lastMessagePreview` is DROPPED — the
  // conversation-list preview DERIVES from the newest message row through
  // `messageBodyProvider` at render time (type labels for media/system rows
  // are constants computed in the widget). No plaintext preview at rest.
  DateTimeColumn get lastMessageAt => dateTime().nullable()();
  IntColumn get disappearingDuration => integer().withDefault(const Constant(0))();
  BoolColumn get onlyAdminsCanMessage => boolean().withDefault(const Constant(false))();
  // Local-only fields (never synced to server)
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  TextColumn get lastReadLocalId => text().nullable()();
  DateTimeColumn get muteUntil => dateTime().nullable()();
  TextColumn get wallpaperPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
