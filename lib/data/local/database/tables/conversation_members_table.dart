import 'package:drift/drift.dart';

class ConversationMembersTable extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get userId => text()();
  TextColumn get role => text().withDefault(const Constant('member'))();
  DateTimeColumn get joinedAt => dateTime()();
  TextColumn get lastReadMessageId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
