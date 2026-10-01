import 'user.dart';

/// A group invite row from the PB `group_invites` collection.
class GroupInvite {
  const GroupInvite({
    required this.id,
    required this.conversationId,
    required this.conversationName,
    required this.invitedBy,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String conversationName;

  /// User who sent the invite.
  final User invitedBy;

  /// 'pending' | 'accepted' | 'declined'
  final String status;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
}
