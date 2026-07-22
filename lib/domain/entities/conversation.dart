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
    this.memberCount = 0,
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
  final int       memberCount;

  bool    get isGroup     => type == 'group';

  String  get displayName => isGroup
      ? (name ?? 'Group')
      : (otherUser?.displayName ?? 'Unknown');

  String? get avatarUrl   => isGroup ? iconUrl : otherUser?.avatarUrl;
  bool    get isOnline    => otherUser?.isOnline ?? false;

  Conversation copyWith({
    String? id,
    String? type,
    String? name,
    String? iconUrl,
    String? lastMessagePreview,
    DateTime? lastMessageAt,
    bool? isPinned,
    int? unreadCount,
    User? otherUser,
    bool? onlyAdminsCanMessage,
    int? memberCount,
  }) {
    return Conversation(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      iconUrl: iconUrl ?? this.iconUrl,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      isPinned: isPinned ?? this.isPinned,
      unreadCount: unreadCount ?? this.unreadCount,
      otherUser: otherUser ?? this.otherUser,
      onlyAdminsCanMessage: onlyAdminsCanMessage ?? this.onlyAdminsCanMessage,
      memberCount: memberCount ?? this.memberCount,
    );
  }
}
