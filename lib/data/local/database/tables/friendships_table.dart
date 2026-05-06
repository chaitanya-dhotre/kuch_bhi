import 'package:drift/drift.dart';

class FriendshipsTable extends Table {
  TextColumn get id => text()();
  TextColumn get userAId => text()();
  TextColumn get userBId => text()();

  /// Local-only nickname for the other user. Never synced to server.
  TextColumn get customNickname => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
