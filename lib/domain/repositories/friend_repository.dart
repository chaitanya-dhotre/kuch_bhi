import '../entities/friend_request.dart';
import '../entities/friendship.dart';
import '../entities/user.dart';

abstract class FriendRepository {

  /// Search for a user by their 6-character friend code.
  /// Returns null if no user found.
  Future<User?> findUserByCode(String code);

  /// Send a friend request to another user.
  Future<FriendRequest> sendRequest(String toUserId);

  /// Accept an incoming friend request.
  Future<void> acceptRequest(String requestId);

  /// Decline an incoming friend request.
  Future<void> declineRequest(String requestId);

  /// Get all incoming pending requests for the current user.
  Future<List<FriendRequest>> getIncomingRequests();

  /// Watch incoming requests in real-time.
  Stream<List<FriendRequest>> watchIncomingRequests();

  /// Get all confirmed friendships for the current user.
  Future<List<Friendship>> getFriendships();

  /// Watch friendships in real-time.
  Stream<List<Friendship>> watchFriendships();

  /// Set a local custom nickname for a friend.
  Future<void> setNickname(String friendshipId, String? nickname);

  /// Block a user.
  Future<void> blockUser(String userId);

  /// Unblock a user.
  Future<void> unblockUser(String userId);

  /// Returns IDs of users the current user has blocked.
  Future<List<String>> getBlockedUserIds();
}
