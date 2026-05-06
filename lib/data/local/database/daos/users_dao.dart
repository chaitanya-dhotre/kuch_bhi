import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/users_table.dart';

part 'users_dao.g.dart';

@DriftAccessor(tables: [UsersTable])
class UsersDao extends DatabaseAccessor<AppDatabase> with _$UsersDaoMixin {
  UsersDao(super.db);

  /// Upsert a user — insert or update if already exists.
  Future<void> upsertUser(UsersTableCompanion user) =>
      into(usersTable).insertOnConflictUpdate(user);

  /// Upsert multiple users at once.
  Future<void> upsertUsers(List<UsersTableCompanion> users) =>
      batch((b) => b.insertAllOnConflictUpdate(usersTable, users));

  /// Get a single user by ID.
  Future<UsersTableData?> getUserById(String id) =>
      (select(usersTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// Watch a user — updates reactively when data changes.
  Stream<UsersTableData?> watchUserById(String id) =>
      (select(usersTable)..where((t) => t.id.equals(id)))
          .watchSingleOrNull();

  /// Get user by friend code.
  Future<UsersTableData?> getUserByFriendCode(String code) =>
      (select(usersTable)..where((t) => t.friendCode.equals(code)))
          .getSingleOrNull();

  /// Delete a user record.
  Future<int> deleteUser(String id) =>
      (delete(usersTable)..where((t) => t.id.equals(id))).go();
}
