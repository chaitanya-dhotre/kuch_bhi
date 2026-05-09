import 'user.dart';

class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.fromUser,
    required this.toUser,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final User fromUser;
  final User toUser;

  /// 'pending' | 'accepted' | 'declined'
  final String status;
  final DateTime createdAt;

  bool get isPending  => status == 'pending';
  bool get isAccepted => status == 'accepted';
}
