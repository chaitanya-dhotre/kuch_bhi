import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database/app_database.dart';
import '../../../data/local/database/tables/media_blob_table.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/message.dart';
import '../../../domain/entities/user.dart';
import '../../../infrastructure/media/media_blob_store.dart' show mediaBlobId;
import '../../../infrastructure/offline/connectivity_signal.dart';
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

  /// Blob identity passed to `MediaBlobStore.requestBlob` — the single
  /// store entry (spec §9). Format shared with [mediaBlobId].
  String get blobId => mediaBlobId(serverId, thumb: thumb);

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
///
/// Upload-race recovery (#18): the sender creates the PocketBase `messages`
/// row BEFORE its `message_media` row (the media upload needs the message
/// id), so a live SSE echo can reach this provider while the media row
/// doesn't exist yet — the first fetch 404s and returns null. Instead of
/// caching that null forever (the old bug: blank bubble until an app
/// restart), subscribe to the repo's message_media change feed FIRST, run
/// the initial fetch, and when it comes back empty wait (bounded) for the
/// media record to land, then retry once. The future completes with the
/// media, or with null after the timeout (bubble keeps its placeholder).
///
/// Task 5 re-point: the fetch now goes through
/// `MediaBlobStore.requestBlob(r.blobId, reason)` — the single blob entry
/// (spec §9). The wait/retry shape above is unchanged (behavior-preserving
/// wiring); a queued blob (offline / media row not landed) returns null
/// exactly like the old network failure did.
final mediaFileProvider = FutureProvider.family<LocalMediaFile?, MediaRef>((
  ref,
  r,
) async {
  final repo = ref.read(messageRepositoryProvider);
  // Single store instance — built by the repo (key-resolution closure).
  final store = (repo as MessageRepositoryImpl).mediaBlobStore;

  // Only a just-sent message can be waiting on its media record (#18): for
  // an older one the 45s wait below can never end well, so skip it.
  final sent = (await store.messages.getMessageByServerId(r.serverId))
      ?.createdAt;
  final fresh = sent == null ||
      DateTime.now().difference(sent) < const Duration(minutes: 10);

  // Subscribe BEFORE the first fetch so a media row landing mid-fetch
  // can't slip between "fetch returned null" and "now wait for an event".
  final mediaArrived = fresh
      ? repo.mediaChanges.where((id) => id == r.serverId).first
      : null;

  var file = await store.requestBlob(r.blobId, 'mediaFileProvider');
  if (file != null) return file;

  // A failed blob is terminal (the store never retries it).
  Future<bool> failed() async =>
      (await store.dao.byId(r.blobId))?.state == BlobState.failed;

  if (mediaArrived != null && !await failed()) {
    try {
      await mediaArrived.timeout(const Duration(seconds: 45));
    } catch (_) {
      // No media event in time (failed/cancelled upload) — fall through to
      // one final attempt, then give up like the old behaviour.
    }
    file = await store.requestBlob(r.blobId, 'mediaFileProvider');
  }
  // Only an offline / not-landed null waits for the network.
  if (file == null && !await failed()) invalidateOnReconnect(ref);
  return file;
});

// ── Messages (reactive Drift stream) ─────────────────────────────────────

final messagesProvider = StreamProvider.family<List<Message>, String>((
  ref,
  conversationId,
) {
  return ref.watch(messageRepositoryProvider).watchMessages(conversationId);
});

/// How many rows in the conversation are hidden because their body cannot be
/// decrypted (backlog §170 fix b).
///
/// Read only when the visible list is EMPTY, so an ordinary chat never pays
/// for it. Lets the empty state distinguish a brand-new conversation from one
/// whose history this device can no longer decrypt.
final undecryptableCountProvider = FutureProvider.family<int, String>((
  ref,
  conversationId,
) {
  return ref.watch(messageRepositoryProvider).countUndecryptable(conversationId);
});

