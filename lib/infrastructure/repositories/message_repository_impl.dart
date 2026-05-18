import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show OrderingMode, OrderingTerm, Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:uuid/uuid.dart';

import '../../core/network/pocketbase_client.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/app_settings_table.dart';
import '../../data/local/database/tables/conversations_table.dart';
import '../../data/local/database/tables/conversation_members_table.dart';
import '../../data/local/database/tables/messages_table.dart';
import '../../data/local/database/tables/users_table.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/message_repository.dart';
import '../../features/chat/providers/chat_provider.dart' show ReactionGroup;
import '../../services/encryption_service.dart';
import '../../services/media_upload_service.dart';
import '../../data/local/secure_storage/secure_storage_service.dart';

class MessageRepositoryImpl implements MessageRepository {
  MessageRepositoryImpl({
    required this.pbClient,
    required this.db,
    required this.storage,
    required this.encryption,
    required this.mediaUploadService,
  }) {
    _initGlobalSubscriptions();
    _initConnectivityRetry();
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

  // ── Global subscriptions (set up once for all conversations) ──

  void _initGlobalSubscriptions() {
    // Messages subscription — handles incoming messages from all conversations
    _pb.collection('messages').subscribe('*', (event) async {
      if (event.record == null) return;
      final r = event.record!;
      final myId = await _myId();

      // Skip our own sent messages — already handled optimistically in sendMessage
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
        final key = await _getConvKey(convId, myId);
        await _cacheMsg(r, myId, key);
        await _markDelivered(r.id, convId, myId);
        // Drift stream auto-emits — no manual push needed
      } catch (e) {
        debugPrint('[Msg] incoming error: $e');
      }
    });

    // Conversation subscriptions — keep home screen in sync when a chat is
    // created or membership changes on the other device.
    _pb.collection('conversations').subscribe('*', (_) {
      _syncConversationsBackground();
    });
    _pb.collection('conversation_members').subscribe('*', (_) {
      _syncConversationsBackground();
    });

    // Receipts subscription — updates tick status
    _pb.collection('message_receipts').subscribe('*', (event) async {
      if (event.record == null) return;
      final r   = event.record!;
      final myId = await _myId();
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

    // Reactions subscription — fires on both devices when any reaction changes
    _pb.collection('reactions').subscribe('*', (event) async {
      if (event.record == null) return;
      final msgServerId = event.record!.getStringValue('message_id');
      if (msgServerId.isNotEmpty) {
        debugPrint('[Reaction] Change detected for message: $msgServerId');
        _reactionsCtrl.add(msgServerId);
      }
    });
  }

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
    // Start background fetch (saves to Drift → auto-emits via stream below)
    _fetchAndCacheMessages(conversationId);

    return db.messagesDao
        .watchMessages(conversationId)
        .asyncMap((rows) => _rowsToMessages(rows));
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

    debugPrint('[Msg] Sending message - localId: $localId, convId: $conversationId');

    // ── Step 1: Optimistic insert to Drift ────────────────────
    // Drift stream auto-emits IMMEDIATELY — message appears NOW.
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
      createdAt:      now,
      updatedAt:      now,
    ));
    debugPrint('[Msg] Message added to local DB with status: pending');

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
    
    EncryptResult encrypted;
    try {
      final key = await _getConvKey(conversationId, myId);
      encrypted  = await encryption.encryptMessage(plaintext, key);
      debugPrint('[Msg] Message encrypted successfully');
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
      replyServerId  = replyMsg?.serverId;
      }

