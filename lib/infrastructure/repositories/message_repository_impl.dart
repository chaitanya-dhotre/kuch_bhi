import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/pocketbase_client.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/app_settings_table.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/group_invite.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/message_repository.dart';
import '../../features/chat/providers/chat_provider.dart' show ReactionGroup;
import '../../services/encryption_service.dart';
import '../../services/media_upload_service.dart';
import '../../data/local/secure_storage/secure_storage_service.dart';
import '../../services/fcm_service.dart';

class MessageRepositoryImpl implements MessageRepository {
  MessageRepositoryImpl({
    required this.pbClient,
    required this.db,
    required this.storage,
    required this.encryption,
    required this.mediaUploadService,
  }) {
    // Kick off the very first connect (serialized — see _reconnect).
    _reconnect();
    _initConnectivityRetry();

    // Re-subscribe when auth state changes (e.g. login/logout).
    _pb.authStore.onChange.listen((event) {
      if (event.token.isNotEmpty) {
        debugPrint('[Msg] Auth token changed (logged in). Reconnecting subscriptions.');
        _reconnect();
      } else {
        debugPrint('[Msg] Auth token changed (logged out). Unsubscribing.');
        _pendingJoinEmitConvIds.clear(); // no join polls for the previous user
        for (final t in _rotateDebounce.values) {
          t.cancel();
        }
        _rotateDebounce.clear(); // no stale auto-rotates for the previous user
        _teardown();
      }
    });
  }

  final PocketBaseClient     pbClient;
  final AppDatabase          db;
  final SecureStorageService storage;
  final EncryptionService    encryption;
  final MediaUploadService   mediaUploadService;

  PocketBase get _pb => pbClient.pb;
  static const _uuid = Uuid();

  final _reactionsCtrl     = StreamController<String>.broadcast();
  final _mediaChangesCtrl   = StreamController<String>.broadcast();

  /// Conversations where an accepted invite's "X joined the group" bubble is
  /// still deferred (no admin device has rotated the group key yet). Retried
  /// on every resume sync — see [_emitJoinedWhenKeyReady].
  final Set<String> _pendingJoinEmitConvIds = {};

  @override
  Stream<String> get reactionsChanges => _reactionsCtrl.stream;

  /// Emits the message serverId of any `message_media` record created or
  /// updated on the server (SSE). Bubbles use this to recover from the
  /// upload race where the messages row hits the realtime feed BEFORE its
  /// media row exists — see mediaFileProvider (#18).
  @override
  Stream<String> get mediaChanges => _mediaChangesCtrl.stream;

  // ── Realtime subscription lifecycle ───────────────────────────
  //
  // PocketBase's subscribe()/unsubscribe() are ASYNC under the hood (they
  // negotiate a single shared /api/realtime SSE client). Firing them
  // concurrently — which used to happen from the constructor, the auth-change
  // listener and resyncOnResume all at once — corrupts that shared client
  // ("Missing or invalid client id", "Cannot add new events after close") and
  // leaves every subscription dead. So ALL connect/teardown work is funnelled
  // through a single serialized chain (_opChain) and guarded by retry+backoff.
  // A lightweight poll fallback keeps devices without a working SSE/FCM path
  // (e.g. de-Googled ROMs) up to date.

  Future<void> _opChain = Future.value();
  bool _subscribed = false;
  int  _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _pollTimer;

  /// Serializes [action] after any in-flight connect/teardown so the shared
  /// SSE client is never mutated concurrently.
  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _opChain.then((_) => action());
    // Keep the chain alive even if an action throws.
    _opChain = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _teardown() => _serialize(_teardownInner);

  Future<void> _teardownInner() async {
    _subscribed = false;
    for (final c in const [
      'messages', 'conversations', 'conversation_members',
      'message_receipts', 'reactions', 'message_media',
    ]) {
      try {
        await _pb.collection(c).unsubscribe('*');
      } catch (_) {}
    }
    debugPrint('[Msg] Unsubscribed from all PocketBase collections.');
  }

  /// Public entry point — always safe to call, always serialized.
  void _reconnect() {
    _reconnectTimer?.cancel();
    _serialize(() async {
      if (!_pb.authStore.isValid) return;
      try {
        await _teardownInner();
        await _subscribeAll();
        _subscribed = true;
        _reconnectAttempts = 0;
        debugPrint('[Msg] Realtime subscriptions established.');
        _startPollFallback();
      } catch (e) {
        _subscribed = false;
        _reconnectAttempts += 1;
        // Exponential backoff, capped at 30s.
        final delay = Duration(
          seconds: (1 << (_reconnectAttempts.clamp(0, 5))).clamp(1, 30),
        );
        debugPrint('[Msg] Subscribe failed ($e). Retrying in ${delay.inSeconds}s.');
        _reconnectTimer = Timer(delay, _reconnect);
        // Even while SSE is down, keep polling so the UI still updates.
        _startPollFallback();
      }
    });
  }

  /// Awaits each subscribe() so failures propagate to the retry logic and the
  /// shared SSE client is built up one collection at a time.
  Future<void> _subscribeAll() async {
    await _subMessages();
    await _subConversations();
    await _subMembers();
    await _subReceipts();
    await _subReactions();
    await _subMedia();
  }