// ── Send ──────────────────────────────────────────────────────────────────

class SendMessageNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> send({
    required String conversationId,
    required String text,
    String? replyToLocalId,
  }) async {
    if (text.trim().isEmpty) return;
    state = true;
    try {
      await ref
          .read(messageRepositoryProvider)
          .sendMessage(
            conversationId: conversationId,
            plaintext: text.trim(),
            replyToLocalId: replyToLocalId,
          );
    } catch (e) {
      // Group-membership gate (#17) — the composer is hidden for
      // removed/left members, but a removal can race an in-flight send.
      // Every throw here lands before the optimistic row (offline sends
      // queue in the outbox instead), so the caller must restore the text.
      debugPrint('[Chat] send rejected: $e');
      rethrow;
    } finally {
      state = false;
    }
  }
}

final sendMessageProvider = NotifierProvider<SendMessageNotifier, bool>(
  SendMessageNotifier.new,
);

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
    try {
      await ref
          .read(messageRepositoryProvider)
          .sendMediaMessage(
            conversationId: conversationId,
            mediaType: mediaType,
            mediaFile: mediaFile,
            thumbnailFile: thumbnailFile,
            quality: quality,
            durationSeconds: durationSeconds,
            durationText: durationText,
            videoWidth: videoWidth,
            videoHeight: videoHeight,
          );
    } catch (e) {
      // Group-membership gate (#17) — see SendMessageNotifier.send. Upload
      // failures after the optimistic row mark the bubble, not this catch.
      debugPrint('[Chat] media send rejected: $e');
      rethrow;
    }
  }
}

final sendMediaMessageProvider =
    NotifierProvider<SendMediaMessageNotifier, bool>(
      SendMediaMessageNotifier.new,
    );

// ── Reply context ─────────────────────────────────────────────────────────

/// The message currently being replied to. Null = no reply in progress.
final replyProvider = StateProvider<Message?>((ref) => null);

// ── Search ────────────────────────────────────────────────────────────────

final searchActiveProvider = StateProvider<bool>((ref) => false);
final searchQueryProvider = StateProvider<String>((ref) => '');

// ── Pinned messages ───────────────────────────────────────────────────────

final pinnedMessagesProvider = StreamProvider.autoDispose
    .family<List<Message>, String>((ref, convId) {
      return ref.read(messageRepositoryProvider).watchPinnedMessages(convId);
    });

// ── Reactions per message ─────────────────────────────────────────────────

/// Reactive reactions provider — re-fetches whenever the repository
/// broadcasts a change for this specific message.
final reactionsProvider = StreamProvider.autoDispose
    .family<List<ReactionGroup>, String>((ref, serverId) {
      final repo = ref.read(messageRepositoryProvider);

      // Offline-first: the local store is what shows. A server read (now,
      // and on every live change for THIS message) lands in it and
      // re-emits from there; offline the read changes nothing.
      unawaited(repo.refreshReactions(serverId));
      final sub = repo.reactionsChanges
          .where((id) => id == serverId)
          .listen((_) => repo.refreshReactions(serverId));
      ref.onDispose(sub.cancel);
      return repo.watchReactions(serverId);
    });

class ReactionGroup {
  const ReactionGroup({
    required this.emoji,
    required this.count,
    required this.isMine,
    this.reactionId,
  });
  final String emoji;
  final int count;
  final bool isMine;
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

// ── Group-key readiness ──────────────────────────────────────────────────
//
/// Emits false while this device has no distributed key for the group
/// (join accepted, no admin device online yet to rotate); polls every 3s,
/// stops once ready. DMs are always ready. Gates the composer + banner.
final groupKeyReadyProvider = StreamProvider.autoDispose.family<bool, String>((
  ref,
  conversationId,
) async* {
  final repo = ref.read(messageRepositoryProvider);
  while (true) {
    final ready = await repo.hasUsableKey(conversationId);
    yield ready;
    if (ready) return;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
});