      debugPrint('[Msg] Creating message record on server');
      final record = await _pb.collection('messages').create(body: {
        'conversation_id':        conversationId,
        'sender_id':              myId,
        'type':                   'text',
        'encrypted_body':         encrypted.ciphertext,
        'iv':                     encrypted.iv,
        'reply_to_id':            replyServerId ?? '',   // Server ID, not local
        'reply_preview':          replyPreview ?? '',    // Store plain text preview
        'is_deleted_for_everyone': false,
      });
      debugPrint('[Msg] Message created on server with serverId: ${record.id}');

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
        replyPreview:   Value(replyPreview),
        status:         Value('sent'),
        createdAt:      createdAt,
        updatedAt:      DateTime.now(),
      ));
      debugPrint('[Msg] Local message updated with status: sent');

      await db.conversationsDao.updateLastMessage(
        conversationId,
        plaintext.length > 50 ? '${plaintext.substring(0, 50)}…' : plaintext,
        DateTime.now(),
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
      // Step A: Get conversation key and encrypt a dummy value (schema requires it)
      EncryptResult encrypted;
      try {
        final key = await _getConvKey(conversationId, myId);
        encrypted = await encryption.encryptMessage(durationText ?? '', key);
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
          videoWidth:  videoWidth,
          videoHeight: videoHeight,
        );
      } else if (mediaType == 'document') {
        mediaId = await mediaUploadService.uploadDocument(
          mediaFile,
          conversationId,
          messageServerId,
        );
      } else {
        mediaId = await mediaUploadService.uploadVoice(
          mediaFile,
          conversationId,
          durationSeconds,
          messageServerId,
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

    for (final msg in pending) {
      if (msg.decryptedBody == null) continue;
      await retryMessage(msg.localId);
    }
  }

  @override
  Future<void> retryMessage(String localId) async {
    final msg = await db.messagesDao.getMessageByLocalId(localId);
    if (msg == null || msg.decryptedBody == null) return;

    // Reset to pending -> Drift stream auto-emits -> retry button disappears
    await db.messagesDao.updateMessageStatus(localId, 'pending');

    // Re-upload with the SAME localId - no new entry created
    await _uploadMessage(
      localId:        localId,
      conversationId: msg.conversationId,
      myId:           await _myId(),
      plaintext:      msg.decryptedBody!,
      createdAt:      msg.createdAt,
    );
  }

  // ── Mark read ─────────────────────────────────────────────────

  @override
  Future<void> markConversationRead(String conversationId) async {
    try {
      final myId = await _myId();
      final res  = await _pb.collection('message_receipts').getList(
        filter: 'conversation_id="$conversationId"'
            '&&recipient_id="$myId"&&read_at=""',
      );
      for (final r in res.items) {
        await _pb.collection('message_receipts').update(r.id, body: {
          'read_at': DateTime.now().toIso8601String(),
        });
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
    } catch (e) {
      debugPrint('[Msg] loadMore: $e');
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
    }
  }

  @override
  Future<void> toggleStar(String localId) async {
    final msg = await db.messagesDao.getMessageByLocalId(localId);
    if (msg == null) return;
    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: msg.localId, conversationId: msg.conversationId,
      senderId: msg.senderId, type: msg.type,
      encryptedBody: msg.encryptedBody, iv: msg.iv,
      isStarred: Value(!msg.isStarred), status: Value(msg.status),
      createdAt: msg.createdAt, updatedAt: DateTime.now(),
    ));
  }

  @override
  Future<void> togglePin(String localId, String conversationId, bool pin) async {
    final msg = await db.messagesDao.getMessageByLocalId(localId);
    if (msg == null) return;

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
    final rows = await db.messagesDao.getStarredMessages(conversationId);
    final myId = await _myId();
    return rows.map((r) => _rowToMessage(r, myId)).toList();
  }

  @override
  Future<List<Message>> getPinnedMessages(String conversationId) async {
    final rows = await db.messagesDao.getPinnedMessages(conversationId);
    final myId = await _myId();
    return rows.map((r) => _rowToMessage(r, myId)).toList();
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
      await db.conversationsDao.upsertConversation(
        ConversationsTableCompanion(
          id: Value(conversationId),
          disappearingDuration: Value(seconds),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } catch (e) {
      debugPrint('[Conv] setDisappearing: $e');
    }
  }

  // ── Group admin ───────────────────────────────────────────────

  @override
  Future<bool> isCurrentUserAdmin(String conversationId) async {
    final myId  = await _myId();
    final member = await db.conversationsDao
        .getMemberByUserAndConv(myId, conversationId);
    return member?.role == 'admin';
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
      if (u != null) users.add(_tableUserToEntity(u));
    }
    return users;
  }

  @override
  Future<void> addMemberToGroup(
      String conversationId, String userId) async {
    final myId = await _myId();
    if (!await isCurrentUserAdmin(conversationId)) {
      throw StateError('Only admins can add members');
    }

    // a) Create conversation_members record in PocketBase
    final memberRecord = await _pb.collection('conversation_members').create(
      body: {
        'conversation_id': conversationId,
        'user_id':         userId,
        'role':            'member',
        'joined_at':       DateTime.now().toUtc().toIso8601String(),
      },
    );

    // b) Get current group key + key_version
    final groupKey = await encryption.getOrFetchGroupKey(conversationId, myId);
    int currentVersion = 1;
    try {
      final myKeyRecord = await _pb.collection('group_keys').getFirstListItem(
        'conversation_id="$conversationId"&&user_id="$myId"',
      );
      currentVersion = myKeyRecord.getIntValue('key_version');
    } catch (_) {}

    // c) Get new member's public key
    var newUser = await db.usersDao.getUserById(userId);
    if (newUser == null || newUser.publicKey == null) {
      try {
        final r = await _pb.collection('users').getOne(userId);
        await _cacheUserRecord(r);
        newUser = await db.usersDao.getUserById(userId);
      } catch (_) {}
    }
    if (newUser?.publicKey == null) {
      throw StateError('Cannot fetch public key for new member');
    }

    // d) Encrypt group key for new member
    final encryptedKey = await encryption.encryptGroupKeyForMember(
      groupKey, newUser!.publicKey!, conversationId,
    );

    // e) Create group_keys record
    await _pb.collection('group_keys').create(body: {
      'conversation_id':      conversationId,
      'user_id':              userId,
      'encrypted_key':        encryptedKey,
      'encrypted_by_user_id': myId,
      'key_version':          currentVersion,
    });

    // f) Update Drift
    await db.conversationsDao.upsertMember(
      ConversationMembersTableCompanion.insert(
        id:             memberRecord.id,
        conversationId: conversationId,
        userId:         userId,
        role:           const Value('member'),
        joinedAt:       DateTime.now(),
      ),
    );
  }

  @override
  Future<void> removeMemberFromGroup(
      String conversationId, String userId) async {
    if (!await isCurrentUserAdmin(conversationId)) {
      throw StateError('Only admins can remove members');
    }

    // a) Find and delete conversation_members record in PocketBase
    try {
      final res = await _pb.collection('conversation_members').getFirstListItem(
        'conversation_id="$conversationId"&&user_id="$userId"',
      );
      await _pb.collection('conversation_members').delete(res.id);
    } catch (_) {}

    // b) Delete their group_keys record
    try {
      final kRes = await _pb.collection('group_keys').getFirstListItem(
        'conversation_id="$conversationId"&&user_id="$userId"',
      );
      await _pb.collection('group_keys').delete(kRes.id);
    } catch (_) {}

    // c) Rotate the group key — forward secrecy
    await _rotateGroupKey(conversationId);

    // d) Update Drift: delete member row
    final localMember = await db.conversationsDao
        .getMemberByUserAndConv(userId, conversationId);
    if (localMember != null) {
      await (db.delete(db.conversationMembersTable)
            ..where((t) => t.id.equals(localMember.id)))
          .go();
    }
  }

  Future<void> _rotateGroupKey(String conversationId) async {
    final myId = await _myId();

    // a) Generate new group key
    final newKey = encryption.generateGroupKey();

    // b) Determine new key version
    int newVersion = 1;
    try {
      final existing = await _pb.collection('group_keys').getList(
        filter:  'conversation_id="$conversationId"',
        perPage: 1,
        sort:    '-key_version',
      );
      if (existing.items.isNotEmpty) {
        newVersion = existing.items.first.getIntValue('key_version') + 1;
      }
    } catch (_) {}

    // c) Get all remaining members
    final members = await db.conversationsDao
        .getMembersForConversation(conversationId);

    // d+e) Encrypt and create new group_keys record for each member
    for (final m in members) {
      var u = await db.usersDao.getUserById(m.userId);
      if (u == null || u.publicKey == null) {
        try {
          final r = await _pb.collection('users').getOne(m.userId);
          await _cacheUserRecord(r);
          u = await db.usersDao.getUserById(m.userId);
        } catch (_) {}
      }
      if (u?.publicKey == null) continue;

      final encryptedKey = await encryption.encryptGroupKeyForMember(
        newKey, u!.publicKey!, conversationId,
      );
      try {
        await _pb.collection('group_keys').create(body: {
          'conversation_id':      conversationId,
          'user_id':              m.userId,
          'encrypted_key':        encryptedKey,
          'encrypted_by_user_id': myId,
          'key_version':          newVersion,
        });
      } catch (e) {
        debugPrint('[GroupKey] Failed to create key for ${m.userId}: $e');
      }
    }

    // f) Delete ALL old group_keys for this conversation (version < newVersion)
    try {
      final old = await _pb.collection('group_keys').getList(
        filter:  'conversation_id="$conversationId"&&key_version<$newVersion',
        perPage: 200,
      );
      for (final r in old.items) {
        try { await _pb.collection('group_keys').delete(r.id); } catch (_) {}
      }
    } catch (_) {}

    // g) Update local cache with new key, clear derived shared key cache
    await storage.write(
      key:   'group_key_$conversationId',
      value: base64.encode(newKey),
    );
    // Clear the per-member derived key cache so re-encryption uses new material
    await storage.write(
      key:   'contact_key_${conversationId}_groupkey',
      value: '',
    );
  }

  @override
  Future<void> promoteMemberToAdmin(
      String conversationId, String userId) async {
    await _updateMemberRole(conversationId, userId, 'admin');
  }

  @override
  Future<void> demoteAdminToMember(
      String conversationId, String userId) async {
    await _updateMemberRole(conversationId, userId, 'member');
  }

  Future<void> _updateMemberRole(
      String conversationId, String userId, String role) async {
    // Find PocketBase record
    final res = await _pb.collection('conversation_members').getFirstListItem(
      'conversation_id="$conversationId"&&user_id="$userId"',
    );
    await _pb.collection('conversation_members').update(res.id, body: {'role': role});

    // Update Drift
    final local = await db.conversationsDao
        .getMemberByUserAndConv(userId, conversationId);
    if (local != null) {
      await db.conversationsDao.upsertMember(
        ConversationMembersTableCompanion.insert(
          id:             local.id,
          conversationId: conversationId,
          userId:         userId,
          role:           Value(role),
          joinedAt:       local.joinedAt,
        ),
      );
    }
  }

  @override
  Future<void> setOnlyAdminsCanMessage(
      String conversationId, bool value) async {
    if (!await isCurrentUserAdmin(conversationId)) {
      throw StateError('Only admins can change this setting');
    }
    await _pb.collection('conversations').update(
      conversationId,
      body: {'only_admins_can_message': value},
    );
    // Update Drift
    await db.conversationsDao.upsertConversation(
      ConversationsTableCompanion(
        id:                   Value(conversationId),
        onlyAdminsCanMessage: Value(value),
        updatedAt:            Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> leaveGroup(String conversationId) async {
    final myId = await _myId();

    // a) Check if I'm the sole admin — if so, promote earliest-joining other member
    final allMembers = await db.conversationsDao
        .getMembersForConversation(conversationId);
    final admins  = allMembers.where((m) => m.role == 'admin').toList();
    final others  = allMembers
        .where((m) => m.userId != myId)
        .toList()
      ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));

    if (admins.length == 1 && admins.first.userId == myId && others.isNotEmpty) {
      try {
        await _updateMemberRole(conversationId, others.first.userId, 'admin');
      } catch (_) {}
    }

    // b) Delete my conversation_members record from PocketBase
    try {
      final res = await _pb.collection('conversation_members').getFirstListItem(
        'conversation_id="$conversationId"&&user_id="$myId"',
      );
      await _pb.collection('conversation_members').delete(res.id);
    } catch (_) {}

    // c) Delete my group_keys record
    try {
      final kRes = await _pb.collection('group_keys').getFirstListItem(
        'conversation_id="$conversationId"&&user_id="$myId"',
      );
      await _pb.collection('group_keys').delete(kRes.id);
    } catch (_) {}

    // d) Remove from local Drift
    await db.conversationsDao.deleteConversation(conversationId);

    // e) Clear cached group key
    await storage.write(key: 'group_key_$conversationId', value: '');
  }

  // ── Private helpers ───────────────────────────────────────────

  Future<String> _myId() async =>
      await db.settingsDao.getSetting(AppSettingsKeys.currentUserId) ?? '';

  Future<void> _fetchAndCacheMessages(String conversationId) async {
    try {
      final myId = await _myId();
      final res  = await _pb.collection('messages').getList(
        filter:  'conversation_id="$conversationId"&&is_deleted_for_everyone=false',
        sort:    '-created',
        perPage: 40,
      );
      final key = await _getConvKey(conversationId, myId);
      for (final r in res.items) {
        await _cacheMsg(r, myId, key);
      }
    } catch (e) {
      debugPrint('[Msg] fetch error (offline?): $e');
    }
  }

  Future<void> _cacheMsg(RecordModel r, String myId, List<int> key) async {
    final encBody = r.getStringValue('encrypted_body');
    final iv      = r.getStringValue('iv');
    String? decrypted;
    if (encBody.isNotEmpty && iv.isNotEmpty && encBody != '__pending__') {
      decrypted = await encryption.decryptMessage(encBody, iv, key);
    }
    final existing = await db.messagesDao.getMessageByServerId(r.id);
    // Don't overwrite a 'read' status with 'delivered'
    final existingStatus = existing?.status ?? '';
    final status = r.getStringValue('sender_id') == myId
        ? (existingStatus.isEmpty ? 'sent' : existingStatus)
        : 'delivered';

    final rawMediaId = r.getStringValue('media_id');
    // 'file' is the server enum used for documents; normalise to 'document' locally.
    final rawType = r.getStringValue('type');
    final localType = rawType == 'file' ? 'document' : rawType;
    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId:               existing?.localId ?? _uuid.v4(),
      serverId:              Value(r.id),
      conversationId:        r.getStringValue('conversation_id'),
      senderId:              r.getStringValue('sender_id'),
      type:                  localType,
      encryptedBody:         encBody,
      iv:                    iv,
      decryptedBody:         Value(decrypted),
      replyToId:             Value(r.getStringValue('reply_to_id').isEmpty
          ? null : r.getStringValue('reply_to_id')),
      replyPreview:          Value(r.getStringValue('reply_preview').isEmpty
        ? null : r.getStringValue('reply_preview')),
      isDeletedForEveryone:  Value(r.getBoolValue('is_deleted_for_everyone')),
      mediaId:               Value(rawMediaId.isEmpty ? null : rawMediaId),
      status:                Value(status),
      createdAt:             DateTime.tryParse(r.created) ?? DateTime.now(),
      updatedAt:             DateTime.now(),
    ));
  }

  Future<void> _updateMsgReceiptStatus(
      String localId, String serverId) async {
    try {
      final res = await _pb.collection('message_receipts').getList(
        filter: 'message_id="$serverId"',
      );
      if (res.items.isEmpty) {
        debugPrint('[Receipt] No receipts found for message: $serverId');
        return;
      }

      final readCount = res.items
          .where((r) => r.getStringValue('read_at').isNotEmpty)
          .length;
      final deliveredCount = res.items
          .where((r) => r.getStringValue('delivered_at').isNotEmpty)
          .length;
      final totalRecipients = res.items.length;

      debugPrint(
        '[Receipt] Status update for $serverId - '
        'delivered: $deliveredCount/$totalRecipients, '
        'read: $readCount/$totalRecipients',
      );

      final allRead      = res.items.every(
          (r) => r.getStringValue('read_at').isNotEmpty);
      final allDelivered = res.items.every(
          (r) => r.getStringValue('delivered_at').isNotEmpty);

      final status = allRead
          ? 'read'
          : allDelivered
              ? 'delivered'
              : 'sent';

      debugPrint('[Receipt] Updating local message status to: $status');
      await db.messagesDao.updateMessageStatus(localId, status);
    } catch (e) {
      debugPrint('[Receipt] ERROR in statusUpdate: $e');
    }
  }

  Future<void> _markDelivered(
      String serverId, String convId, String myId) async {
    try {
      final res = await _pb.collection('message_receipts').getList(
        filter: 'message_id="$serverId"&&recipient_id="$myId"',
        perPage: 1,
      );
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      if (res.items.isEmpty) {
        await _pb.collection('message_receipts').create(body: {
          'message_id':     serverId,
          'conversation_id': convId,
          'recipient_id':   myId,
          'delivered_at':   nowUtc,
        });
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

  Future<List<int>> _getConvKey(String convId, String myId) async {
    final conv = await db.conversationsDao.getConversationById(convId);
    if (conv?.type == 'group') {
      return encryption.getOrFetchGroupKey(convId, myId);
    }

    final members = await db.conversationsDao.getMembersForConversation(convId);
    final otherUserId = members
        .where((m) => m.userId != myId)
        .map((m) => m.userId)
        .firstOrNull;

    if (otherUserId == null) return List.filled(32, 0);

    var u = await db.usersDao.getUserById(otherUserId);
    if (u == null || u.publicKey == null) {
      try {
        final r = await _pb.collection('users').getOne(otherUserId);
        await _cacheUserRecord(r);
        u = await db.usersDao.getUserById(otherUserId);
      } catch (_) {}
    }
    if (u?.publicKey == null) return List.filled(32, 0);
    return encryption.getOrDeriveConversationKey(convId, u!.publicKey!);
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
        await db.conversationsDao.upsertConversation(
          ConversationsTableCompanion.insert(
            id:          conv.id,
            type:        conv.getStringValue('type'),
            name:        Value(conv.getStringValue('name').isEmpty
                ? null : conv.getStringValue('name')),
            iconUrl:     Value(iconUrl),
            createdById: conv.getStringValue('created_by'),
            onlyAdminsCanMessage: Value(conv.getBoolValue('only_admins_can_message')),
            lastMessagePreview: Value(
                conv.getStringValue('last_message_preview').isEmpty
                    ? null : conv.getStringValue('last_message_preview')),
            lastMessageAt: Value(
                conv.getStringValue('last_message_at').isEmpty
                    ? null : DateTime.tryParse(conv.getStringValue('last_message_at'))),
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
        final others = await _pb.collection('conversation_members').getList(
          filter: 'conversation_id="${conv.id}"&&user_id!="$myId"',
          expand: 'user_id',
        );
        for (final om in others.items) {
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
      final members = await db.conversationsDao.getMembersForConversation(r.id);
      convs.add(_convDataToEntity(r, null, memberCount: members.length));
    }
    return convs;
  }

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
        memberCount: memberCount,
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

  User _tableUserToEntity(dynamic u) => User(
    id: u.id, displayName: u.displayName, username: u.username,
    email: u.email ?? '', friendCode: u.friendCode, avatarUrl: u.avatarUrl,
    about: u.about, publicKey: u.publicKey, isOnline: u.isOnline,
    lastSeen: u.lastSeen, createdAt: u.createdAt,
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
  return MessageRepositoryImpl(
    pbClient:           ref.watch(pocketbaseClientProvider),
    db:                 ref.read(appDatabaseProvider),
    storage:            ref.read(secureStorageProvider),
    encryption:         ref.read(encryptionServiceProvider),
    mediaUploadService: ref.read(mediaUploadServiceProvider),
  );
});
// REPLACE the existing deleteMessage with this:
