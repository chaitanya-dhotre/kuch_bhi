import 'dart:io';

import '../../features/chat/providers/chat_provider.dart' show ReactionGroup;
import '../../services/media_upload_service.dart' show LocalMediaFile;
import '../entities/conversation.dart';
import '../entities/message.dart';
import '../entities/user.dart';

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

  /// Watch pinned messages reactively (live updates without reopening).
  Stream<List<Message>> watchPinnedMessages(String conversationId);

  /// Downloads + decrypts a media file for a message. [thumb] returns the
  /// thumbnail variant. Returns the local cleartext file + metadata.
  Future<LocalMediaFile?> getDecryptedMedia(
    String conversationId,
    String messageServerId, {
    bool thumb,
  });

  /// After a reinstall + key restore, re-downloads and decrypts the full
  /// message history for every conversation the user belongs to. Safe to call
  /// multiple times (idempotent via serverId dedup).
  Future<void> syncAllHistory();

  /// Search decrypted messages within a conversation.
  Future<List<Message>> searchMessages(String conversationId, String query);

  /// Update the disappearing-message duration for a conversation.
  Future<void> setDisappearingDuration(String conversationId, int seconds);

  /// Full resync after the app returns to the foreground: reconnects the
  /// realtime subscriptions (Android suspends the SSE socket in background)
  /// and refetches recent messages + receipts so nothing stays stale.
  Future<void> resyncOnResume();

  /// Retry all pending (failed) messages.
  Future<void> retryPendingMessages();

  /// Retry a specific failed message using its existing localId.
  /// Does NOT create a new message entry.
  Future<void> retryMessage(String localId);

  /// Fetch older messages (pagination).
  Future<void> loadMoreMessages(String conversationId, int offset);

  /// Fetch and cache a single message by its server ID.
  Future<void> fetchAndCacheSingleMessage(String messageId, String conversationId);

  // ── Group admin ────────────────────────────────────────────────

  /// Returns true if the current user is an admin in [conversationId].
  Future<bool> isCurrentUserAdmin(String conversationId);

  /// Returns all members of a group conversation as User entities.
  Future<List<User>> getGroupMembers(String conversationId);

  /// Add a user to a group (caller must be admin).
  Future<void> addMemberToGroup(String conversationId, String userId);

  /// Remove a member from a group (caller must be admin). Rotates group key.
  Future<void> removeMemberFromGroup(String conversationId, String userId);

  /// Promote a member to admin.
  Future<void> promoteMemberToAdmin(String conversationId, String userId);

  /// Demote an admin to member.
  Future<void> demoteAdminToMember(String conversationId, String userId);

  /// Toggle the only-admins-can-message setting (caller must be admin).
  Future<void> setOnlyAdminsCanMessage(String conversationId, bool value);

  /// Leave the group. Promotes another member first if caller is sole admin.
  Future<void> leaveGroup(String conversationId);

  /// Update group info (name and/or icon). Caller must be admin.
  Future<void> updateGroupInfo(String conversationId,
      {String? name, File? iconFile});

  /// Watch a single conversation reactively.
  Stream<Conversation?> watchConversation(String conversationId);

  /// Watch group members reactively.
  Stream<List<User>> watchGroupMembers(String conversationId);
}
