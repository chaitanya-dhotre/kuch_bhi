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

/// An invite as seen from the ADMIN side (group settings): the invitee,
/// not the inviter, is the interesting party.
class PendingGroupInvite {
  const PendingGroupInvite({
    required this.inviteId,
    required this.user,
    required this.status,
  });
  final String inviteId;
  final User   user;
  final String status; // pending | accepted | declined
}
