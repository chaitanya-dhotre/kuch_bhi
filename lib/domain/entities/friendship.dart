import 'user.dart';

class Friendship {
  const Friendship({
    required this.id,
    required this.friend,
    required this.createdAt,
    this.customNickname,
  });

  final String id;

  /// The other user in the friendship (not the current user).
  final User friend;
  final DateTime createdAt;

  /// Local-only nickname. Never sent to server.
  final String? customNickname;

  /// Display name respects custom nickname if set.
  String get displayName => customNickname ?? friend.displayName;
}
