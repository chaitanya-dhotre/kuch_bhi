import 'package:drift/drift.dart';

/// Cached user profiles — both the current user and contacts.
class UsersTable extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text()();
  TextColumn get username => text()();
  TextColumn get email => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get about => text().nullable()();
  TextColumn get friendCode => text()();
  BoolColumn get isOnline => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastSeen => dateTime().nullable()();
  TextColumn get publicKey => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
