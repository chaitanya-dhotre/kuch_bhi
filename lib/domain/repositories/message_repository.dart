import 'dart:io';

import '../../features/chat/providers/chat_provider.dart' show ReactionGroup;
import '../../services/media_upload_service.dart' show LocalMediaFile;
import '../entities/conversation.dart';
import '../entities/group_invite.dart';
import '../entities/message.dart';
import '../entities/user.dart';

/// One album item, already compressed (12.5). Takes files, not picker
/// results, so share-in (12.1) can feed the same call.
typedef AlbumSendItem = ({
  String mediaType,
  File mediaFile,
  File? thumbnailFile,
  int? durationSeconds,
  String? durationText,
  int? videoWidth,
  int? videoHeight,
});

abstract class MessageRepository {
  /// #74 tap-down predecrypt: warm the body cache for the newest [limit]
  /// body-rendering rows of [conversationId] when its list row is
  /// PRESSED — the ~250ms open transition hides the decrypt work, so the
  /// first bubble build resolves straight from cache (Astra rec:
  /// tap→text ≤100ms p95). Local-only; failures never block navigation.
  Future<void> predecryptConversation(String conversationId, {int limit = 30});

  /// Get or create a direct conversation with another user.
  Future<Conversation> getOrCreateDirectConversation(String otherUserId);

  /// Watch all conversations (real-time).
  Stream<List<Conversation>> watchConversations();

  /// Watch messages in a conversation (real-time, paginated).
  Stream<List<Message>> watchMessages(String conversationId);

  /// How many rows in [conversationId] exist but are NOT renderable because
  /// their body cannot be decrypted (backlog §170 fix b).
  ///
  /// `watchMessages` hides them (spec D1 — ciphertext never reaches a bubble),
  /// so a conversation with only undecryptable history yields an empty list
  /// that is indistinguishable at the screen from a brand-new chat. This count
  /// is what lets the empty state say "old messages need re-sharing" instead
  /// of "Say hello". Never exposes ciphertext or plaintext — just a number.
  Future<int> countUndecryptable(String conversationId);

