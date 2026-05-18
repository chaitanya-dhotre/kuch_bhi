import 'package:drift/drift.dart';

/// Cached conversation metadata for both direct and group chats.
class ConversationsTable extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()(); // 'direct' | 'group'
  TextColumn get name => text().nullable()(); // groups only
  TextColumn get iconUrl => text().nullable()(); // groups only
  TextColumn get createdById => text()();
  TextColumn get lastMessagePreview => text().nullable()();
  DateTimeColumn get lastMessageAt => dateTime().nullable()();
  IntColumn get disappearingDuration => integer().withDefault(const Constant(0))();
  BoolColumn get onlyAdminsCanMessage => boolean().withDefault(const Constant(false))();
  // Local-only fields (never synced to server)
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get muteUntil => dateTime().nullable()();
  TextColumn get wallpaperPath => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
