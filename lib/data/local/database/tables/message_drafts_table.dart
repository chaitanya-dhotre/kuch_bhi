import 'package:drift/drift.dart';

/// Persists in-progress message text per conversation.
class MessageDraftsTable extends Table {
  TextColumn get conversationId => text()();
  TextColumn get draftText => text()();
  TextColumn get replyToLocalId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {conversationId};
}
