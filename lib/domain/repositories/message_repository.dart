import 'dart:io';

import '../../features/chat/providers/chat_provider.dart' show ReactionGroup;
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

  /// Send a media message (voice, image, video, document).
  /// Creates the message record first, then uploads the media file.
  Future<void> sendMediaMessage({
    required String conversationId,
    required String mediaType,
    required File mediaFile,
    File? thumbnailFile,
    String? quality,
    int? durationSeconds,
    String? durationText,
    int? videoWidth,
    int? videoHeight,
  });

  /// Mark all messages in a conversation as read by current user.
  Future<void> markConversationRead(String conversationId);

  /// Delete a message.
  Future<void> deleteMessage(String localId, {bool forEveryone = false});

  /// Toggle star on a message.
  Future<void> toggleStar(String localId);

  /// Toggle pin on a message.
  Future<void> togglePin(String localId, String conversationId, bool pin);

  /// Add or toggle a reaction on a server message.
  Future<void> addReaction(String messageServerId, String emoji);

  /// Remove a reaction by its server record ID.
  Future<void> removeReaction(String reactionId);

  /// Get grouped reactions for a server message.
  Future<List<ReactionGroup>> getReactions(String messageServerId);

  /// Emits the serverId of a message whenever its reactions change.
  Stream<String> get reactionsChanges;

  /// Get starred messages for a conversation.
  Future<List<Message>> getStarredMessages(String conversationId);

  /// Get pinned messages for a conversation.
  Future<List<Message>> getPinnedMessages(String conversationId);

  /// Search decrypted messages within a conversation.
  Future<List<Message>> searchMessages(String conversationId, String query);

  /// Update the disappearing-message duration for a conversation.
  Future<void> setDisappearingDuration(String conversationId, int seconds);

  /// Retry all pending (failed) messages.
  Future<void> retryPendingMessages();

  /// Retry a specific failed message using its existing localId.
  /// Does NOT create a new message entry.
  Future<void> retryMessage(String localId);

  /// Fetch older messages (pagination).
  Future<void> loadMoreMessages(String conversationId, int offset);
}
