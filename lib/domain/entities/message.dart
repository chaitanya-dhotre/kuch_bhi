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
    this.decryptState = 'ready',
    this.ciphertextLength = 0,
    this.albumId,
    this.albumIndex,
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

  /// UI projection of the row's decrypt lifecycle. Defaults to the legacy
  /// ready state so existing entity callers remain source-compatible.
  final String decryptState;

  /// Existing ciphertext length used only for transient placeholder sizing.
  final int ciphertextLength;

  /// Albums: item 0's record id, shared by every item sent together; null
  /// = not in an album. [albumIndex] is the pick order.
  final String? albumId;
  final int? albumIndex;

  bool get isPending   => status == 'pending';
  bool get isSent      => status == 'sent';
  bool get isDelivered => status == 'delivered';
  bool get isRead      => status == 'read';
  bool get isFailed    => status == 'failed';
}
