import 'package:drift/drift.dart';

/// Tracks delivery and read status per recipient per message.
/// This is the backbone of the tick system.
class MessageReceiptsTable extends Table {
  TextColumn get id => text()();
  TextColumn get messageLocalId => text()();
  TextColumn get conversationId => text()();
  TextColumn get recipientId => text()();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
