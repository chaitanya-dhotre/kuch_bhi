import '../entities/conversation.dart';
import '../entities/message.dart';

abstract class MessageRepository {
  /// Get or create a direct conversation with another user.
  Future<Conversation> getOrCreateDirectConversation(String otherUserId);

  /// Watch all conversations (real-time).
  Stream<List<Conversation>> watchConversations();

  /// Watch messages in a conversation (real-time, paginated).
  Stream<List<Message>> watchMessages(String conversationId);

  /// Send a text message.
  Future<void> sendMessage({
    required String conversationId,
    required String plaintext,
    String? replyToLocalId,
    String? replyPreview,
  });

  /// Mark all messages in a conversation as read by current user.
  Future<void> markConversationRead(String conversationId);

  /// Delete a message.
  Future<void> deleteMessage(String localId, {bool forEveryone = false});

  /// Toggle star on a message.
  Future<void> toggleStar(String localId);

  /// Retry all pending (failed) messages.
  Future<void> retryPendingMessages();

  /// Retry a specific failed message using its existing localId.
  /// Does NOT create a new message entry.
  Future<void> retryMessage(String localId);

  /// Fetch older messages (pagination).
  Future<void> loadMoreMessages(String conversationId, int offset);
}
