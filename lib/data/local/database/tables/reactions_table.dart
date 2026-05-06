import 'package:drift/drift.dart';

class ReactionsTable extends Table {
  TextColumn get id => text()();
  TextColumn get messageLocalId => text()();
  TextColumn get conversationId => text()();
  TextColumn get userId => text()();
  TextColumn get emoji => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
