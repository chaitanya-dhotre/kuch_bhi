import 'user.dart';

class Conversation {
  const Conversation({
    required this.id,
    required this.type,
    this.name,
    this.iconUrl,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.isPinned = false,
    this.unreadCount = 0,
    this.otherUser,
    this.onlyAdminsCanMessage = false,
    this.memberCount,
  });

  final String    id;
  final String    type; // direct | group
  final String?   name;
  final String?   iconUrl;
  final String?   lastMessagePreview;
  final DateTime? lastMessageAt;
  final bool      isPinned;
  final int       unreadCount;
  final User?     otherUser; // populated for direct chats
  final bool      onlyAdminsCanMessage;
  final int?      memberCount;

  bool    get isGroup     => type == 'group';

  String  get displayName => isGroup
      ? (name ?? 'Group Chat')
      : (otherUser?.displayName ?? 'Unknown');

  String? get avatarUrl   => isGroup ? iconUrl : otherUser?.avatarUrl;
  bool    get isOnline    => otherUser?.isOnline ?? false;
}