  Future<void> _subMessages() async {
    // Messages subscription — handles incoming messages from all conversations
    await _pb.collection('messages').subscribe('*', (event) async {
      if (event.record == null) return;
      final r = event.record!;
      final myId = await _myId();
      // Never process incoming events before the session id is known — that
      // caused own-message echoes and empty recipient_id receipts.
      if (myId.isEmpty) return;

      // Sync pin + delete-for-everyone state for ANY message (including our
      // own), so these reflect live across devices without reopening.
      try {
        final existing = await db.messagesDao.getMessageByServerId(r.id);
        if (existing != null) {
          final serverPinned = r.getBoolValue('is_pinned');
          final serverDeleted = r.getBoolValue('is_deleted_for_everyone');
          if (serverPinned != existing.isPinned ||
              serverDeleted != existing.isDeletedForEveryone) {
            await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
              localId:              existing.localId,
              serverId:             Value(existing.serverId),
              conversationId:       existing.conversationId,
              senderId:             existing.senderId,
              type:                 existing.type,
              encryptedBody:        existing.encryptedBody,
              iv:                   existing.iv,
              decryptedBody:        Value(existing.decryptedBody),
              replyToId:            Value(existing.replyToId),
              replyPreview:         Value(existing.replyPreview),
              isPinned:             Value(serverPinned),
              isStarred:            Value(existing.isStarred),
              isDeletedForMe:       Value(existing.isDeletedForMe),
              isDeletedForEveryone: Value(serverDeleted),
              mediaId:              Value(existing.mediaId),
              status:               Value(existing.status),
              createdAt:            existing.createdAt,
              updatedAt:            DateTime.now(),
            ));
          }
        }
      } catch (_) {}

      // Skip our own sent messages for the incoming-decrypt path — already
      // handled optimistically in sendMessage (pin/delete synced above).
      if (r.getStringValue('sender_id') == myId) return;

      final convId  = r.getStringValue('conversation_id');
      final senderId = r.getStringValue('sender_id');
      try {
        // Ensure sender is cached in Drift (important for group messages)
        if (await db.usersDao.getUserById(senderId) == null) {
          try {
            final u = await _pb.collection('users').getOne(senderId);
            await _cacheUserRecord(u);
          } catch (_) {}
        }
        List<int>? key;
        try {
          key = await _getConvKey(convId, myId);
        } on MissingKeyException catch (e) {
          debugPrint('[Msg] incoming key not ready, caching ciphertext: $e');
          key = null;
        }
        // Cache even if we can't decrypt yet — a later fetch/reconcile will
        // decrypt once the key is available. Message is never lost.
        await _cacheMsg(r, myId, key ?? const <int>[]);
        // Acknowledge delivery so the sender's tick advances — narrative
        // 'system' rows carry no ticks, skip them.
        if (r.getStringValue('type') != 'system') {
          await _markDelivered(r.id, convId, myId);
        }
        // Drift stream auto-emits — no manual push needed
      } catch (e) {
        debugPrint('[Msg] incoming error: $e');
      }
    });
  }

  Future<void> _subConversations() async {
    // Keep home screen in sync when a chat is created or membership changes
    // on the other device.
    await _pb.collection('conversations').subscribe('*', (_) {
      _syncConversationsBackground();
    });
  }

  /// Per-conversation rotate debounce (one rotation per join burst).
  final Map<String, Timer> _rotateDebounce = {};

  Future<void> _subMembers() async {
    await _pb.collection('conversation_members').subscribe('*', (event) {
      _syncConversationsBackground();
      if (event.action != 'create' || event.record == null) return;
      final r = event.record!;
      _maybeScheduleRotate(r.getStringValue('conversation_id'),
          r.getStringValue('user_id'));
    });
  }

  /// Invite-accept self-joins create the member row from the JOINER's device.
  /// Key distribution must come from a key-holding device: any admin of the
  /// group rotates (debounced) so the joiner receives the current key.
  Future<void> _maybeScheduleRotate(String convId, String newUserId) async {
    if (convId.isEmpty) return;
    final myId = await _myId();
    if (myId.isEmpty || newUserId == myId) return;
    final conv = await db.conversationsDao.getConversationById(convId);
    if (conv?.type != 'group') return;
    if (!await isCurrentUserAdmin(convId)) return;

    // Deterministic rotate election: with 2+ admins online, every admin
    // device used to schedule its own rotation; both then read the same
    // next key_version before either wrote, colliding on
    // UNIQUE(conversation_id,user_id,key_version). All admins now compute
    // the same single owner (smallest admin user id) and only that device
    // rotates. If the owner is offline, no rotation happens on this pass —
    // the joiner's key-poll and the resume retry reconcile later.
    if (!await _isRotationOwner(convId, myId)) return;

    _rotateDebounce[convId]?.cancel();
    _rotateDebounce[convId] = Timer(const Duration(seconds: 3), () async {
      _rotateDebounce.remove(convId);
      try {
        await _rotateGroupKey(convId, myId);
      } catch (e) {
        debugPrint('[Group] auto-rotate on join failed: $e');
      }
    });
  }

  /// Election helper: true only if [myId] is the elected rotation owner —
  /// the lexicographically smallest admin user id of [convId]. Every admin
  /// device computes the same owner, so exactly one schedules the rotation.
  /// DAO rows first (cheap); PB fallback when the DAO throws or a fresh
  /// install has no local member rows yet.
  Future<bool> _isRotationOwner(String convId, String myId) async {
    var adminIds = const <String>[];
    try {
      final members =
          await db.conversationsDao.getAllMembersForConversation(convId);
      adminIds = members
          .where((m) => m.role == 'admin')
          .map((m) => m.userId)
          .toList();
    } catch (e) {
      debugPrint('[Group] rotate election: dao member fetch failed: $e');
    }
    if (adminIds.isEmpty) {
      try {
        final recs = await _pb.collection('conversation_members').getFullList(
              filter: 'conversation_id="$convId"&&role="admin"', batch: 200,
            );
        adminIds = recs.map((r) => r.getStringValue('user_id')).toList();
      } catch (e) {
        debugPrint('[Group] rotate election: pb admin fetch failed: $e');
        // Cannot enumerate admins — isCurrentUserAdmin above already
        // confirmed locally that we are one; proceed rather than stall the
        // joiner's key distribution forever.
        return true;
      }
    }
    final sorted = adminIds.where((id) => id.isNotEmpty).toList()..sort();
    if (sorted.isEmpty) return true;
    if (sorted.first != myId) {
      debugPrint(
          '[Group] rotate election: owner=${sorted.first}, me=$myId -> skip');
      return false;
    }
    return true;
  }

  Future<void> _subReceipts() async {
    // Receipts subscription — updates tick status
    await _pb.collection('message_receipts').subscribe('*', (event) async {
      if (event.record == null) return;
      final r   = event.record!;
      final myId = await _myId();
      if (myId.isEmpty) return;
      final msgServerId = r.getStringValue('message_id');
      final recipientId = r.getStringValue('recipient_id');
      final deliveredAt = r.getStringValue('delivered_at');
      final readAt = r.getStringValue('read_at');

      debugPrint('[Receipt] Subscription update - msg: $msgServerId, recipient: $recipientId, delivered: ${deliveredAt.isNotEmpty}, read: ${readAt.isNotEmpty}');

      try {
        final local = await db.messagesDao.getMessageByServerId(msgServerId);
        if (local == null) {
          debugPrint('[Receipt] Local message not found for server ID: $msgServerId');
          return;
        }

        // Only update status for messages I sent
        if (local.senderId != myId) {
          debugPrint('[Receipt] Ignoring receipt update for message sent by someone else');
          return;
        }

        debugPrint('[Receipt] Updating status for local message: ${local.localId}');
        await _updateMsgReceiptStatus(local.localId, msgServerId);
        // Drift auto-emits after the status update above
      } catch (e) {
        debugPrint('[Receipt] ERROR in subscription update: $e');
      }
    });

  }

  Future<void> _subReactions() async {
    // Reactions subscription — fires on both devices when any reaction changes.
    await _pb.collection('reactions').subscribe('*', (event) async {
      if (event.record == null) return;
      final msgServerId = event.record!.getStringValue('message_id');
      if (msgServerId.isNotEmpty) {
        debugPrint('[Reaction] Change detected for message: $msgServerId');
        _reactionsCtrl.add(msgServerId);
      }
    });
  }

  Future<void> _subMedia() async {
    // Media records land AFTER their messages row (the sender uploads the
    // encrypted file only after creating the message, since the media row
    // needs the message id), so the message's live SSE echo can beat the
    // media row by seconds. Broadcast the message_id so open bubbles can
    // retry their media fetch the moment the row exists (#18).
    await _pb.collection('message_media').subscribe('*', (event) {
      final r = event.record;
      if (r == null) return;
      final messageId = r.getStringValue('message_id');
      if (messageId.isNotEmpty) {
        debugPrint('[Media] Change detected for message: $messageId');
        _mediaChangesCtrl.add(messageId);
      }
    });
  }

  // ── Poll fallback ─────────────────────────────────────────────
  // For devices where SSE is flaky or FCM is unavailable (de-Googled ROMs),
  // poll the active conversations every few seconds so incoming messages,
  // receipts, reactions, pins and deletions still surface without a reopen.
  //
  // IMPORTANT: this loop only does the heavy work (re-fetch messages +
  // receipts + full conversation sync) when SSE is NOT healthy — i.e. when
  // `_subscribed == false`. When realtime is live, those updates arrive via
  // the subscriptions, so re-fetching here would re-cache every message every
  // 5s, and each cached row re-emits via the Drift stream → the open chat's
  // `markConversationRead` listener fires N times → a server round-trip for
  // each → creates receipts → the receipts subscription floods. That was the
  // "receipts run infinitely while a chat is open" storm.

  void _startPollFallback() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final myId = await _myId();
        if (myId.isEmpty) return;
        final active = _activeConversationId;
        if (active != null && !_subscribed) {
          // SSE is down — re-fetch messages + receipts for the on-screen chat.
          await _fetchAndCacheMessages(active);
          await _reconcileReceiptsForConversation(active, myId);
        }
        // Only reconcile the conversation list server-side when SSE is down;
        // when it's live, subscription handlers already drive `_syncConversations`.
        if (!_subscribed) {
          await _syncConversations(myId);
        }
      } catch (e) {
        debugPrint('[Msg] poll fallback: $e');
      }
    });
  }

  /// The conversation currently on screen (set by watchMessages). Polled more
  /// eagerly than the rest so the open chat feels live even without SSE.
  String? _activeConversationId;

  void _initConnectivityRetry() {
    Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        debugPrint('[Msg] Connectivity restored. Retrying pending messages.');
        retryPendingMessages();
      }
    });
  }

  // ── Watch conversations (Drift reactive) ──────────────────────

  @override
  Stream<List<Conversation>> watchConversations() {
    _syncConversationsBackground(); // Fire-and-forget

    return db.conversationsDao
        .watchAllConversations()
        .asyncMap((rows) => _convRowsToEntities(rows));
  }

  Future<void> _syncConversationsBackground() async {
    try {
      final myId = await _myId();
      await _syncConversations(myId);
    } catch (e) {
      debugPrint('[Conv] background sync: $e');
    }
  }

  // ── Watch messages (Drift reactive) ──────────────────────────

  /// Returns Drift's own reactive stream.
  /// Auto-emits on every table write — including optimistic inserts.
  /// No manual StreamController needed.
  ///
  /// COLD-START: if the local Drift cache for this conversation is empty we
  /// HOLD the stream until the first server fetch completes, so Riverpod
  /// reports `AsyncLoading` (spinner) rather than `AsyncData([])` ("Say hello
  /// 👋") during the 1–2s before the fetch writes the rows. If we already have
  /// cached rows (re-entering a chat) we hand them back immediately and let
  /// the background fetch update the stream reactively — no warm-open delay.
  @override
  Stream<List<Message>> watchMessages(String conversationId) {
    // Track the on-screen conversation for the poll fallback — set FIRST so the
    // poll can track it even while the fetch below is awaiting.
    _activeConversationId = conversationId;
    // Purge any locally-expired disappearing messages before showing the chat.
    // The Drift stream auto-emits on delete.
    db.messagesDao.deleteExpiredMessages();
    // Collapse any duplicate rows the FCM background isolate raced in.
    db.messagesDao.dedupByServerId();

    return _messagesStream(conversationId);
  }

  Stream<List<Message>> _messagesStream(String conversationId) async* {
    // Peek at the current local cache once to choose the cold vs warm path.
    final cached = await db.messagesDao.watchMessages(conversationId).first;
    if (cached.isEmpty) {
      // Cold: await the first server fetch so the UI shows a spinner, not the
      // empty-state, before the rows arrive. _fetchAndCacheMessages swallows its
      // own errors (offline) so on failure we still yield the (empty) Drift
      // stream below → "Say hello 👋" shows correctly when truly unreachable.
      await _fetchAndCacheMessages(conversationId);
    } else {
      // Warm: hand cached rows back instantly; refresh in the background.
      _fetchAndCacheMessages(conversationId);
    }

    await for (final rows in db.messagesDao.watchMessages(conversationId)) {
      debugPrint('[Msg] watchMessages EMIT — convId: $conversationId, rowCount: ${rows.length}');
      yield await _rowsToMessages(rows);
    }
  }

  Future<List<Message>> _rowsToMessages(
      List<MessagesTableData> rows) async {
    final myId = await _myId();
    return rows.map((r) => _rowToMessage(r, myId)).toList();
  }

  // ── Send message ──────────────────────────────────────────────

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String plaintext,
    String? replyToLocalId,
    String? replyPreview,
  }) async {
    final myId    = await _myId();
    // Hard group-membership gate (#17): the chat screen hides the composer
    // for removed/left members, this covers races (removed while the
    // composer was open) and retry paths.
    await _assertCanSend(conversationId);
    final localId = _uuid.v4();
    final now     = DateTime.now();
    final expiresAt = await _computeExpiry(conversationId, now);

    debugPrint('[Msg] Sending message - localId: $localId, convId: $conversationId');

    // ── Step 1: Optimistic insert to Drift ────────────────────
    // Drift stream auto-emits IMMEDIATELY — message appears NOW.
    debugPrint('[Msg] OPTIMISTIC INSERT — localId: $localId, convId: $conversationId, senderId: $myId');
    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId:        localId,
      conversationId: conversationId,
      senderId:       myId,
      type:           'text',
      encryptedBody:  '__pending__',
      iv:             '',
      decryptedBody:  Value(plaintext),
      replyToId:      Value(replyToLocalId),
      replyPreview:   Value(replyPreview),
      status:         Value('pending'),
      expiresAt:      Value(expiresAt),
      createdAt:      now,
      updatedAt:      now,
    ));
    debugPrint('[Msg] OPTIMISTIC INSERT DONE — myId: $myId, convId: $conversationId');

    // ── Step 2: Upload in background (does NOT block UI) ──────
    _uploadMessage(
      localId:        localId,
      conversationId: conversationId,
      myId:           myId,
      plaintext:      plaintext,
      replyToLocalId: replyToLocalId,
      replyPreview:   replyPreview,
      createdAt:      now,
    );
  }

  Future<void> _uploadMessage({
    required String   localId,
    required String   conversationId,
    required String   myId,
    required String   plaintext,
    String?           replyToLocalId,
    String?           replyPreview,
    required DateTime createdAt,
  }) async {
    debugPrint('[Msg] Starting upload for localId: $localId');
    
    final List<int> key;
    final EncryptResult encrypted;
    final EncryptResult? encryptedReply;
    try {
      key = await _getConvKey(conversationId, myId);
      encrypted = await encryption.encryptMessage(plaintext, key);
      // Encrypt the reply preview too — it must never hit the server as plaintext.
      encryptedReply = (replyPreview != null && replyPreview.isNotEmpty)
          ? await encryption.encryptMessage(replyPreview, key)
          : null;
      debugPrint('[Msg] Message encrypted successfully');
    } on MissingKeyException catch (e) {
      // Key not ready yet (peer key not synced / offline). Keep the message
      // PENDING so it retries automatically — do NOT mark failed, and never
      // send under a placeholder key.
      debugPrint('[Msg] Key not ready, staying pending: $e');
      await db.messagesDao.updateMessageStatus(localId, 'pending');
      return;
    } catch (e) {
      debugPrint('[Msg] Encryption failed: $e');
      await db.messagesDao.updateMessageStatus(localId, 'failed');
      return;
    }

    try {
      // Resolve localId → serverId for reply reference
      String? replyServerId;
      if (replyToLocalId != null) {
        final replyMsg = await db.messagesDao.getMessageByLocalId(replyToLocalId);
        replyServerId = replyMsg?.serverId;
      }

      debugPrint('[Msg] Creating message record on server');
      final record = await _pb.collection('messages').create(body: {
        'conversation_id':        conversationId,
        'sender_id':              myId,
        'type':                   'text',
        'encrypted_body':         encrypted.ciphertext,
        'iv':                     encrypted.iv,
        'reply_to_id':            replyServerId ?? '',
        // Encrypted preview stored as 'iv:ciphertext' (empty when no reply).
        'reply_preview':          encryptedReply == null
            ? ''
            : '${encryptedReply.iv}:${encryptedReply.ciphertext}',
        'is_deleted_for_everyone': false,
      });
      debugPrint('[Msg] Message created on server with serverId: ${record.id}');

      final serverCreated = DateTime.tryParse(record.created) ?? createdAt;
      final expiresAt = await _computeExpiry(conversationId, serverCreated);
      await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId:        localId,
        serverId:       Value(record.id),
        conversationId: conversationId,
        senderId:       myId,
        type:           'text',
        encryptedBody:  encrypted.ciphertext,
        iv:             encrypted.iv,
        decryptedBody:  Value(plaintext),
        replyToId:      Value(replyServerId),
        // Keep the local plaintext reply preview for display.
        replyPreview:   Value(replyPreview),
        status:         Value('sent'),
        expiresAt:      Value(expiresAt),
        // Use the server's canonical timestamp so ordering matches all devices.
        createdAt:      serverCreated,
        updatedAt:      DateTime.now(),
      ));
      debugPrint('[Msg] Local message updated with status: sent');

      await db.conversationsDao.updateLastMessage(
        conversationId,
        plaintext.length > 50 ? '${plaintext.substring(0, 50)}…' : plaintext,
        serverCreated,
      );

      debugPrint('[Msg] Creating receipts for serverId: ${record.id}');
      await _createReceipts(record.id, conversationId, myId);
    } catch (e) {
      debugPrint('[Msg] ERROR upload failed: $e');
      await db.messagesDao.updateMessageStatus(localId, 'failed');
    }
  }
  // ── Send media message ───────────────────────────────────────

  @override
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
  }) async {
    final myId    = await _myId();
    await _assertCanSend(conversationId);
    final localId = _uuid.v4();
    final now     = DateTime.now();

    debugPrint('[Msg] Sending media message - type: $mediaType, file: ${mediaFile.path}');

    // Step 1: Optimistic insert WITHOUT mediaId (we don't have it yet)
    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId:        localId,
      conversationId: conversationId,
      senderId:       myId,
      type:           mediaType,
      encryptedBody:  '',
      iv:             '',
      decryptedBody:  Value(durationText),
      status:         Value('pending'),
      createdAt:      now,
      updatedAt:      now,
    ));

    // Step 2: Upload in background
    unawaited(_uploadMediaMessage(
      localId:        localId,
      conversationId: conversationId,
      myId:           myId,
      mediaType:      mediaType,
      mediaFile:      mediaFile,
      thumbnailFile:  thumbnailFile,
      quality:        quality,
      durationSeconds: durationSeconds ?? 0,
      durationText:   durationText,
      createdAt:      now,
      videoWidth:     videoWidth,
      videoHeight:    videoHeight,
    ));
  }

  Future<void> _uploadMediaMessage({
    required String   localId,
    required String   conversationId,
    required String   myId,
    required String   mediaType,
    required File     mediaFile,
    File?             thumbnailFile,
    String?           quality,
    required int      durationSeconds,
    String?           durationText,
    required DateTime createdAt,
    int?              videoWidth,
    int?              videoHeight,
  }) async {
    try {
      // Step A: Get conversation key. Media bytes AND the body stub are
      // E2E-encrypted with this key.
      final List<int> key;
      final EncryptResult encrypted;
      try {
        key = await _getConvKey(conversationId, myId);
        encrypted = await encryption.encryptMessage(durationText ?? '', key);
      } on MissingKeyException catch (e) {
        debugPrint('[Msg] Media key not ready, staying pending: $e');
        await db.messagesDao.updateMessageStatus(localId, 'pending');
        return;
      } catch (e) {
        debugPrint('[Msg] Media encryption failed: $e');
        await db.messagesDao.updateMessageStatus(localId, 'failed');
        return;
      }

      // Step B: Create message on PocketBase first (no media_id yet)
      // 'document' is not a valid server enum value — map it to 'file'.
      final serverType = mediaType == 'document' ? 'file' : mediaType;
      final record = await _pb.collection('messages').create(body: {
        'conversation_id':         conversationId,
        'sender_id':               myId,
        'type':                    serverType,
        'encrypted_body':          encrypted.ciphertext,
        'iv':                      encrypted.iv,
        'reply_to_id':             '',
        'reply_preview':           '',
        'is_deleted_for_everyone': false,
        'media_id':                '',
      });

      final messageServerId = record.id;
      debugPrint('[Msg] Media message created on server: $messageServerId');

      // Step C: Upload media WITH the message_id now available
      late final String mediaId;
      if (mediaType == 'image') {
        if (thumbnailFile == null) {
          throw Exception('Thumbnail required for image upload');
        }
        mediaId = await mediaUploadService.uploadImage(
          mediaFile,
          thumbnailFile,
          conversationId,
          quality ?? 'normal',
          messageServerId,
          key,
        );
      } else if (mediaType == 'video') {
        if (thumbnailFile == null) {
          throw Exception('Thumbnail required for video upload');
        }
        mediaId = await mediaUploadService.uploadVideo(
          mediaFile,
          thumbnailFile,
          conversationId,
          quality ?? 'normal',
          durationSeconds,
          messageServerId,
          key,
          videoWidth:  videoWidth,
          videoHeight: videoHeight,
        );
      } else if (mediaType == 'document') {
        mediaId = await mediaUploadService.uploadDocument(
          mediaFile,
          conversationId,
          messageServerId,
          key,
        );
      } else {
        mediaId = await mediaUploadService.uploadVoice(
          mediaFile,
          conversationId,
          durationSeconds,
          messageServerId,
          key,
        );
      }
      debugPrint('[Msg] Media uploaded, mediaId: $mediaId');

      // Step D: Update local record with serverId and mediaId
      await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId:        localId,
        serverId:       Value(messageServerId),
        conversationId: conversationId,
        senderId:       myId,
        type:           mediaType,
        encryptedBody:  encrypted.ciphertext,
        iv:             encrypted.iv,
        decryptedBody:  Value(durationText),
        mediaId:        Value(mediaId),
        status:         Value('sent'),
        createdAt:      createdAt,
        updatedAt:      DateTime.now(),
      ));

      final preview = switch (mediaType) {
        'voice'    => '🎤 Voice message${durationText != null ? ' ($durationText)' : ''}',
        'image'    => '📷 Photo',
        'video'    => '🎬 Video',
        'document' => '📎 Document',
        _          => '📎 File',
      };
      await db.conversationsDao.updateLastMessage(
        conversationId,
        preview,
        DateTime.now(),
      );

      await _createReceipts(messageServerId, conversationId, myId);
    } catch (e) {
      debugPrint('[Msg] ERROR media upload: $e');
      await db.messagesDao.updateMessageStatus(localId, 'failed');
    } finally {
      try { await mediaFile.delete(); } catch (_) {}
      if (thumbnailFile != null) {
        try { await thumbnailFile.delete(); } catch (_) {}
      }
      debugPrint('[Msg] Temp media files deleted');
    }
  }

  /// Group send-gate (#17): throws when the current user is not an ACTIVE
  /// member of a group conversation (removed or left). DMs always pass.
  Future<void> _assertCanSend(String conversationId) async {
    final conv = await db.conversationsDao.getConversationById(conversationId);
    if (conv?.type != 'group') return;
    final myId = await _myId();
    final members =
        await db.conversationsDao.getAllMembersForConversation(conversationId);
    final mine = members.where((m) => m.userId == myId).firstOrNull;
    if (mine == null || mine.role == 'left') {
      throw StateError('You are no longer a member of this group.');
    }
  }

  // ── Retry pending messages ────────────────────────────────────

  @override
  Future<void> retryPendingMessages() async {
    final pending = await db.messagesDao.getPendingMessages();
    if (pending.isEmpty) return;

    debugPrint('[Msg] Retrying ${pending.length} pending messages.');

    // Resolve our id once; if the session isn't ready, skip this pass entirely
    // (we do NOT delete or fail the user's queued messages — they'll retry).
    final myId = await _myId();
    if (myId.isEmpty) {
      debugPrint('[Msg] Session not ready; deferring pending retry.');
      return;
    }

    for (final msg in pending) {
      if (msg.decryptedBody == null && msg.mediaId == null) continue;
      // Repair ghost messages whose senderId was lost to an early auth race:
      // adopt the now-known id instead of destroying the user's message.
      if (msg.senderId.isEmpty) {
        debugPrint('[Msg] Repairing pending message ${msg.localId} with resolved senderId.');
      }
      // Never retry into a group we're no longer a member of (#17) — the
      // server would reject the create anyway.
      final conv =
          await db.conversationsDao.getConversationById(msg.conversationId);
      if (conv?.type == 'group') {
        final members = await db.conversationsDao
            .getAllMembersForConversation(msg.conversationId);
        final mine = members.where((m) => m.userId == myId).firstOrNull;
        if (mine == null || mine.role == 'left') {
          debugPrint('[Msg] Skipping retry in group we left: ${msg.conversationId}');
          continue;
        }
      }
      await retryMessage(msg.localId);
    }
  }

  @override
  Future<void> retryMessage(String localId) async {
    final msg = await db.messagesDao.getMessageByLocalId(localId);
    if (msg == null) return;
    // Already synced — nothing to retry.
    if (msg.serverId != null && msg.serverId!.isNotEmpty) return;

    final myId = await _myId();
    if (myId.isEmpty) return;

    // Reset to pending -> Drift stream auto-emits -> retry button disappears
    await db.messagesDao.updateMessageStatus(localId, 'pending');

    // Media messages retry through their own path.
    if (msg.type != 'text') {
      // Media temp files may be gone after a restart; only text is safely
      // re-uploadable from Drift. Leave media as-is for now.
      if (msg.decryptedBody == null) return;
    }

    // Resolve reply preview (plaintext) from the referenced local/DB row.
    String? replyPreview = msg.replyPreview;

    // Re-upload with the SAME localId - no new entry created.
    await _uploadMessage(
      localId:        localId,
      conversationId: msg.conversationId,
      myId:           myId,
      plaintext:      msg.decryptedBody ?? '',
      replyToLocalId: null,
      replyPreview:   replyPreview,
      createdAt:      msg.createdAt,
    );
  }

  // ── Mark read ─────────────────────────────────────────────────

  @override
  Future<void> markConversationRead(String conversationId) async {
    try {
      final myId = await _myId();
      if (myId.isEmpty) return;
      final nowUtc = DateTime.now().toUtc().toIso8601String();

      // 1) Mark all my existing unread receipts in this conversation as read.
      final res = await _pb.collection('message_receipts').getFullList(
        filter: 'conversation_id="$conversationId"'
            '&&recipient_id="$myId"&&read_at=""',
        batch: 200,
      );
      for (final r in res) {
        try {
          await _pb.collection('message_receipts').update(r.id, body: {
            'read_at': nowUtc,
            // Ensure delivered is set too — reading implies delivered.
            if (r.getStringValue('delivered_at').isEmpty) 'delivered_at': nowUtc,
          });
        } catch (_) {}
      }

      // 2) For any incoming messages that don't yet have a receipt for me
      //    (e.g. the sender's create failed), create one now marked read.
      final rows = await db.messagesDao.watchMessages(conversationId).first;
      final withReceipt = res.map((r) => r.getStringValue('message_id')).toSet();
      for (final row in rows) {
        final sid = row.serverId;
        if (sid == null || sid.isEmpty) continue;
        if (row.senderId == myId) continue;      // not my own messages
        if (row.type == 'system') continue;      // narrative rows carry no receipts
        if (withReceipt.contains(sid)) continue; // already handled above
        try {
          await _pb.collection('message_receipts').create(body: {
            'message_id':      sid,
            'conversation_id': conversationId,
            'recipient_id':    myId,
            'delivered_at':    nowUtc,
            'read_at':         nowUtc,
          });
        } catch (_) {
          // Unique-index race — a receipt now exists; mark it read.
          try {
            final ex = await _pb.collection('message_receipts').getList(
              filter: 'message_id="$sid"&&recipient_id="$myId"', perPage: 1,
            );
            if (ex.items.isNotEmpty) {
              await _pb.collection('message_receipts').update(
                ex.items.first.id, body: {'read_at': nowUtc});
            }
          } catch (_) {}
        }
      }

      // 3) Reset the LOCAL unread badge for this conversation. Pick the most
      //    recent message localId and persist it as the new last-read cursor so
      //    the next incoming message bumps the count from zero again.
      String? lastReadLocalId;
      if (rows.isNotEmpty) {
        // rows from `watchMessages` are DESC by createdAt → first = newest.
        lastReadLocalId = rows.first.localId;
      }
      await db.conversationsDao.markRead(
        conversationId, lastReadLocalId ?? '');
    } catch (e) {
      debugPrint('[Receipt] markRead: $e');
    }
  }

  // ── Load more (pagination) ────────────────────────────────────

  @override
  Future<void> loadMoreMessages(String conversationId, int offset) async {
    try {
      final myId = await _myId();
      final res  = await _pb.collection('messages').getList(
        filter:  'conversation_id="$conversationId"&&is_deleted_for_everyone=false',
        sort:    '-created',
        page:    (offset ~/ 40) + 1,
        perPage: 40,
      );
      final key = await _getConvKey(conversationId, myId);
      for (final r in res.items) {
        await _cacheMsg(r, myId, key);
      }
      // Drift auto-emits after the inserts above
    } on MissingKeyException catch (e) {
      debugPrint('[Msg] loadMore key not ready: $e');
    } catch (e) {
      debugPrint('[Msg] loadMore: $e');
    }
  }

  @override
  Future<void> fetchAndCacheSingleMessage(
      String messageId, String conversationId) async {
    try {
      final myId = await _myId();

      // Check if already cached
      final existing = await db.messagesDao.getMessageByServerId(messageId);
      if (existing != null) {
        debugPrint('[Msg] Single message $messageId already cached locally.');
        return;
      }

      final r = await _pb.collection('messages').getOne(messageId);
      final senderId = r.getStringValue('sender_id');

      // Ensure sender is cached in Drift
      if (await db.usersDao.getUserById(senderId) == null) {
        try {
          final u = await _pb.collection('users').getOne(senderId);
          await _cacheUserRecord(u);
        } catch (_) {}
      }

      final key = await _getConvKey(conversationId, myId);
      await _cacheMsg(r, myId, key);
      debugPrint('[Msg] Successfully fetched and cached single message $messageId');
    } on MissingKeyException catch (e) {
      debugPrint('[Msg] single message key not ready: $e');
    } catch (e) {
      debugPrint('[Msg] Error fetching and caching single message: $e');
    }
  }

  // ── Get or create conversation ────────────────────────────────

  @override
  Future<Conversation> getOrCreateDirectConversation(
      String otherUserId) async {
    final myId = await _myId();

    final existingId = await db.conversationsDao
        .findDirectConversationId(myId, otherUserId);

    if (existingId != null) {
      final conv = await db.conversationsDao.getConversationById(existingId);
      if (conv != null) {
        final other = await _getOtherUser(existingId, myId);
        return _convDataToEntity(conv, other);
      }
    }

    await _syncConversations(myId);

    final syncedId = await db.conversationsDao
        .findDirectConversationId(myId, otherUserId);
    if (syncedId != null) {
      final conv = await db.conversationsDao.getConversationById(syncedId);
      if (conv != null) {
        final other = await _getOtherUser(syncedId, myId);
        return _convDataToEntity(conv, other);
      }
    }

    throw StateError('Direct conversation not found yet.');
  }

  @override
  Future<void> deleteMessage(String localId, {bool forEveryone = false}) async {
    final msg = await db.messagesDao.getMessageByLocalId(localId);
    if (msg == null) return;

    if (forEveryone) {
      if (msg.serverId != null) {
        try {
          await _pb.collection('messages').update(
            msg.serverId!,
            body: {'is_deleted_for_everyone': true},
          );
        } catch (e) {
          debugPrint('[Msg] deleteForEveryone: $e');
        }
      }

      await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId:              msg.localId,
        serverId:             Value(msg.serverId),
        conversationId:       msg.conversationId,
        senderId:             msg.senderId,
        type:                 msg.type,
        encryptedBody:        msg.encryptedBody,
        iv:                   msg.iv,
        decryptedBody:        Value(msg.decryptedBody),
        isDeletedForEveryone: Value(true),
        status:               Value(msg.status),
        createdAt:            msg.createdAt,
        updatedAt:            DateTime.now(),
      ));
    } else {
      await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId:        msg.localId,
        serverId:       Value(msg.serverId),
        conversationId: msg.conversationId,
        senderId:       msg.senderId,
        type:           msg.type,
        encryptedBody:  msg.encryptedBody,
        iv:             msg.iv,
        decryptedBody:  Value(msg.decryptedBody),
        isDeletedForMe: Value(true),
        status:         Value(msg.status),
        createdAt:      msg.createdAt,
        updatedAt:      DateTime.now(),
      ));

      if (msg.serverId != null) {
        final myId = await _myId();
        unawaited(() async {
          try {
            await _pb.collection('deleted_messages_for_me').create(body: {
              'user_id':         myId,
              'message_id':      msg.serverId,
              'conversation_id': msg.conversationId,
            });
          } catch (e) {
            debugPrint('[Delete] PB sync failed (offline?): $e');
          }
        }());
      }
    }
  }

  @override
  Future<void> toggleStar(String localId) async {
    final msg = await db.messagesDao.getMessageByLocalId(localId);
    if (msg == null) return;

    final nextStarred = !msg.isStarred;

    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId:        msg.localId,
      conversationId: msg.conversationId,
      senderId:       msg.senderId,
      type:           msg.type,
      encryptedBody:  msg.encryptedBody,
      iv:             msg.iv,
      decryptedBody:  Value(msg.decryptedBody),
      isStarred:      Value(nextStarred),
      status:         Value(msg.status),
      createdAt:      msg.createdAt,
      updatedAt:      DateTime.now(),
    ));

    if (msg.serverId != null) {
      final myId = await _myId();
      unawaited(() async {
        try {
          if (nextStarred) {
            await _pb.collection('starred_messages').create(body: {
              'user_id':         myId,
              'message_id':      msg.serverId,
              'conversation_id': msg.conversationId,
              'message_preview': msg.decryptedBody ?? '',
              'sender_id':       msg.senderId,
            });
          } else {
            final res = await _pb.collection('starred_messages').getList(
              filter: 'user_id="$myId"&&message_id="${msg.serverId}"',
              perPage: 1,
            );
            if (res.items.isNotEmpty) {
              await _pb.collection('starred_messages').delete(res.items.first.id);
            }
          }
        } catch (e) {
          debugPrint('[Star] PB sync failed (offline?): $e');
        }
      }());
    }
  }

  @override
  Future<void> togglePin(String localId, String conversationId, bool pin) async {
    final msg = await db.messagesDao.getMessageByLocalId(localId);
    if (msg == null) return;

    // Enforce max 3 pinned messages per conversation (bible §6.4).
    if (pin) {
      final current = await db.messagesDao.getPinnedMessages(conversationId);
      final alreadyPinned = current.any((m) => m.localId == localId);
      if (!alreadyPinned && current.length >= AppConstants.maxPinnedMessages) {
        throw StateError(
            'You can pin up to ${AppConstants.maxPinnedMessages} messages.');
      }
    }

    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId:        msg.localId,
      conversationId: msg.conversationId,
      senderId:       msg.senderId,
      type:           msg.type,
      encryptedBody:   msg.encryptedBody,
      iv:             msg.iv,
      isPinned:       Value(pin),
      decryptedBody:  Value(msg.decryptedBody),
      status:         Value(msg.status),
      createdAt:      msg.createdAt,
      updatedAt:      DateTime.now(),
    ));

    if (msg.serverId != null) {
      try {
        await _pb.collection('messages').update(
          msg.serverId!,
          body: {'is_pinned': pin},
        );
      } catch (e) {
        debugPrint('[Msg] togglePin server: $e');
      }
    }
  }

  @override
  Future<void> addReaction(String messageServerId, String emoji) async {
    final myId = await _myId();

    try {
      final message = await db.messagesDao.getMessageByServerId(messageServerId);
      final conversationId = message?.conversationId;
      if (conversationId == null || conversationId.isEmpty) return;

      final existing = await _pb.collection('reactions').getList(
        filter: 'message_id="$messageServerId"&&user_id="$myId"&&emoji="$emoji"',
        perPage: 1,
      );
      if (existing.items.isNotEmpty) {
        await _pb.collection('reactions').delete(existing.items.first.id);
      } else {
        await _pb.collection('reactions').create(body: {
          'message_id': messageServerId,
          'conversation_id': conversationId,
          'user_id': myId,
          'emoji': emoji,
        });
      }
    } catch (e) {
      debugPrint('[Reaction] add: $e');
    }
  }

  @override
  Future<void> removeReaction(String reactionId) async {
    try {
      await _pb.collection('reactions').delete(reactionId);
    } catch (e) {
      debugPrint('[Reaction] remove: $e');
    }
  }

  @override
  Future<List<ReactionGroup>> getReactions(String messageServerId) async {
    try {
      final myId = await _myId();
      final res = await _pb.collection('reactions').getList(
        filter: 'message_id="$messageServerId"',
        perPage: 50,
      );

      final Map<String, List<RecordModel>> grouped = {};
      for (final r in res.items) {
        final emoji = r.getStringValue('emoji');
        grouped.putIfAbsent(emoji, () => []).add(r);
      }

      return grouped.entries.map((entry) {
        RecordModel? mine;
        for (final reaction in entry.value) {
          if (reaction.getStringValue('user_id') == myId) {
            mine = reaction;
            break;
          }
        }

        return ReactionGroup(
          emoji: entry.key,
          count: entry.value.length,
          isMine: mine != null,
          reactionId: mine?.id,
        );
      }).toList();
    } catch (e) {
      debugPrint('[Reaction] get: $e');
      return [];
    }
  }

  @override
  Future<List<Message>> getStarredMessages(String conversationId) async {
    try {
      final myId = await _myId();
      final res = await _pb.collection('starred_messages').getList(
        filter: 'user_id="$myId"&&conversation_id="$conversationId"',
        sort: '-starred_at',
        perPage: 200,
      );

      final out = <Message>[];
      for (final record in res.items) {
        final serverId = record.getStringValue('message_id');
        // Resolve the REAL message type from the local cache — the
        // starred_messages PB collection only stores message_preview (text),
        // so without this lookup every starred media item would render as
        // plaintext and look blank. Fall back to 'text' only when the
        // message isn't in the local cache yet.
        String realType = 'text';
        try {
          final local = await db.messagesDao.getMessageByServerId(serverId);
          if (local != null && local.type.isNotEmpty) {
            realType = local.type;
          }
        } catch (_) {}
        out.add(Message(
          localId:        record.id,
          serverId:       serverId,
          conversationId: record.getStringValue('conversation_id'),
          senderId:       record.getStringValue('sender_id'),
          type:           realType,
          decryptedBody:  record.getStringValue('message_preview'),
          status:         'read',
          createdAt:      DateTime.tryParse(record.created) ?? DateTime.now(),
          isStarred:      true,
        ));
      }
      return out;
    } catch (e) {
      debugPrint('[Star] getStarredMessages: $e');
      return [];
    }
  }

  @override
  Future<List<Message>> getPinnedMessages(String conversationId) async {
    final rows = await db.messagesDao.getPinnedMessages(conversationId);
    final myId = await _myId();
    return rows.map((r) => _rowToMessage(r, myId)).toList();
  }

  @override
  Stream<List<Message>> watchPinnedMessages(String conversationId) {
    return db.messagesDao
        .watchPinnedMessages(conversationId)
        .asyncMap((rows) async {
      final myId = await _myId();
      return rows.map((r) => _rowToMessage(r, myId)).toList();
    });
  }

  @override
  Future<LocalMediaFile?> getDecryptedMedia(
    String conversationId,
    String messageServerId, {
    bool thumb = false,
  }) async {
    try {
      final myId = await _myId();
      final key = await _getConvKey(conversationId, myId);
      return mediaUploadService.getDecryptedMedia(
        messageServerId, key, thumb: thumb);
    } on MissingKeyException catch (e) {
      debugPrint('[Media] key not ready for decrypt: $e');
      return null;
    }
  }

  @override
  Future<void> syncAllHistory({
    void Function(HistorySyncProgress)? onProgress,
  }) async {
    final myId = await _myId();
    if (myId.isEmpty) return;
    debugPrint('[Sync] Full history sync starting for $myId');
    try {
      // Ensure conversations + members are cached first.
      onProgress?.call(const HistorySyncProgress(
        phase: HistorySyncPhase.fetchingConversations,
      ));
      await _syncConversations(myId);
      final convs = await db.conversationsDao.watchAllConversations().first;
      final convTotal = convs.length;
      for (var i = 0; i < convs.length; i++) {
        final conv = convs[i];
        // Find the message count up-front so we can show "downloading X of Y".
        final headRes = await _pb.collection('messages').getList(
          filter:
              'conversation_id="${conv.id}"&&is_deleted_for_everyone=false',
          page: 1,
          perPage: 1,
        );
        final msgTotal = headRes.totalItems;
        try {
          List<int>? key;
          // Retry key derivation a few times — during reinstall restore the
          // peer's public key fetch can transiently fail on a flaky network,
          // and skipping it would leave the whole conversation blank.
          for (var attempt = 0; attempt < 3 && key == null; attempt++) {
            try {
              key = await _getConvKey(conv.id, myId);
            } on MissingKeyException {
              if (attempt < 2) {
                await Future.delayed(
                    Duration(milliseconds: 400 * (attempt + 1)));
              }
            }
          }
          if (key == null) {
            debugPrint('[Sync] conv ${conv.id}: no key after retries, '
                'messages will re-decrypt once key is available');
          }
          // Page through the ENTIRE conversation history.
          var page = 1;
          var downloaded = 0;
          while (true) {
            final res = await _pb.collection('messages').getList(
              filter:
                  'conversation_id="${conv.id}"&&is_deleted_for_everyone=false',
              sort: '-created',
              page: page,
              perPage: 200,
            );
            if (res.items.isEmpty) break;
            // Cache every row even when key is null — _cacheMsg stores the
            // ciphertext and a later chat-open re-decrypts. Never drop history.
            for (final r in res.items) {
              await _cacheMsg(r, myId, key ?? const <int>[]);
              downloaded++;
              if (msgTotal > 0) {
                onProgress?.call(HistorySyncProgress(
                  phase: HistorySyncPhase.downloadingMessages,
                  conversationIndex: i + 1,
                  conversationCount: convTotal,
                  messageCurrent: downloaded,
                  messageTotal: msgTotal,
                ));
              }
            }
            if (page >= res.totalPages) break;
            page++;
          }
          onProgress?.call(HistorySyncProgress(
            phase: HistorySyncPhase.finalisingConversation,
            conversationIndex: i + 1,
            conversationCount: convTotal,
          ));
          await _syncDeletedForMe(conv.id);
          await _syncStarredMessages(conv.id);
        } catch (e) {
          debugPrint('[Sync] conversation ${conv.id} failed: $e');
        }
      }
      onProgress?.call(const HistorySyncProgress(
        phase: HistorySyncPhase.complete,
      ));
      debugPrint('[Sync] Full history sync complete');
    } catch (e) {
      debugPrint('[Sync] Full history sync error: $e');
    }
  }

  @override
  Future<List<Message>> searchMessages(String conversationId, String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final rows = await (db.select(db.messagesTable)
          ..where((t) => t.conversationId.equals(conversationId))
          ..where((t) => t.isDeletedForMe.equals(false))
          ..where((t) => t.isDeletedForEveryone.equals(false))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                )
          ]))
        .get();

    final myId = await _myId();
    final needle = trimmed.toLowerCase();
    return rows
        .where((row) => (row.decryptedBody ?? '').toLowerCase().contains(needle))
        .map((r) => _rowToMessage(r, myId))
        .toList();
  }

  @override
  Future<void> setDisappearingDuration(
      String conversationId, int seconds) async {
    try {
      await _pb.collection('conversations').update(
        conversationId,
        body: {'disappearing_duration': seconds},
      );
      await (db.update(db.conversationsTable)
            ..where((t) => t.id.equals(conversationId)))
          .write(ConversationsTableCompanion(
        disappearingDuration: Value(seconds),
        updatedAt: Value(DateTime.now()),
      ));
    } catch (e) {
      debugPrint('[Conv] setDisappearing: $e');
    }
  }

  // ── Group admin ───────────────────────────────────────────────

  @override
  Future<bool> isCurrentUserAdmin(String conversationId) async {
    final myId = await _myId();
    final members = await db.conversationsDao
        .getMembersForConversation(conversationId);
    return members
        .where((m) => m.userId == myId)
        .firstOrNull?.role == 'admin';
  }

  @override
  Future<List<User>> getGroupMembers(String conversationId) async {
    // UNFILTERED on purpose (#17): the chat screen's isLeft/isMeAdmin gate
    // looks for the user's OWN row in this list — the filtered dao query
    // drops 'left' rows, so a removed member's gate never fired and they
    // could keep typing. Display lists filter `groupRole != 'left'` locally.
    final members = await db.conversationsDao
        .getAllMembersForConversation(conversationId);
    final users = <User>[];
    for (final m in members) {
      var u = await db.usersDao.getUserById(m.userId);
      if (u == null) {
        try {
          final r = await _pb.collection('users').getOne(m.userId);
          await _cacheUserRecord(r);
          u = await db.usersDao.getUserById(m.userId);
        } catch (_) {}
      }
      if (u != null) {
        users.add(_tableUserToEntity(u, groupRole: m.role));
      }
    }
    return users;
  }

  @override
  Future<void> sendGroupInvite(String conversationId, String userId) async {
    final myId = await _myId();
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }
    // Idempotent: one invite per (conversation, user) — UNIQUE index
    // server-side. Re-invite flips an existing row back to pending.
    try {
      final existing = await _pb.collection('group_invites').getFirstListItem(
        'conversation_id="$conversationId"&&invited_user_id="$userId"',
      );
      await _pb.collection('group_invites').update(
        existing.id, body: {'status': 'pending'},
      );
    } on ClientException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _pb.collection('group_invites').create(body: {
        'conversation_id': conversationId,
        'invited_user_id': userId,
        'invited_by':      myId,
        'status':          'pending',
      });
    }
  }

  /// Minimal RecordModel → User mapping for invite senders (this file has no
  /// shared record→entity helper; mirrors friend_repository_impl's shape).
  User _inviteRecordToUser(RecordModel r) {
    final avatar = r.getStringValue('avatar');
    return User(
      id:          r.id,
      displayName: r.getStringValue('display_name'),
      username:    r.getStringValue('username'),
      email:       r.getStringValue('email'),
      friendCode:  r.getStringValue('friend_code'),
      avatarUrl:   avatar.isEmpty
          ? null
          : '${_pb.baseUrl}/api/files/users/${r.id}/$avatar',
      createdAt:   DateTime.tryParse(r.created) ?? DateTime.now(),
    );
  }

  @override
  Future<List<GroupInvite>> getIncomingGroupInvites() async {
    final myId = await _myId();
    if (myId.isEmpty) return [];
    final items = await _pb.collection('group_invites').getFullList(
      filter: 'invited_user_id="$myId"&&status="pending"',
      expand: 'invited_by,conversation_id',
      sort:   '-created',
      batch:  100,
    );
    final invites = <GroupInvite>[];
    for (final r in items) {
      final inviter = r.expand['invited_by']?.firstOrNull;
      if (inviter != null) await _cacheUserRecord(inviter);
      final convName = r.expand['conversation_id']?.firstOrNull
          ?.getStringValue('name');
      invites.add(GroupInvite(
        id:               r.id,
        conversationId:   r.getStringValue('conversation_id'),
        conversationName: convName?.isNotEmpty == true ? convName! : 'Group',
        invitedBy:        inviter != null
            ? _inviteRecordToUser(inviter)
            : User(
                id:          '',
                displayName: 'Someone',
                username:    '',
                email:       '',
                friendCode:  '',
                createdAt:   DateTime.now(),
              ),
        status:           r.getStringValue('status'),
        createdAt:        DateTime.tryParse(r.getStringValue('created')) ??
            DateTime.now(),
      ));
    }
    return invites;
  }

  @override
  Future<void> acceptGroupInvite(String inviteId) async {
    final myId = await _myId();
    if (myId.isEmpty) throw Exception('Not authenticated');
    final invite = await _pb.collection('group_invites').getOne(inviteId);
    final convId = invite.getStringValue('conversation_id');

    // Self-join — conversation_members.createRule's invite clause covers
    // this. A 400 here can be a UNIQUE(conversation_id,user_id) duplicate or
    // a rule denial (e.g. the invite was cancelled between getOne and
    // create); the catch below verifies which before tolerating.
    try {
      await _pb.collection('conversation_members').create(body: {
        'conversation_id': convId,
        'user_id':         myId,
        'role':            'member',
      });
    } on ClientException catch (e) {
      // 400 means the row was not created. Tolerate it ONLY if the
      // membership already exists (UNIQUE duplicate, e.g. accepted on
      // another device): verify the row, then continue as joined. If the
      // lookup fails (404 or otherwise) this was a rule denial, not a
      // duplicate — rethrow the original create failure so the caller sees
      // it and the invite below is NOT marked accepted for a non-member.
      if (e.statusCode != 400) rethrow;
      try {
        await _pb.collection('conversation_members').getFirstListItem(
          'conversation_id="$convId"&&user_id="$myId"',
        );
      } catch (_) {
        throw e;
      }
      debugPrint('[Invite] already a member of $convId — continuing');
    }

    await _pb.collection('group_invites').update(
      inviteId, body: {'status': 'accepted'},
    );

    // Make the group appear locally right away (messages stay garbled until
    // an admin device rotates the key and we fetch it).
    try {
      await _syncConversationsBackground();
    } catch (e) {
      debugPrint('[Invite] post-accept sync failed: $e');
    }

    // Bounded wait for the group key (admin auto-rotate), then a single
    // "X joined the group" bubble.
    unawaited(_emitJoinedWhenKeyReady(convId, myId));
  }

  /// After accepting an invite, the joiner holds no group key until an admin
  /// device rotates. Poll (bounded) for the key, then emit the join bubble
  /// exactly once (guarded by a local lookup for an existing copy).
  Future<void> _emitJoinedWhenKeyReady(String convId, String myId) async {
    const tries = 15;
    for (var i = 0; i < tries; i++) {
      try {
        await encryption.getOrFetchGroupKey(convId, myId);
        final myName = await _userName(myId);
        final body   = '$myName joined the group';
        final already = await db.messagesDao
            .findSystemMessage(convId, myId, body);
        if (already == null) {
          await _emitSystemMessage(convId, body, actorUserId: myId);
        }
        _pendingJoinEmitConvIds.remove(convId);
        return;
      } on Exception {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    debugPrint('[Invite] key not distributed within ${tries * 2}s — '
        'join bubble deferred to next resume sync');
    _pendingJoinEmitConvIds.add(convId);
  }

  @override
  Future<void> declineGroupInvite(String inviteId) async {
    await _pb.collection('group_invites').update(
      inviteId, body: {'status': 'declined'},
    );
  }

  @override
  Future<Map<String, String>> getInviteStatusesForConversation(
      String conversationId) async {
    final rows = await _pb.collection('group_invites').getFullList(
      filter: 'conversation_id="$conversationId"',
      batch:  100,
    );
    return {
      for (final r in rows)
        r.getStringValue('invited_user_id'): r.getStringValue('status'),
    };
  }

  @override
  Future<void> removeMemberFromGroup(
      String conversationId, String userId) async {
    final myId = await _myId();
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }

    // Capture display names BEFORE we drop the membership rows / caches.
    final removedName = await _userName(userId);
    final adminName   = await _userName(myId);

    // 1) Delete ALL membership rows for this user (defensive against any
    //    pre-existing duplicates). Do NOT swallow failures — a silent 403
    //    here was the root cause of #17: the "removed" member stayed a full
    //    member server-side, reappeared after reopen and kept receiving.
    //    Let the caller see the error so the failure surfaces.
    final memberRecs = await _pb.collection('conversation_members').getFullList(
      filter: 'conversation_id="$conversationId"&&user_id="$userId"', batch: 50,
    );
    for (final rec in memberRecs) {
      await _pb.collection('conversation_members').delete(rec.id);
    }

    // 2) Purge any pending invite for this user in this conversation — a live
    //    invite would let them self-rejoin after being removed.
    try {
      final invs = await _pb.collection('group_invites').getFullList(
        filter: 'conversation_id="$conversationId"&&invited_user_id="$userId"',
        batch: 20,
      );
      for (final inv in invs) {
        await _pb.collection('group_invites').delete(inv.id);
      }
    } catch (e) {
      debugPrint('[Group] invite purge on remove failed: $e');
    }

    // 3) Emit "X was removed by Y" only on success, BEFORE the key
    //    rotation. The removed member still holds the CURRENT group key in
    //    their cache (their own sync wipes it later), so this row stays
    //    decryptable for them too; emitting after the rotation would garble
    //    it. Their device also gets its own local "You were removed" bubble
    //    from the membership sync — this one is for the remaining members.
    try {
      await _emitSystemMessage(
        conversationId,
        '$removedName was removed by $adminName',
        actorUserId: myId,
      );
    } catch (e) {
      debugPrint('[Group] removeMember system message emit failed: $e');
    }

    // 4) Remove the removed user's group-key rows so they can't decrypt
    //    anything on a fresh install. Best-effort: the server's
    //    group_keys.deleteRule may forbid this — stale rows only ever
    //    decrypt messages from BEFORE the rotation, which the user was
    //    entitled to anyway.
    try {
      final keyRecs = await _pb.collection('group_keys').getFullList(
        filter: 'conversation_id="$conversationId"&&user_id="$userId"', batch: 50,
      );
      for (final rec in keyRecs) {
        await _pb.collection('group_keys').delete(rec.id);
      }
    } catch (_) {}

    // 5) Fully remove locally (not a soft 'left' — they were removed by an
    //    admin). The removed user's own device flips to 'left' via
    //    _syncConversations when it sees the server row gone.
    await (db.delete(db.conversationMembersTable)
          ..where((t) => t.conversationId.equals(conversationId)
              & t.userId.equals(userId)))
        .go();

    // 6) Rotate the key so the removed member can't read future messages.
    await _rotateGroupKey(conversationId, myId);
  }

  Future<void> _rotateGroupKey(String convId, String myId) async {
    final newKey = encryption.generateGroupKey();

    // Read the CURRENT membership straight from the server so a just-added
    // member is included and a just-removed member is excluded.
    final memberRecs = await _pb.collection('conversation_members').getFullList(
      filter: 'conversation_id="$convId"', batch: 200,
    );

    // Determine the next key version from any existing key for this group.
    final existing = await _pb.collection('group_keys').getList(
      filter: 'conversation_id="$convId"',
      sort: '-key_version',
      perPage: 1,
    );
    final newVersion =
        (existing.items.isEmpty ? 0 : existing.items.first.getIntValue('key_version')) + 1;

    for (final m in memberRecs) {
      final uid = m.getStringValue('user_id');
      String? pubKey;
      try {
        final r = await _pb.collection('users').getOne(uid);
        await _cacheUserRecord(r);
        pubKey = r.getStringValue('public_key');
      } catch (_) {}
      if (pubKey == null || pubKey.isEmpty) continue;

      final encKey = await encryption.encryptGroupKeyForMember(
        newKey, pubKey, convId,
      );
      try {
        await _pb.collection('group_keys').create(body: {
          'conversation_id':      convId,
          'user_id':              uid,
          'encrypted_key':        encKey,
          'encrypted_by_user_id': myId,
          'key_version':          newVersion,
        });
      } catch (e) {
        // Unique (conv,user,version) race — update the existing row instead.
        debugPrint('[Group] group_key create conflict for $uid, updating: $e');
        try {
          final ex = await _pb.collection('group_keys').getFirstListItem(
            'conversation_id="$convId"&&user_id="$uid"&&key_version=$newVersion',
          );
          await _pb.collection('group_keys').update(ex.id, body: {
            'encrypted_key':        encKey,
            'encrypted_by_user_id': myId,
          });
        } catch (_) {}
      }
    }

    // Delete stale older-version keys.
    final oldRecs = await _pb.collection('group_keys').getFullList(
      filter: 'conversation_id="$convId"&&key_version<$newVersion', batch: 200,
    );
    for (final r in oldRecs) {
      try {
        await _pb.collection('group_keys').delete(r.id);
      } catch (e) {
        debugPrint('[Group] Non-fatal: could not delete old group key record: $e');
      }
    }

    // Update my own cache to the new key; other members' caches self-heal on
    // decrypt failure (they re-fetch the latest key version).
    await storage.write(
      key:   'group_key_$convId',
      value: base64.encode(newKey),
    );
    await storage.write(key: 'contact_key_${convId}_gk', value: '');
  }

  @override
  Future<void> promoteMemberToAdmin(
      String conversationId, String userId) async {
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }
    final rec = await _pb.collection('conversation_members').getFirstListItem(
      'conversation_id="$conversationId"&&user_id="$userId"',
    );
    await _pb.collection('conversation_members').update(rec.id, body: {'role': 'admin'});
    await (db.update(db.conversationMembersTable)
          ..where((t) => t.conversationId.equals(conversationId)
              & t.userId.equals(userId)))
        .write(const ConversationMembersTableCompanion(role: Value('admin')));
    try {
      final myId = await _myId();
      final name = await _userName(userId);
      await _emitSystemMessage(
        conversationId,
        '$name is now an admin',
        actorUserId: myId,
      );
    } catch (e) {
      debugPrint('[Group] promote system message emit failed: $e');
    }
  }

  @override
  Future<void> demoteAdminToMember(
      String conversationId, String userId) async {
    final members = await db.conversationsDao.getMembersForConversation(conversationId);
    final adminCount = members.where((m) => m.role == 'admin').length;
    final myId = await _myId();
    if (userId == myId && adminCount <= 1) {
      throw Exception('Cannot demote the only admin');
    }
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }
    final rec = await _pb.collection('conversation_members').getFirstListItem(
      'conversation_id="$conversationId"&&user_id="$userId"',
    );
    await _pb.collection('conversation_members').update(rec.id, body: {'role': 'member'});
    await (db.update(db.conversationMembersTable)
          ..where((t) => t.conversationId.equals(conversationId)
              & t.userId.equals(userId)))
          .write(const ConversationMembersTableCompanion(role: Value('member')));
    try {
      final myId = await _myId();
      final name = await _userName(userId);
      await _emitSystemMessage(
        conversationId,
        '$name is no longer an admin',
        actorUserId: myId,
      );
    } catch (e) {
      debugPrint('[Group] demote system message emit failed: $e');
    }
  }

  @override
  Future<void> setOnlyAdminsCanMessage(
      String conversationId, bool value) async {
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }
    await _pb.collection('conversations').update(
      conversationId,
      body: {'only_admins_can_message': value},
    );
    await (db.update(db.conversationsTable)
          ..where((t) => t.id.equals(conversationId)))
        .write(ConversationsTableCompanion(
          onlyAdminsCanMessage: Value(value)));
  }

  @override
  Future<void> leaveGroup(String conversationId) async {
    final myId = await _myId();
    final members = await db.conversationsDao.getMembersForConversation(conversationId);
    final me = members.where((m) => m.userId == myId).firstOrNull;

    if (me?.role == 'admin') {
      final otherAdmins = members.where((m) => m.userId != myId && m.role == 'admin');
      if (otherAdmins.isEmpty && members.length > 1) {
        final nextAdmin = members
          .where((m) => m.userId != myId)
          .reduce((a, b) => a.joinedAt.isBefore(b.joinedAt) ? a : b);
        await promoteMemberToAdmin(conversationId, nextAdmin.userId);
      }
    }

    // "X left" — emitted BEFORE deleting the key row/cache so it encrypts
    // with the key the remaining members still share (and our own cached
    // key is still available to encrypt it). Rotation at the end then
    // excludes the leaver from all FUTURE messages.
    try {
      final myName = await _userName(myId);
      await _emitSystemMessage(
        conversationId,
        '$myName left the group',
        actorUserId: myId,
      );
    } catch (e) {
      debugPrint('[Group] leaveGroup system message emit failed: $e');
    }

    try {
      final rec = await _pb.collection('conversation_members').getFirstListItem(
        'conversation_id="$conversationId"&&user_id="$myId"',
      );
      await _pb.collection('conversation_members').delete(rec.id);
    } catch (e) {
      debugPrint('[Group] Error deleting membership on server during leave: $e');
    }

    try {
      final keyRec = await _pb.collection('group_keys').getFirstListItem(
        'conversation_id="$conversationId"&&user_id="$myId"',
      );
      await _pb.collection('group_keys').delete(keyRec.id);
    } catch (_) {}

    await storage.delete(key: 'group_key_$conversationId');

    if (me != null) {
      await (db.update(db.conversationMembersTable)
            ..where((t) => t.conversationId.equals(conversationId)
                & t.userId.equals(myId)))
          .write(const ConversationMembersTableCompanion(role: Value('left')));
    }

    // Rotate the key so the leaver (who still holds the previous key in
    // SecureStorage) cannot decrypt any FUTURE group messages they might
    // still observe. Their membership row is already gone server-side, so
    // _rotateGroupKey distributes the new key to the remaining members only.
    await _rotateGroupKey(conversationId, myId);
  }

  @override
  Future<void> updateGroupInfo(String conversationId,
      {String? name, File? iconFile}) async {
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    List<http.MultipartFile>? files;
    if (iconFile != null) {
      files = [
        http.MultipartFile.fromBytes(
          'icon',
          await iconFile.readAsBytes(),
          filename: 'icon.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      ];
    }
    final rec = await _pb.collection('conversations').update(
      conversationId,
      body: body,
      files: files ?? [],
    );
    final iconField = rec.getStringValue('icon');
    final iconUrl   = iconField.isEmpty
        ? null
        : '${_pb.baseUrl}/api/files/conversations/$conversationId/$iconField';

    await (db.update(db.conversationsTable)
          ..where((t) => t.id.equals(conversationId)))
        .write(ConversationsTableCompanion(
      name:      Value(rec.getStringValue('name')),
      iconUrl:   Value(iconUrl),
      updatedAt: Value(DateTime.now()),
    ));
  }

  @override
  Stream<Conversation?> watchConversation(String conversationId) {
    return db.conversationsDao.watchConversationById(conversationId).asyncMap((row) async {
      if (row == null) return null;
      if (row.type == 'group') {
        final count = await _getMemberCount(row.id);
        return _convDataToEntity(row, null, memberCount: count);
      } else {
        final myId = await _myId();
        final other = await _getOtherUser(row.id, myId);
        return _convDataToEntity(row, other);
      }
    });
  }

  @override
  Stream<List<User>> watchGroupMembers(String conversationId) {
    return db.conversationsDao
        .watchMembersForConversation(conversationId)
        .asyncMap((_) => getGroupMembers(conversationId));
  }

  // ── Private helpers ───────────────────────────────────────────

  Future<String> _myId() async {
    // Poll until the session is saved to Drift (avoids race with _saveSession
    // on first launch / after reinstall where sendMessage may be called before
    // the auth flow has finished writing current_user_id).
    for (var i = 0; i < 50; i++) {
      final id = await db.settingsDao.getSetting(AppSettingsKeys.currentUserId);
      if (id != null && id.isNotEmpty) return id;
      // Also check SecureStorage — _saveSession writes there first.
      final secureId = await storage.getCurrentUserId();
      if (secureId != null && secureId.isNotEmpty) return secureId;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return '';
  }

  @override
  Future<void> resyncOnResume() async {
    debugPrint('[Msg] resyncOnResume — reconnecting realtime + refetching.');
    // 1. Force-reconnect the SSE subscriptions. Android suspends the socket
    //    while backgrounded and events sent in that window are lost forever —
    //    a fresh subscribe guarantees a live connection. _reconnect() is
    //    serialized internally, so calling it here can never race the
    //    constructor or the auth-change listener.
    _reconnect();

    // 2. Refetch conversations + recent messages/receipts for every
    //    conversation so anything missed while suspended is backfilled.
    try {
      final myId = await _myId();
      if (myId.isEmpty) return;
      // Remove any duplicate rows the FCM background isolate raced in.
      await db.messagesDao.dedupByServerId();
      await _syncConversations(myId);
      final memberships =
          await db.conversationsDao.getMembershipsOfUser(myId);
      for (final m in memberships) {
        if (m.role == 'left') continue;
        await _fetchAndCacheMessages(m.conversationId);
      }
      // 3. Flush anything that failed to send while backgrounded.
      await retryPendingMessages();

      // 4. Retry deferred join bubbles (accept happened while no admin
      //    device was online to rotate the group key).
      for (final convId in _pendingJoinEmitConvIds.toList()) {
        unawaited(_emitJoinedWhenKeyReady(convId, myId));
      }
    } catch (e) {
      debugPrint('[Msg] resyncOnResume: $e');
    }
  }

  Future<void> _fetchAndCacheMessages(String conversationId) async {
    try {
      final myId = await _myId();
      debugPrint('[Msg] _fetchAndCacheMessages — myId: $myId, convId: $conversationId');
      // No is_deleted_for_everyone filter: deletions that happened while this
      // device was offline must ALSO sync (cacheMsg flips the local flag).
      final res  = await _pb.collection('messages').getList(
        filter:  'conversation_id="$conversationId"',
        sort:    '-created',
        perPage: 40,
      );
      debugPrint('[Msg] _fetchAndCacheMessages — fetched ${res.items.length} messages from server');
      
      // Note: Group key recovery works seamlessly after private key restore.
      // The old encrypted group keys in PocketBase are decrypted using the user's restored X25519 key
      // on first access, and local FlutterSecureStorage group key cache is cleared on reinstall.
      List<int>? key;
      try {
        key = await _getConvKey(conversationId, myId);
      } on MissingKeyException catch (e) {
        debugPrint('[Msg] key not ready during fetch: $e');
        key = null;
      }
      if (key != null) {
        for (final r in res.items) {
          await _cacheMsg(r, myId, key);
        }
      }

      await _syncDeletedForMe(conversationId);
      await _syncStarredMessages(conversationId);
      // Repair any stuck ticks for my own messages in this conversation.
      await _reconcileReceiptsForConversation(conversationId, myId);
    } catch (e) {
      debugPrint('[Msg] fetch error (offline?): $e');
    }
  }

  /// Repairs sender-side tick status for a conversation by recomputing from
  /// the server receipts. Fixes ticks that got stuck due to missed events.
  Future<void> _reconcileReceiptsForConversation(
      String conversationId, String myId) async {
    try {
      final rows = await db.messagesDao.watchMessages(conversationId).first;
      for (final row in rows) {
        if (row.senderId != myId) continue;
        final sid = row.serverId;
        if (sid == null || sid.isEmpty) continue;
        if (row.status == 'read') continue; // already terminal
        await _updateMsgReceiptStatus(row.localId, sid);
      }
    } catch (e) {
      debugPrint('[Receipt] reconcile: $e');
    }
  }

  Future<void> _syncDeletedForMe(String conversationId) async {
    final myId = await _myId();
    try {
      final res = await _pb.collection('deleted_messages_for_me').getList(
        filter: 'user_id="$myId"&&conversation_id="$conversationId"',
        perPage: 500,
      );
      final deletedIds = res.items
          .map((r) => r.getStringValue('message_id'))
          .toSet();
      if (deletedIds.isEmpty) return;

      final rows = await db.messagesDao.watchMessages(conversationId).first;
      for (final row in rows) {
        if (row.serverId != null && deletedIds.contains(row.serverId)) {
          await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
            localId:              row.localId,
            serverId:             Value(row.serverId),
            conversationId:       row.conversationId,
            senderId:             row.senderId,
            type:                 row.type,
            encryptedBody:        row.encryptedBody,
            iv:                   row.iv,
            decryptedBody:        Value(row.decryptedBody),
            isDeletedForMe:       Value(true),
            isDeletedForEveryone: Value(row.isDeletedForEveryone),
            isStarred:            Value(row.isStarred),
            isPinned:             Value(row.isPinned),
            mediaId:              Value(row.mediaId),
            status:               Value(row.status),
            createdAt:            row.createdAt,
            updatedAt:            DateTime.now(),
          ));
        }
      }
    } catch (e) {
      debugPrint('[Delete] syncDeletedForMe: $e');
    }
  }

  Future<void> _syncStarredMessages(String conversationId) async {
    final myId = await _myId();
    try {
      final res = await _pb.collection('starred_messages').getList(
        filter: 'user_id="$myId"&&conversation_id="$conversationId"',
        perPage: 500,
      );
      final starredIds = res.items
          .map((r) => r.getStringValue('message_id'))
          .toSet();
      if (starredIds.isEmpty) return;

      final rows = await db.messagesDao.watchMessages(conversationId).first;
      for (final row in rows) {
        if (row.serverId != null && starredIds.contains(row.serverId)) {
          await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
            localId:              row.localId,
            serverId:             Value(row.serverId),
            conversationId:       row.conversationId,
            senderId:             row.senderId,
            type:                 row.type,
            encryptedBody:        row.encryptedBody,
            iv:                   row.iv,
            decryptedBody:        Value(row.decryptedBody),
            isDeletedForMe:       Value(row.isDeletedForMe),
            isDeletedForEveryone: Value(row.isDeletedForEveryone),
            isStarred:            Value(true),
            isPinned:             Value(row.isPinned),
            mediaId:              Value(row.mediaId),
            status:               Value(row.status),
            createdAt:            row.createdAt,
            updatedAt:            DateTime.now(),
          ));
        }
      }
    } catch (e) {
      debugPrint('[Star] syncStarredMessages: $e');
    }
  }

  /// In-flight cache operations keyed by serverId. The realtime subscription,
  /// the FCM foreground handler, and background fetches can all try to cache
  /// the same message concurrently — without serialization both see
  /// "no existing row" and insert duplicates (two bubbles for one message).
  final Map<String, Future<void>> _cacheInFlight = {};

  Future<void> _cacheMsg(RecordModel r, String myId, List<int> key) {
    final pending = _cacheInFlight[r.id];
    // Swallow the previous op's error so the chain always continues.
    final next = (pending ?? Future.value())
        .catchError((_) {})
        .then((_) => _cacheMsgInner(r, myId, key));
    _cacheInFlight[r.id] = next.whenComplete(() {
      if (identical(_cacheInFlight[r.id], next)) _cacheInFlight.remove(r.id);
    });
    return next;
  }

  Future<void> _cacheMsgInner(RecordModel r, String myId, List<int> key) async {
    // Note: isDeletedForEveryone is already synchronized automatically on fresh install
    // since is_deleted_for_everyone is fetched directly from the PocketBase messages collection schema.
    final encBody = r.getStringValue('encrypted_body');
    final iv      = r.getStringValue('iv');
    String? decrypted;
    if (encBody.isNotEmpty && iv.isNotEmpty && encBody != '__pending__') {
      decrypted = await encryption.decryptMessage(encBody, iv, key);
      if (decrypted == null) {
        final convId = r.getStringValue('conversation_id');
        final conv = await db.conversationsDao.getConversationById(convId);
        if (conv?.type == 'group') {
          debugPrint('[Enc] Group decryption failed. Invalidating cached group key and refetching...');
          try {
            await storage.delete(key: 'group_key_$convId');
            final freshKey = await _getConvKey(convId, myId);
            decrypted = await encryption.decryptMessage(encBody, iv, freshKey);
          } catch (e) {
            debugPrint('[Enc] Self-healing group key fetch failed: $e');
          }
        }
      }
    }
    // Decrypt the reply preview if present. New messages store it as
    // 'iv:ciphertext'; legacy rows may hold plaintext — handle both.
    String? replyPreview;
    final rawReply = r.getStringValue('reply_preview');
    if (rawReply.isNotEmpty) {
      final idx = rawReply.indexOf(':');
      if (idx > 0 && encBody != '__pending__') {
        final rIv = rawReply.substring(0, idx);
        final rCt = rawReply.substring(idx + 1);
        replyPreview = await encryption.decryptMessage(rCt, rIv, key) ?? '🔒';
      } else {
        replyPreview = rawReply; // legacy plaintext
      }
    }

    final existing = await db.messagesDao.getMessageByServerId(r.id);
    final isMine = r.getStringValue('sender_id') == myId;
    final existingStatus = existing?.status ?? '';

    // For my own messages: keep any existing (locally-known) status, but on a
    // fresh install (existing == null) compute the real status from receipts
    // instead of blindly resetting to 'sent'.
    String status;
    if (isMine) {
      if (existingStatus.isNotEmpty) {
        status = existingStatus;
      } else {
        status = await _computeSenderStatus(r.id);
      }
    } else {
      // Incoming message: mark delivered locally (recipient side).
      status = 'delivered';
    }

    final rawMediaId = r.getStringValue('media_id');
    // 'file' is the server enum used for documents; normalise to 'document' locally.
    final rawType = r.getStringValue('type');
    final localType = rawType == 'file' ? 'document' : rawType;
    final convId = r.getStringValue('conversation_id');
    final createdAt = DateTime.tryParse(r.created) ?? DateTime.now();
    final expiresAt = await _computeExpiry(convId, createdAt);
    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId:               existing?.localId ?? _uuid.v4(),
      serverId:              Value(r.id),
      conversationId:        convId,
      senderId:              r.getStringValue('sender_id'),
      type:                  localType,
      encryptedBody:         encBody,
      iv:                    iv,
      // Never wipe an already-decrypted body with null (e.g. when a later
      // cache pass runs with the key unavailable).
      decryptedBody:         Value(decrypted ?? existing?.decryptedBody),
      replyToId:             Value(r.getStringValue('reply_to_id').isEmpty
          ? null : r.getStringValue('reply_to_id')),
      replyPreview:          Value(replyPreview ?? existing?.replyPreview),
      // Preserve locally-known star/pin/delete-for-me flags across re-caches.
      isPinned:              Value(r.getBoolValue('is_pinned')),
      isStarred:             Value(existing?.isStarred ?? false),
      isDeletedForMe:        Value(existing?.isDeletedForMe ?? false),
      isDeletedForEveryone:  Value(r.getBoolValue('is_deleted_for_everyone')),
      mediaId:               Value(rawMediaId.isEmpty ? null : rawMediaId),
      status:                Value(status),
      expiresAt:             Value(expiresAt),
      createdAt:             createdAt,
      updatedAt:             DateTime.now(),
    ));

    // Keep the conversation list ordered + previewed on the RECIPIENT side
    // too (the sender's device updates it in sendMessage). Only bump for
    // messages newer than the current lastMessageAt so backfills don't
    // reorder the list.
    if (!isMine && !r.getBoolValue('is_deleted_for_everyone')) {
      try {
        final conv = await db.conversationsDao.getConversationById(convId);
        final currentLast = conv?.lastMessageAt;
        if (currentLast == null || createdAt.isAfter(currentLast)) {
          final preview = switch (localType) {
            'image'    => '📷 Photo',
            'video'    => '🎬 Video',
            'voice'    => '🎤 Voice message',
            'document' => '📎 Document',
            _          => decrypted ?? 'New message',
          };
          await db.conversationsDao.updateLastMessage(
              convId, preview, createdAt);
          // Bump the unread badge unless the user is currently viewing
          // this conversation (their last-read already points past it).
          // Narrative 'system' rows don't count as unread.
          if (localType != 'system' &&
              conv?.lastReadLocalId != null &&
              conv!.lastReadLocalId!.isNotEmpty) {
            await db.conversationsDao.bumpUnread(
                convId, existing?.localId ?? _uuid.v4());
          }
        }
      } catch (e) {
        debugPrint('[Conv] recipient lastMessage bump: $e');
      }
    }
  }

  /// Returns the user's cached display name, falling back to the username
  /// then the bare id. Local-only caller; safe to use everywhere.
  Future<String> _userName(String userId) async {
    if (userId.isEmpty) return 'Someone';
    try {
      final u = await db.usersDao.getUserById(userId);
      if (u != null) {
        if (u.displayName.isNotEmpty) return u.displayName;
        if (u.username.isNotEmpty)    return '@${u.username}';
      }
      // Cache miss — pull and try again.
      try {
        final r = await _pb.collection('users').getOne(userId);
        await _cacheUserRecord(r);
        if (r.getStringValue('display_name').isNotEmpty) {
          return r.getStringValue('display_name');
        }
        if (r.getStringValue('username').isNotEmpty) {
          return '@${r.getStringValue('username')}';
        }
      } catch (_) {}
    } catch (_) {}
    return userId.length > 8 ? 'Member' : userId;
  }

  /// Emits a system / info message — a centered, italic "Alice created the
  /// group" / "Bob added Charlie" / "You were removed by David" row that
  /// surfaces to every group member (including the newly-added or just-
  /// removed user) via the realtime SSE feed. Strategy:
  ///  1. Insert a local row IMMEDIATELY so the actor (e.g. the admin who
  ///     pressed "remove") sees the bubble appear without waiting for the
  ///     round-trip.
  ///  2. Encrypt the body with the group key and POST it to PB as a real
  ///     `messages` record of `type='system'`. The SSE subscription will
  ///     deliver it to every other device. The local cache is already there
  ///     so the returning SSE echo is a harmless upsert (same localId).
  ///  3. If the PB write fails (offline), the local bubble is still useful —
  ///     it just won't reach other members until sync resumes.
  Future<void> _emitSystemMessage(
    String convId,
    String body, {
    required String actorUserId,
  }) async {
    try {
      final id = 'sys_${_uuid.v4()}';
      final now = DateTime.now();

      // (1) local immediate insert
      await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId:           id,
        serverId:          const Value(null),
        conversationId:    convId,
        senderId:          actorUserId,
        type:              'system',
        encryptedBody:     '',
        iv:                '',
        decryptedBody:     Value(body),
        status:            const Value('sent'),
        createdAt:         now,
        updatedAt:         now,
      ));
      debugPrint('[SysMsg] local emit → "$body" in $convId');

      // (2) push to PB so every group member sees it too
      try {
        // Only groups post system messages; DMs don't have this concept.
        final conv = await db.conversationsDao.getConversationById(convId);
        if (conv?.type != 'group') return;
        final myId = await _myId();
        final key  = await _getConvKey(convId, myId);
        final res  = await encryption.encryptMessage(body, key);

        await _pb.collection('messages').create(body: {
          'conversation_id': convId,
          'sender_id':       actorUserId,
          'type':            'system',
          'encrypted_body':  res.ciphertext,
          'iv':              res.iv,
          // No reply, no media, no star/pin — system row stays boring.
          'is_pinned':              false,
          'is_deleted_for_everyone': false,
          'created':                now.toUtc().toIso8601String(),
        });
        debugPrint('[SysMsg] PB posted.');
      } catch (e) {
        debugPrint('[SysMsg] PB post failed (kept local-only): $e');
      }
    } catch (e) {
      debugPrint('[SysMsg] emit failed: $e');
    }
  }

  /// Local-only info bubble (never pushed to PocketBase) — for narrative
  /// rows that are only true on THIS device, e.g. "You were removed from
  /// this group" when a membership sync notices an admin removal.
  Future<void> _emitLocalSystemMessage(String convId, String body) async {
    final id  = 'sys_${_uuid.v4()}';
    final now = DateTime.now();
    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId:           id,
      serverId:          const Value(null),
      conversationId:    convId,
      senderId:          await _myId(),
      type:              'system',
      encryptedBody:     '',
      iv:                '',
      decryptedBody:     Value(body),
      status:            const Value('sent'),
      createdAt:         now,
      updatedAt:         now,
    ));
    debugPrint('[SysMsg] local-only emit → "$body" in $convId');
  }

  /// Computes a sender's message status ('sent'/'delivered'/'read') from the
  /// current receipts. Used when re-caching own messages after a reinstall.
  /// Strict semantics (see [_updateMsgReceiptStatus]) — every non-sender
  /// member of the conversation must have the matching timestamp.
  Future<String> _computeSenderStatus(String serverId) async {
    try {
      final res = await _pb.collection('message_receipts').getFullList(
        filter: 'message_id="$serverId"', batch: 200,
      );
      if (res.isEmpty) return 'sent';

      // Identify the conversation + sender so we can requery the live member
      // list (the present-receipts list isn't reliable during member
      // add/remove windows).
      String? convId;
      String? senderId;
      try {
        final msg = await _pb.collection('messages').getOne(serverId);
        convId   = msg.getStringValue('conversation_id');
        senderId = msg.getStringValue('sender_id');
      } catch (_) {}

      Set<String> required = res
          .map((r) => r.getStringValue('recipient_id'))
          .where((uid) => uid.isNotEmpty)
          .toSet();
      if (convId != null) {
        try {
          final members = await _pb.collection('conversation_members').getFullList(
            filter: 'conversation_id="$convId"', batch: 200,
          );
          required = members
              .map((m) => m.getStringValue('user_id'))
              .where((uid) => uid.isNotEmpty && uid != senderId)
              .toSet();
          if (required.isEmpty) required = {'__none__'}; // Direct conv: no other members → tick immediately
        } catch (_) {}
      }

      final deliveredIds = res
          .where((r) => r.getStringValue('delivered_at').isNotEmpty)
          .map((r) => r.getStringValue('recipient_id'))
          .toSet();
      final readIds = res
          .where((r) => r.getStringValue('read_at').isNotEmpty)
          .map((r) => r.getStringValue('recipient_id'))
          .toSet();

      if (required.every(readIds.contains)) return 'read';
      if (required.every(deliveredIds.contains)) return 'delivered';
      return 'sent';
    } catch (_) {
      return 'sent';
    }
  }

  Future<void> _updateMsgReceiptStatus(
      String localId, String serverId) async {
    try {
      // getFullList avoids the 30-row default cap for large groups.
      final items = await _pb.collection('message_receipts').getFullList(
        filter: 'message_id="$serverId"', batch: 200,
      );
      if (items.isEmpty) {
        debugPrint('[Receipt] No receipts found for message: $serverId');
        return;
      }

      // Strict WhatsApp-style semantics: delivered/read is ticked ONLY when
      // EVERY non-sender member of the conversation has the matching
      // timestamp. The naive `items.every(...)` over present receipts
      // misses members whose receipt was never created (race during member
      // add/remove windows) — that was letting "delivered" tick as soon as
      // even one recipient filled it in. We cross-check against the live
      // conversation_members list from the server.
      String? convId;
      String? senderId;
      try {
        final msg = await _pb.collection('messages').getOne(serverId);
        convId   = msg.getStringValue('conversation_id');
        senderId = msg.getStringValue('sender_id');
      } catch (_) {}

      Set<String> requiredRecipientIds = {};
      if (convId != null && senderId != null) {
        try {
          final members = await _pb.collection('conversation_members').getFullList(
            filter: 'conversation_id="$convId"', batch: 200,
          );
          requiredRecipientIds = members
              .map((m) => m.getStringValue('user_id'))
              .where((uid) => uid.isNotEmpty && uid != senderId)
              .toSet();
        } catch (_) {}
      }
      // Fall back to the present receipts when the cross-check can't run
      // (server unreachable, message row missing — shouldn't regress tick).
      if (requiredRecipientIds.isEmpty) {
        requiredRecipientIds = items
            .map((r) => r.getStringValue('recipient_id'))
            .where((uid) => uid.isNotEmpty)
            .toSet();
      }

      final deliveredIds = items
          .where((r) => r.getStringValue('delivered_at').isNotEmpty)
          .map((r) => r.getStringValue('recipient_id'))
          .toSet();
      final readIds = items
          .where((r) => r.getStringValue('read_at').isNotEmpty)
          .map((r) => r.getStringValue('recipient_id'))
          .toSet();

      final allDelivered = requiredRecipientIds.every(deliveredIds.contains);
      final allRead      = requiredRecipientIds.every(readIds.contains);

      final computed = allRead
          ? 'read'
          : allDelivered
              ? 'delivered'
              : 'sent';

      // Never regress a stronger status (read > delivered > sent) — receipt
      // events can arrive out of order.
      const rank = {'sent': 0, 'delivered': 1, 'read': 2};
      final current = await db.messagesDao.getMessageByServerId(serverId);
      final currentStatus = current?.status ?? 'sent';
      if ((rank[computed] ?? 0) < (rank[currentStatus] ?? 0)) {
        debugPrint('[Receipt] Skipping regression $currentStatus -> $computed');
        return;
      }

      debugPrint('[Receipt] Updating local message status to: $computed '
          '(deliveredIds=${deliveredIds.length}/${requiredRecipientIds.length}, '
          'readIds=${readIds.length}/${requiredRecipientIds.length})');
      await db.messagesDao.updateMessageStatus(localId, computed);
    } catch (e) {
      debugPrint('[Receipt] ERROR in statusUpdate: $e');
    }
  }

  /// Marks a message delivered for the current user (the recipient).
  /// Idempotent: the server has a UNIQUE(message_id, recipient_id) index, so
  /// a racing create just fails harmlessly and we fall back to update.
  Future<void> _markDelivered(
      String serverId, String convId, String myId) async {
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    try {
      final res = await _pb.collection('message_receipts').getList(
        filter: 'message_id="$serverId"&&recipient_id="$myId"',
        perPage: 1,
      );
      if (res.items.isEmpty) {
        try {
          await _pb.collection('message_receipts').create(body: {
            'message_id':      serverId,
            'conversation_id': convId,
            'recipient_id':    myId,
            'delivered_at':    nowUtc,
          });
        } catch (_) {
          // Lost the create race (unique index) — someone else created it;
          // re-read and set delivered_at if still empty.
          final again = await _pb.collection('message_receipts').getList(
            filter: 'message_id="$serverId"&&recipient_id="$myId"',
            perPage: 1,
          );
          if (again.items.isNotEmpty &&
              again.items.first.getStringValue('delivered_at').isEmpty) {
            await _pb.collection('message_receipts').update(
              again.items.first.id,
              body: {'delivered_at': nowUtc},
            );
          }
        }
      } else if (res.items.first.getStringValue('delivered_at').isEmpty) {
        await _pb.collection('message_receipts').update(
          res.items.first.id,
          body: {'delivered_at': nowUtc},
        );
      }
    } catch (e) {
      debugPrint('[Receipt] markDelivered: $e');
    }
  }

  Future<void> _createReceipts(
      String serverId, String convId, String myId) async {
    try {
      final members = await db.conversationsDao
          .getMembersForConversation(convId);
      debugPrint('[Receipt] Creating receipts for message $serverId to ${members.length} members');
      
      for (final m in members) {
        if (m.userId == myId) {
          debugPrint('[Receipt] Skipping self receipt for $serverId');
          continue;
        }
        try {
          final existing = await _pb.collection('message_receipts').getList(
            filter: 'message_id="$serverId"&&recipient_id="${m.userId}"',
            perPage: 1,
          );
          if (existing.items.isEmpty) {
            debugPrint('[Receipt] Creating new receipt for recipient: ${m.userId}');
            await _pb.collection('message_receipts').create(body: {
              'message_id':     serverId,
              'conversation_id': convId,
              'recipient_id':   m.userId,
            });
            debugPrint('[Receipt] Receipt created for recipient: ${m.userId}');
          } else {
            debugPrint('[Receipt] Receipt already exists for recipient: ${m.userId}');
          }
        } catch (e) {
          debugPrint('[Receipt] ERROR creating receipt for ${m.userId}: $e');
        }
      }
    } catch (e) {
      debugPrint('[Receipt] ERROR in create: $e');
    }
  }

  Future<ConversationsTableData?> _fetchAndCacheConversation(String convId, String myId) async {
    try {
      final conv = await _pb.collection('conversations').getOne(convId);
      final iconField = conv.getStringValue('icon');
      final iconUrl   = iconField.isEmpty
          ? null
          : '${_pb.baseUrl}/api/files/conversations/${conv.id}/$iconField';
      final tableData = ConversationsTableData(
        id:          conv.id,
        type:        conv.getStringValue('type'),
        name:        conv.getStringValue('name').isEmpty ? null : conv.getStringValue('name'),
        iconUrl:     iconUrl,
        createdById: conv.getStringValue('created_by'),
        onlyAdminsCanMessage: conv.getBoolValue('only_admins_can_message'),
        disappearingDuration: conv.getIntValue('disappearing_duration'),
        isPinned:    false,
        unreadCount: 0,
        lastReadLocalId: null,
        createdAt:   DateTime.tryParse(conv.getStringValue('created')) ?? DateTime.now(),
        updatedAt:   DateTime.now(),
      );
      await db.conversationsDao.upsertConversation(
        ConversationsTableCompanion.insert(
          id:          tableData.id,
          type:        tableData.type,
          name:        Value(tableData.name),
          iconUrl:     Value(tableData.iconUrl),
          createdById: tableData.createdById,
          onlyAdminsCanMessage: Value(tableData.onlyAdminsCanMessage),
          disappearingDuration: Value(tableData.disappearingDuration),
          isPinned:    Value(tableData.isPinned),
          createdAt:   tableData.createdAt,
          updatedAt:   tableData.updatedAt,
        ),
      );
      final membersRes = await _pb.collection('conversation_members').getList(
        filter: 'conversation_id="$convId"',
        expand: 'user_id',
      );
      // Join-triggered rotate, sync-discovery variant (see _syncConversations):
      // pre-check BEFORE each upsert so rows new-to-this-device schedule the
      // admin auto-rotate even when this fetch beats the full conversation
      // sync to a freshly (re)installed device.
      final localMemberIds = (await db.conversationsDao
              .getAllMembersForConversation(convId))
          .map((lm) => lm.userId)
          .toSet();
      for (final m in membersRes.items) {
        final u = m.expand['user_id']?.firstOrNull;
        if (u != null) await _cacheUserRecord(u);
        if (!localMemberIds.contains(m.getStringValue('user_id'))) {
          await _maybeScheduleRotate(convId, m.getStringValue('user_id'));
        }
        await db.conversationsDao.upsertMember(
          ConversationMembersTableCompanion.insert(
            id:             m.id,
            conversationId: convId,
            userId:         m.getStringValue('user_id'),
            role:           Value(m.getStringValue('role').isEmpty ? 'member' : m.getStringValue('role')),
            joinedAt:       DateTime.tryParse(m.getStringValue('joined_at')) ?? DateTime.now(),
          ),
        );
      }
      return tableData;
    } catch (e) {
      debugPrint('[Msg] Failed to fetch and cache conversation $convId: $e');
      return null;
    }
  }

  /// Computes when a message should locally disappear based on the
  /// conversation's disappearing-messages setting. Returns null when the
  /// feature is Off (duration <= 0), meaning the message never expires.
  Future<DateTime?> _computeExpiry(String convId, DateTime from) async {
    final conv = await db.conversationsDao.getConversationById(convId);
    final seconds = conv?.disappearingDuration ?? 0;
    if (seconds <= 0) return null;
    return from.add(Duration(seconds: seconds));
  }

  Future<List<int>> _getConvKey(String convId, String myId) async {
    var conv = await db.conversationsDao.getConversationById(convId);
    if (conv == null) {
      conv = await _fetchAndCacheConversation(convId, myId);
    }
    if (conv?.type == 'group') {
      return encryption.getOrFetchGroupKey(convId, myId);
    }

    final members = await db.conversationsDao.getMembersForConversation(convId);
    final otherUserId = members
        .where((m) => m.userId != myId)
        .map((m) => m.userId)
        .firstOrNull;

    if (otherUserId == null || otherUserId.isEmpty) {
      throw const MissingKeyException('no other member resolved for conversation');
    }

    var u = await db.usersDao.getUserById(otherUserId);
    final cachedPublicKey = u?.publicKey;

    // Always fetch the latest public key from the server to detect key rotation
    // (e.g. the other user reinstalled the app and got a new key pair).
    try {
      final r = await _pb.collection('users').getOne(otherUserId);
      final serverPublicKey = r.getStringValue('public_key');
      if (serverPublicKey.isNotEmpty && serverPublicKey != cachedPublicKey) {
        debugPrint('[Keys] Public key rotation detected for user $otherUserId — clearing derived key cache.');
        await storage.saveContactEncryptionKey(convId, ''); // Invalidate derived key
        await storage.clearAllContactKeys();               // Clear all stale derived keys
      }
      await _cacheUserRecord(r);
      u = await db.usersDao.getUserById(otherUserId);
    } catch (_) {}

    if (u?.publicKey == null || u!.publicKey!.isEmpty) {
      throw const MissingKeyException('peer public key not available yet');
    }
    return encryption.getOrDeriveConversationKey(convId, u.publicKey!);
  }

  Future<void> _syncConversations(String myId) async {
    try {
      final res = await _pb.collection('conversation_members').getList(
        filter: 'user_id="$myId"', expand: 'conversation_id', sort: '-created',
      );
      for (final m in res.items) {
        final conv = m.expand['conversation_id']?.firstOrNull;
        if (conv == null) continue;
        final iconField = conv.getStringValue('icon');
        final iconUrl   = iconField.isEmpty
            ? null
            : '${_pb.baseUrl}/api/files/conversations/${conv.id}/$iconField';
        // NEVER clobber the locally-computed last-message preview/time with
        // the server fields — nothing maintains them server-side, so they are
        // stale. Local Drift (updated by _cacheMsg/updateLastMessage) is the
        // source of truth; keep whichever timestamp is NEWER.
        final existingConv =
            await db.conversationsDao.getConversationById(conv.id);
        final serverAtStr = conv.getStringValue('last_message_at');
        final serverAt = serverAtStr.isEmpty
            ? null : DateTime.tryParse(serverAtStr);
        final localAt  = existingConv?.lastMessageAt;
        final keepLocal = localAt != null &&
            (serverAt == null || localAt.isAfter(serverAt));
        await db.conversationsDao.upsertConversation(
          ConversationsTableCompanion.insert(
            id:          conv.id,
            type:        conv.getStringValue('type'),
            name:        Value(conv.getStringValue('name').isEmpty
                ? null : conv.getStringValue('name')),
            iconUrl:     Value(iconUrl),
            createdById: conv.getStringValue('created_by'),
            onlyAdminsCanMessage: Value(conv.getBoolValue('only_admins_can_message')),
            disappearingDuration: Value(conv.getIntValue('disappearing_duration')),
            isPinned: Value(existingConv?.isPinned ?? false),
            lastMessagePreview: Value(keepLocal
                ? existingConv?.lastMessagePreview
                : (conv.getStringValue('last_message_preview').isEmpty
                    ? existingConv?.lastMessagePreview
                    : conv.getStringValue('last_message_preview'))),
            lastMessageAt: Value(keepLocal ? localAt : (serverAt ?? localAt)),
            createdAt: DateTime.tryParse(conv.created) ?? DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        await db.conversationsDao.upsertMember(
          ConversationMembersTableCompanion.insert(
            id: m.id, conversationId: conv.id, userId: myId,
            role: Value(m.getStringValue('role').isEmpty ? 'member' : m.getStringValue('role')),
            joinedAt: DateTime.tryParse(m.getStringValue('joined_at')) ?? DateTime.now(),
          ),
        );
        // getFullList (not getList's 30 cap) so large groups sync fully.
        final others = await _pb.collection('conversation_members').getFullList(
          filter: 'conversation_id="${conv.id}"&&user_id!="$myId"',
          expand: 'user_id', batch: 200,
        );
        final serverMemberIds = <String>{myId};
        // Join-triggered rotate, sync-discovery variant: if the SSE create
        // event was missed (offline admin), a member row that is NEW to this
        // device is discovered here. Must run BEFORE the upsert below makes
        // the row exist locally — same-map debounce collapses the duplicate
        // scheduling when the SSE handler fired moments earlier.
        final localMemberIds = (await db.conversationsDao
                .getAllMembersForConversation(conv.id))
            .map((lm) => lm.userId)
            .toSet();
        for (final om in others) {
          serverMemberIds.add(om.getStringValue('user_id'));
          final u = om.expand['user_id']?.firstOrNull;
          if (u != null) await _cacheUserRecord(u);
          if (!localMemberIds.contains(om.getStringValue('user_id'))) {
            await _maybeScheduleRotate(conv.id, om.getStringValue('user_id'));
          }
          await db.conversationsDao.upsertMember(
            ConversationMembersTableCompanion.insert(
              id: om.id, conversationId: conv.id,
              userId: om.getStringValue('user_id'),
              role: Value(om.getStringValue('role').isEmpty ? 'member' : om.getStringValue('role')),
              joinedAt: DateTime.tryParse(om.getStringValue('joined_at')) ?? DateTime.now(),
            ),
          );
        }

        // Reconcile removals: drop local members who are no longer on the
        // server (fixes "removed member still shows" on the other device).
        final localForConv =
            await db.conversationsDao.getMembersForConversation(conv.id);
        for (final lm in localForConv) {
          if (!serverMemberIds.contains(lm.userId)) {
            await (db.delete(db.conversationMembersTable)
                  ..where((t) => t.conversationId.equals(conv.id)
                      & t.userId.equals(lm.userId)))
                .go();
          }
        }
      }

      final activeConvIds = res.items
          .map((m) => m.expand['conversation_id']?.firstOrNull?.id)
          .whereType<String>()
          .toSet();

      final localMembers = await db.conversationsDao.getMembershipsOfUser(myId);
      for (final lm in localMembers) {
        if (lm.role != 'left' && !activeConvIds.contains(lm.conversationId)) {
          final conv = await db.conversationsDao.getConversationById(lm.conversationId);
          if (conv?.type == 'group') {
            await (db.update(db.conversationMembersTable)
                  ..where((t) => t.conversationId.equals(lm.conversationId)
                      & t.userId.equals(myId)))
                .write(const ConversationMembersTableCompanion(role: Value('left')));
            // We did NOT leave from THIS device (leaveGroup sets 'left'
            // locally first, so the branch above is skipped there) — the
            // server dropped our membership: an admin removed us (#17).
            // Wipe the cached group key so we can neither decrypt nor send
            // anything further, and drop a local-only info bubble so the
            // removal is visible in the timeline even if the removal SSE
            // message was missed (e.g. offline at the time).
            try {
              await storage.delete(key: 'group_key_${lm.conversationId}');
              await storage.write(
                  key: 'contact_key_${lm.conversationId}_gk', value: '');
              await _emitLocalSystemMessage(
                lm.conversationId,
                'You were removed from this group',
              );
            } catch (e) {
              debugPrint('[Group] membership-loss cleanup failed: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Conv] sync: $e');
    }
  }

  Future<List<Conversation>> _convRowsToEntities(
      List<ConversationsTableData> rows) async {
    final myId = await _myId();

    // ── Pass 1: best direct-conv-row per counter-party + cache the peer ──
    // For DMs with the same peer we keep the row with the most recent message.
    final bestDirectByUser = <String, ConversationsTableData>{};
    final otherByConvId = <String, User?>{};
    for (final r in rows) {
      if (r.type != 'direct') continue;
      final other = await _getOtherUser(r.id, myId);
      otherByConvId[r.id] = other;
      if (other == null) continue;
      final candidateScore = r.lastMessageAt ?? r.createdAt;
      final existing = bestDirectByUser[other.id];
      if (existing == null ||
          candidateScore.isAfter(existing.lastMessageAt ?? existing.createdAt)) {
        bestDirectByUser[other.id] = r;
      }
    }

    // ── Pass 2: emit in ORIGINAL DB order (pinned desc, then last_msg desc).
    //    DMs and groups mix naturally — no more "all DMs then all groups".
    final out = <Conversation>[];
    for (final r in rows) {
      if (r.type == 'direct') {
        final other = otherByConvId[r.id];
        if (other == null) {
          // Peer not yet in local user cache — drop this row from the
          // chat list. The Friends section below surfaces them.
          continue;
        }
        if (bestDirectByUser[other.id]?.id != r.id) continue; // dup, kept the newer row
        final count = await _getMemberCount(r.id);
        out.add(_convDataToEntity(r, other, memberCount: count));
      } else {
        final count = await _getMemberCount(r.id);
        out.add(_convDataToEntity(r, null, memberCount: count));
      }
    }
    return out;
  }

  Future<int> _getMemberCount(String convId) async =>
      (await db.conversationsDao.getMembersForConversation(convId)).length;

  Future<User?> _getOtherUser(String convId, String myId) async {
    final members = await db.conversationsDao.getMembersForConversation(convId);
    for (final m in members) {
      if (m.userId != myId) {
        final u = await db.usersDao.getUserById(m.userId);
        if (u != null) return _tableUserToEntity(u);
      }
    }
    return null;
  }

  Conversation _convDataToEntity(
      ConversationsTableData r, User? otherUser, {int? memberCount}) =>
      Conversation(
        id: r.id, type: r.type, name: r.name, iconUrl: r.iconUrl,
        lastMessagePreview: r.lastMessagePreview,
        lastMessageAt: r.lastMessageAt,
        isPinned: r.isPinned, otherUser: otherUser,
        onlyAdminsCanMessage: r.onlyAdminsCanMessage,
        memberCount: memberCount ?? 0,
        unreadCount: r.unreadCount,
      );

  Message _rowToMessage(MessagesTableData r, String myId) => Message(
    localId: r.localId, serverId: r.serverId,
    conversationId: r.conversationId, senderId: r.senderId,
    type: r.type, decryptedBody: r.decryptedBody,
    replyToId: r.replyToId,
    replyPreview: r.replyPreview,
    isDeletedForEveryone: r.isDeletedForEveryone,
    isDeletedForMe: r.isDeletedForMe,
    isPinned: r.isPinned, isStarred: r.isStarred,
    status: r.status, createdAt: r.createdAt,
    mediaId: r.mediaId,
  );

  User _tableUserToEntity(dynamic u, {String? groupRole}) => User(
    id: u.id, displayName: u.displayName, username: u.username,
    email: u.email ?? '', friendCode: u.friendCode, avatarUrl: u.avatarUrl,
    about: u.about, publicKey: u.publicKey, isOnline: u.isOnline,
    lastSeen: u.lastSeen, createdAt: u.createdAt, groupRole: groupRole,
  );

  Future<void> _cacheUserRecord(RecordModel r) async {
    final avatar = r.getStringValue('avatar');
    await db.usersDao.upsertUser(UsersTableCompanion(
      id:          Value(r.id),
      displayName: Value(r.getStringValue('display_name')),
      username:    Value(r.getStringValue('username')),
      email:       Value(r.getStringValue('email')),
      avatarUrl:   Value(avatar.isEmpty ? null
          : '${_pb.baseUrl}/api/files/users/${r.id}/$avatar'),
      friendCode:  Value(r.getStringValue('friend_code')),
      publicKey:   Value(r.getStringValue('public_key').isEmpty
          ? null : r.getStringValue('public_key')),
      isOnline:    Value(r.getBoolValue('is_online')),
      createdAt:   Value(DateTime.tryParse(r.created) ?? DateTime.now()),
      updatedAt:   Value(DateTime.now()),
    ));
  }
}

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  final repo = MessageRepositoryImpl(
    pbClient:           ref.watch(pocketbaseClientProvider),
    db:                 ref.read(appDatabaseProvider),
    storage:            ref.read(secureStorageProvider),
    encryption:         ref.read(encryptionServiceProvider),
    mediaUploadService: ref.read(mediaUploadServiceProvider),
  );
  FcmService.setRepository(repo);
  return repo;
});
// REPLACE the existing deleteMessage with this:
