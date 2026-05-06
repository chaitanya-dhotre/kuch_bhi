import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/friendships_table.dart';
import '../tables/friend_requests_table.dart';

part 'friends_dao.g.dart';

@DriftAccessor(tables: [FriendshipsTable, FriendRequestsTable])
class FriendsDao extends DatabaseAccessor<AppDatabase>
    with _$FriendsDaoMixin {
  FriendsDao(super.db);

  Future<void> upsertFriendship(FriendshipsTableCompanion friendship) =>
      into(friendshipsTable).insertOnConflictUpdate(friendship);

  Future<List<FriendshipsTableData>> getAllFriendships() =>
      select(friendshipsTable).get();

  Stream<List<FriendshipsTableData>> watchAllFriendships() =>
      select(friendshipsTable).watch();

  Future<void> setCustomNickname(String friendshipId, String? nickname) =>
      (update(friendshipsTable)
            ..where((t) => t.id.equals(friendshipId)))
          .write(FriendshipsTableCompanion(
        customNickname: Value(nickname),
      ));

  Future<void> deleteFriendship(String id) =>
      (delete(friendshipsTable)..where((t) => t.id.equals(id))).go();

  // --- Requests ---

  Future<void> upsertFriendRequest(
          FriendRequestsTableCompanion request) =>
      into(friendRequestsTable).insertOnConflictUpdate(request);

  Stream<List<FriendRequestsTableData>> watchPendingRequests(
          String currentUserId) =>
      (select(friendRequestsTable)
            ..where((t) =>
                t.toUserId.equals(currentUserId) &
                t.status.equals('pending')))
          .watch();

  Future<void> updateRequestStatus(String id, String status) =>
      (update(friendRequestsTable)..where((t) => t.id.equals(id))).write(
        FriendRequestsTableCompanion(status: Value(status)),
      );
}
