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

  final _reactionsCtrl = StreamController<String>.broadcast();

  @override
  Stream<String> get reactionsChanges => _reactionsCtrl.stream;

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
      'message_receipts', 'reactions',
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
        // Always acknowledge delivery so the sender's tick advances.
        await _markDelivered(r.id, convId, myId);
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

  Future<void> _subMembers() async {
    await _pb.collection('conversation_members').subscribe('*', (_) {
      _syncConversationsBackground();
    });
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

  // ── Poll fallback ─────────────────────────────────────────────
  // For devices where SSE is flaky or FCM is unavailable (de-Googled ROMs),
  // poll the active conversations every few seconds so incoming messages,
  // receipts, reactions, pins and deletions still surface without a reopen.

  void _startPollFallback() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      // If SSE is healthy this is cheap insurance; if it's down it's the only
      // thing keeping the device current.
      try {
        final myId = await _myId();
        if (myId.isEmpty) return;
        final active = _activeConversationId;
        if (active != null) {
          await _fetchAndCacheMessages(active);
          await _reconcileReceiptsForConversation(active, myId);
        }
        await _syncConversations(myId);
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
  @override
  Stream<List<Message>> watchMessages(String conversationId) {
    // Track the on-screen conversation for the poll fallback.
    _activeConversationId = conversationId;
    // Purge any locally-expired disappearing messages before showing the chat,
    // then start the background fetch. The Drift stream auto-emits on delete.
    db.messagesDao.deleteExpiredMessages();
    // Collapse any duplicate rows the FCM background isolate raced in.
    db.messagesDao.dedupByServerId();
    // Start background fetch (saves to Drift → auto-emits via stream below)
    _fetchAndCacheMessages(conversationId);

    return db.messagesDao
        .watchMessages(conversationId)
        .asyncMap((rows) async {
          debugPrint('[Msg] watchMessages EMIT — convId: $conversationId, rowCount: ${rows.length}');
          return _rowsToMessages(rows);
        });
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

      return res.items.map((record) {
        return Message(
          localId:        record.id,
          serverId:       record.getStringValue('message_id'),
          conversationId: record.getStringValue('conversation_id'),
          senderId:       record.getStringValue('sender_id'),
          type:           'text',
          decryptedBody:  record.getStringValue('message_preview'),
          status:         'read',
          createdAt:      DateTime.tryParse(record.created) ?? DateTime.now(),
          isStarred:      true,
        );
      }).toList();
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
    final members = await db.conversationsDao
        .getMembersForConversation(conversationId);
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
  Future<void> addMemberToGroup(
      String conversationId, String newUserId) async {
    final myId = await _myId();
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }

    // Idempotent membership: the server has UNIQUE(conversation_id,user_id),
    // so re-adding a previously-removed member must NOT create a duplicate.
    RecordModel memberRecord;
    try {
      memberRecord = await _pb.collection('conversation_members').getFirstListItem(
        'conversation_id="$conversationId"&&user_id="$newUserId"',
      );
      // Already a member — nothing to add (avoids duplicate rows/keys).
      debugPrint('[Group] $newUserId already a member — skipping duplicate add.');
    } catch (_) {
      memberRecord = await _pb.collection('conversation_members').create(
        body: {
          'conversation_id': conversationId,
          'user_id':         newUserId,
          'role':            'member',
        },
      );
    }

    String? newPublicKey;
    try {
      final r = await _pb.collection('users').getOne(newUserId);
      await _cacheUserRecord(r);
      newPublicKey = r.getStringValue('public_key');
    } catch (_) {}

    if (newPublicKey == null || newPublicKey.isEmpty) {
      throw Exception('No public key for user');
    }

    // Rotate the group key so the newly-added member cannot read history
    // from before they joined, and everyone converges on one current key.
    await _rotateGroupKey(conversationId, myId);

    await db.conversationsDao.upsertMember(
      ConversationMembersTableCompanion.insert(
        id:             memberRecord.id,
        conversationId: conversationId,
        userId:         newUserId,
        joinedAt:       DateTime.now(),
        role:           const Value('member'),
      ),
    );
  }

  @override
  Future<void> removeMemberFromGroup(
      String conversationId, String userId) async {
    final myId = await _myId();
    if (!await isCurrentUserAdmin(conversationId)) {
      throw Exception('Not an admin');
    }

    // Delete ALL membership rows for this user (defensive against any
    // pre-existing duplicates), tolerating a missing record.
    try {
      final memberRecs = await _pb.collection('conversation_members').getFullList(
        filter: 'conversation_id="$conversationId"&&user_id="$userId"', batch: 50,
      );
      for (final rec in memberRecs) {
        await _pb.collection('conversation_members').delete(rec.id);
      }
    } catch (e) {
      debugPrint('[Group] remove member server delete: $e');
    }

    // Remove all of the removed user's group-key rows so they can't decrypt.
    try {
      final keyRecs = await _pb.collection('group_keys').getFullList(
        filter: 'conversation_id="$conversationId"&&user_id="$userId"', batch: 50,
      );
      for (final rec in keyRecs) {
        await _pb.collection('group_keys').delete(rec.id);
      }
    } catch (_) {}

    // Fully remove locally (not a soft 'left' — they were removed by an admin).
    await (db.delete(db.conversationMembersTable)
          ..where((t) => t.conversationId.equals(conversationId)
              & t.userId.equals(userId)))
        .go();

    // Rotate the key so the removed member can't read future messages.
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
        }
      } catch (e) {
        debugPrint('[Conv] recipient lastMessage bump: $e');
      }
    }
  }

  /// Computes a sender's message status ('sent'/'delivered'/'read') from the
  /// current receipts. Used when re-caching own messages after a reinstall.
  Future<String> _computeSenderStatus(String serverId) async {
    try {
      final res = await _pb.collection('message_receipts').getFullList(
        filter: 'message_id="$serverId"', batch: 200,
      );
      if (res.isEmpty) return 'sent';
      final allRead = res.every((r) => r.getStringValue('read_at').isNotEmpty);
      final allDelivered =
          res.every((r) => r.getStringValue('delivered_at').isNotEmpty);
      return allRead ? 'read' : (allDelivered ? 'delivered' : 'sent');
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

      // Status is computed over the receipts that EXIST (one per recipient,
      // guaranteed unique by the server index). "All delivered/read" across
      // present recipients → delivered/read tick, matching WhatsApp/Signal.
      final allRead = items.every(
          (r) => r.getStringValue('read_at').isNotEmpty);
      final allDelivered = items.every(
          (r) => r.getStringValue('delivered_at').isNotEmpty);

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

      debugPrint('[Receipt] Updating local message status to: $computed');
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
      for (final m in membersRes.items) {
        final u = m.expand['user_id']?.firstOrNull;
        if (u != null) await _cacheUserRecord(u);
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
        for (final om in others) {
          serverMemberIds.add(om.getStringValue('user_id'));
          final u = om.expand['user_id']?.firstOrNull;
          if (u != null) await _cacheUserRecord(u);
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
    final directByOtherUser = <String, ConversationsTableData>{};
    final directOtherUsers = <String, User?>{};
    final groupRows = <ConversationsTableData>[];

    for (final r in rows) {
      final other = await _getOtherUser(r.id, myId);
      if (r.type != 'direct' || other == null) {
        groupRows.add(r);
        continue;
      }

      directOtherUsers.putIfAbsent(other.id, () => other);
      final existing = directByOtherUser[other.id];
      if (existing == null) {
        directByOtherUser[other.id] = r;
        continue;
      }

      final existingScore = existing.lastMessageAt ?? existing.createdAt;
      final candidateScore = r.lastMessageAt ?? r.createdAt;
      if (candidateScore.isAfter(existingScore)) {
        directByOtherUser[other.id] = r;
      }
    }

    final convs = <Conversation>[];
    convs.addAll(directByOtherUser.entries.map(
      (entry) => _convDataToEntity(entry.value, directOtherUsers[entry.key]),
    ));
    for (final r in groupRows) {
      final count = await _getMemberCount(r.id);
      convs.add(_convDataToEntity(r, null, memberCount: count));
    }
    return convs;
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
