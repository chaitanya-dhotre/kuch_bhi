class Message {
  const Message({
    required this.localId,
    this.serverId,
    required this.conversationId,
    required this.senderId,
    required this.type,
    this.decryptedBody,
    this.replyToId,
    this.isDeletedForEveryone = false,
    this.isDeletedForMe = false,
    this.isPinned = false,
    this.isStarred = false,
    required this.status,
    required this.createdAt,
    this.mediaId,
  });

  final String  localId;
  final String? serverId;
  final String  conversationId;
  final String  senderId;
  final String  type; // text | image | video | voice | poll | system
  final String? decryptedBody;
  final String? replyToId;
  final bool    isDeletedForEveryone;
  final bool    isDeletedForMe;
  final bool    isPinned;
  final bool    isStarred;
  final String  status; // pending | sent | delivered | read | failed
  final DateTime createdAt;
  final String? mediaId;

  bool get isPending   => status == 'pending';
  bool get isSent      => status == 'sent';
  bool get isDelivered => status == 'delivered';
  bool get isRead      => status == 'read';
  bool get isFailed    => status == 'failed';
}
