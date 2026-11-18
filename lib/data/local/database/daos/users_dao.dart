import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/users_table.dart';

part 'users_dao.g.dart';

@DriftAccessor(tables: [UsersTable])
class UsersDao extends DatabaseAccessor<AppDatabase> with _$UsersDaoMixin {
  UsersDao(super.db);

  /// Upsert a user — insert or update if already exists.
  Future<void> upsertUser(UsersTableCompanion user) async {
    await into(usersTable).insertOnConflictUpdate(user);
    await _observeKey(user);
  }

  /// Upsert multiple users at once.
  Future<void> upsertUsers(List<UsersTableCompanion> users) async {
    await batch((b) => b.insertAllOnConflictUpdate(usersTable, users));
    for (final u in users) {
      await _observeKey(u);
    }
  }

  /// Audit F3 (spec A2): every server key passes the pin check here, the one
  /// funnel all user fetches share. `users.public_key` stays display-only.
  Future<void> _observeKey(UsersTableCompanion u) async {
    if (!u.id.present || !u.publicKey.present) return;
    await attachedDatabase.contactKeys.observe(u.id.value, u.publicKey.value);
  }

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
