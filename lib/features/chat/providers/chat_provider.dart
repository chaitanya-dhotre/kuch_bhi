import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/message.dart';
import '../../../domain/entities/user.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../../services/media_upload_service.dart';

final activeConversationProvider = StateProvider<Conversation?>((ref) => null);

// ── Decrypted media cache ─────────────────────────────────────────────────
// Media is E2E-encrypted on the server, so bubbles download + decrypt to a
// local cleartext file. Cached for the session so scrolling never re-decrypts.

/// Identifies a media file to fetch: its conversation (for the key) + the
/// message server id + whether we want the thumbnail variant.
class MediaRef {
  const MediaRef(this.conversationId, this.serverId, {this.thumb = false});
  final String conversationId;
  final String serverId;
  final bool thumb;

  @override
  bool operator ==(Object other) =>
      other is MediaRef &&
      other.conversationId == conversationId &&
      other.serverId == serverId &&
      other.thumb == thumb;

  @override
  int get hashCode => Object.hash(conversationId, serverId, thumb);
}

/// Downloads + decrypts the full media file (image/video/voice/document).
final mediaFileProvider =
    FutureProvider.family<LocalMediaFile?, MediaRef>((ref, r) {
  return ref.read(messageRepositoryProvider).getDecryptedMedia(
        r.conversationId, r.serverId, thumb: r.thumb);
});

// ── Messages (reactive Drift stream) ─────────────────────────────────────

final messagesProvider =
    StreamProvider.family<List<Message>, String>((ref, conversationId) {
  return ref
      .watch(messageRepositoryProvider)
      .watchMessages(conversationId);
});

// ── Send ──────────────────────────────────────────────────────────────────

class SendMessageNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void send({
    required String conversationId,
    required String text,
    String? replyToLocalId,
    String? replyPreview,
  }) {
    if (text.trim().isEmpty) return;
    ref.read(messageRepositoryProvider).sendMessage(
      conversationId: conversationId,
      plaintext:      text.trim(),
      replyToLocalId: replyToLocalId,
      replyPreview:   replyPreview,
    );
  }
}

final sendMessageProvider =
    NotifierProvider<SendMessageNotifier, bool>(SendMessageNotifier.new);

// ── Send media message ─────────────────────────────────────────────────────

class SendMediaMessageNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> send({
    required String conversationId,
    required String mediaType,
    required File mediaFile,
    File? thumbnailFile,
    String? quality,
    int? durationSeconds,
    String? durationText,
    int? videoWidth,
    int? videoHeight,
  }) async {
    await ref.read(messageRepositoryProvider).sendMediaMessage(
      conversationId:  conversationId,
      mediaType:       mediaType,
      mediaFile:       mediaFile,
      thumbnailFile:   thumbnailFile,
      quality:         quality,
      durationSeconds: durationSeconds,
      durationText:    durationText,
      videoWidth:      videoWidth,
      videoHeight:     videoHeight,
    );
  }
}

final sendMediaMessageProvider =
    NotifierProvider<SendMediaMessageNotifier, bool>(
        SendMediaMessageNotifier.new);

// ── Reply context ─────────────────────────────────────────────────────────

/// The message currently being replied to. Null = no reply in progress.
final replyProvider = StateProvider<Message?>((ref) => null);

// ── Search ────────────────────────────────────────────────────────────────

final searchActiveProvider  = StateProvider<bool>((ref) => false);
final searchQueryProvider   = StateProvider<String>((ref) => '');

// ── Pinned messages ───────────────────────────────────────────────────────

final pinnedMessagesProvider =
    StreamProvider.autoDispose.family<List<Message>, String>((ref, convId) {
  return ref.read(messageRepositoryProvider).watchPinnedMessages(convId);
});

// ── Reactions per message ─────────────────────────────────────────────────

/// Reactive reactions provider — re-fetches whenever the repository
/// broadcasts a change for this specific message.
final reactionsProvider = StreamProvider.autoDispose
    .family<List<ReactionGroup>, String>((ref, serverId) async* {
  final repo = ref.read(messageRepositoryProvider);

  // Emit initial data immediately
  yield await repo.getReactions(serverId);

  // Re-emit whenever any reaction changes for THIS message
  await for (final changedId
      in repo.reactionsChanges.where((id) => id == serverId)) {
    yield await repo.getReactions(serverId);
  }
});

class ReactionGroup {
  const ReactionGroup({
    required this.emoji,
    required this.count,
    required this.isMine,
    this.reactionId,
  });
  final String  emoji;
  final int     count;
  final bool    isMine;
  final String? reactionId; // null when isMine is false
}

// ── Current user ──────────────────────────────────────────────────────────

final currentUserIdProvider = FutureProvider<String>((ref) async {
  final db = ref.read(appDatabaseProvider);
  return await db.settingsDao.getSetting('current_user_id') ?? '';
});

// ── Group members ─────────────────────────────────────────────────────────

final groupMembersProvider = StreamProvider.autoDispose
    .family<List<User>, String>((ref, conversationId) {
  return ref
      .watch(messageRepositoryProvider)
      .watchGroupMembers(conversationId);
});

// ── Conversation stream ────────────────────────────────────────────────────

final conversationStreamProvider = StreamProvider.autoDispose
    .family<Conversation?, String>((ref, conversationId) {
  return ref
      .watch(messageRepositoryProvider)
      .watchConversation(conversationId);
});
