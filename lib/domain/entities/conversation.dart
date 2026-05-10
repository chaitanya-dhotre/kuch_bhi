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

  String  get displayName => type == 'direct'
      ? (otherUser?.displayName ?? 'Unknown')
      : (name ?? 'Group Chat');

  String? get avatarUrl   => otherUser?.avatarUrl;
  bool    get isOnline    => otherUser?.isOnline ?? false;
}