  /// Send a text message.
  ///
  /// P7 (spec §3): there is deliberately NO `replyPreview` parameter — a
  /// preview is derived where it is needed (the UI derives the quote from
  /// the parent row via `messageBodyProvider`; the drain derives the
  /// server-bound preview from the same row). Nothing preview-shaped is
  /// ever handed to the repository for storage.
  Future<void> sendMessage({
    required String conversationId,
    required String plaintext,
    String? replyToLocalId,
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

  /// Albums (12.5 B7): [items] in pick order become one album (2–20 photos
  /// and videos). Each is its own row and send; uploads then run one at a
  /// time in index order through the resume pass.
  Future<void> sendMediaAlbum({
    required String conversationId,
    required List<AlbumSendItem> items,
    String? quality,
  });

  /// Stops an own media send that has not finished: the bubble and its
  /// files go, and a server copy is marked deleted for everyone. False when
  /// the message was already sent (nothing to cancel).
  Future<bool> cancelMediaUpload(String localId);

  /// Mark all messages in a conversation as read by current user.
  Future<void> markConversationRead(String conversationId);

  /// Delete a message.
  Future<void> deleteMessage(String localId, {bool forEveryone = false});

  /// Toggle star on a message.
  Future<void> toggleStar(String localId);

  /// 12.8 D6: star or unstar many rows. Writes the phone and returns; the
  /// server writes follow one at a time in the background (creates paced).
  Future<void> setStarred(List<String> localIds, bool starred);

  /// Toggle pin on a message.
  Future<void> togglePin(String localId, String conversationId, bool pin);

  /// Add or toggle a reaction on a server message.
  Future<void> addReaction(String messageServerId, String emoji);

  /// Remove a reaction by its server record ID.
  Future<void> removeReaction(String reactionId);

  /// Get grouped reactions for a server message.
  Future<List<ReactionGroup>> getReactions(String messageServerId);

  /// Grouped reactions for a server message from the local store, emitting
  /// again on every local change or synced server read (offline-first).
  Stream<List<ReactionGroup>> watchReactions(String messageServerId);

  /// Pulls the server's reactions for one message into the local store,
  /// keeping queued adds and removes. Offline or on error it changes nothing.
  Future<void> refreshReactions(String messageServerId);

  /// Emits the serverId of a message whenever its reactions change.
  Stream<String> get reactionsChanges;

  /// Emits the message serverId whenever a `message_media` record for it is
  /// created or updated on the server. Lets a bubble that raced the sender's
  /// upload (message row exists, media row not yet) re-fetch and render.
  Stream<String> get mediaChanges;

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
  Future<void> syncAllHistory({void Function(HistorySyncProgress)? onProgress});

  /// Search decrypted messages within a conversation.
  Future<List<Message>> searchMessages(String conversationId, String query);

  /// Update the disappearing-message duration for a conversation.
  Future<void> setDisappearingDuration(String conversationId, int seconds);

  /// Full resync after the app returns to the foreground: reconnects the
  /// realtime subscriptions (Android suspends the SSE socket in background)
  /// and refetches recent messages + receipts so nothing stays stale.
  /// [awayFor] = how long the app was backgrounded (null = cold start /
  /// unknown). Under 60s the repo takes a light path — one aggregate delta
  /// query instead of the all-conversation backfill scan (F2b, 2026-10-14).
  Future<void> resyncOnResume({Duration? awayFor});

  /// Retry all pending (failed) messages.
  Future<void> retryPendingMessages();

  /// True when this device can encrypt/decrypt for [conversationId]
  /// (always true for DMs; groups require a distributed key).
  Future<bool> hasUsableKey(String conversationId);

  /// Retry a specific failed message using its existing localId.
  /// Does NOT create a new message entry.
  Future<void> retryMessage(String localId);

  /// Re-queue one outbox op (typically `failedTerminal`): clears its retry
  /// metadata back to NULL/0, unsticks the message row, drains. Task 4's
  /// terminal banner Retry action.
  Future<void> retryOp(String opId);

  /// Discard one outbox op: cascades to every op that (transitively)
  /// `dependsOn` it and deletes their local message rows, then drains.
  /// Task 4's terminal banner Discard action.
  Future<void> discardOp(String opId);

  /// Fetch older messages (pagination). Throws on failure (8s bound) so the
  /// caller keeps its offset instead of skipping the page.
  Future<void> loadMoreMessages(String conversationId, int offset);

  /// Fetch and cache a single message by its server ID.
  Future<void> fetchAndCacheSingleMessage(String messageId, String conversationId);

  // ── Group admin ────────────────────────────────────────────────

  /// Returns true if the current user is an admin in [conversationId].
  Future<bool> isCurrentUserAdmin(String conversationId);

  /// Returns all members of a group conversation as User entities.
  Future<List<User>> getGroupMembers(String conversationId);

  /// Sends (or re-sends) a group invite to [userId] (caller must be admin).
  /// Idempotent per (conversation, user): an existing row is PATCHed back
  /// to 'pending' instead of creating a duplicate.
  Future<void> sendGroupInvite(String conversationId, String userId);

  /// My pending incoming group invites, newest first.
  Future<List<GroupInvite>> getIncomingGroupInvites();

  /// Accept: creates my own membership row, marks the invite accepted,
  /// syncs the conversation locally, then emits "X joined the group" once
  /// the group key is distributed (bounded wait).
  Future<void> acceptGroupInvite(String inviteId);

  /// Decline: marks the invite declined. Nothing else.
  Future<void> declineGroupInvite(String inviteId);

  /// userId -> invite status for a conversation (picker chips).
  Future<Map<String, String>> getInviteStatusesForConversation(
      String conversationId);

  /// All invites for a conversation, admin side (group settings list).
  /// [PendingGroupInvite.user] is the invitee.
  Future<List<PendingGroupInvite>> getPendingInvitesForConversation(
      String conversationId);

  /// Cancel (delete) an invite row (admin or invitee; server rule checks).
  Future<void> cancelGroupInvite(String inviteId);

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

/// One step of [MessageRepository.syncAllHistory]. Reported through the
/// `onProgress` callback so the UI can show a live progress message
/// instead of a single static "processing…" string. [current]/[total]
/// are non-null for the per-page download phase, null otherwise.
class HistorySyncProgress {
  const HistorySyncProgress({
    required this.phase,
    this.conversationIndex,
    this.conversationCount,
    this.messageCurrent,
    this.messageTotal,
  });

  /// High-level phase label — keys the UI to a friendly message and icon.
  final HistorySyncPhase phase;

  /// 1-based index of the conversation currently being synced (null
  /// during account-wide phases).
  final int? conversationIndex;

  /// Total number of conversations that need history.
  final int? conversationCount;

  /// For the download phase: 1-based index of the message currently being
  /// pulled from the server.
  final int? messageCurrent;

  /// For the download phase: total message count across the conversation.
  final int? messageTotal;
}

enum HistorySyncPhase {
  /// Re-downloading the user's conversation list.
  fetchingConversations,

  /// Pulling all messages for one conversation, page by page.
  downloadingMessages,

  /// Running per-conv sync of delete-for-me + starred messages.
  finalisingConversation,

  /// All conversations done.
  complete,
}
