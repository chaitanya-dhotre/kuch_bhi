import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value;
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
import '../../services/encryption_service.dart';
import '../../data/local/secure_storage/secure_storage_service.dart';

class MessageRepositoryImpl implements MessageRepository {
  MessageRepositoryImpl({
    required this.pbClient,
    required this.db,
    required this.storage,
    required this.encryption,
  }) {
    _initGlobalSubscriptions();
    _initConnectivityRetry();
  }

  final PocketBaseClient     pbClient;
  final AppDatabase          db;
  final SecureStorageService storage;
  final EncryptionService    encryption;

  PocketBase get _pb => pbClient.pb;
  static const _uuid = Uuid();

  // ── Global subscriptions (set up once for all conversations) ──

  void _initGlobalSubscriptions() {
    // Messages subscription — handles incoming messages from all conversations
    _pb.collection('messages').subscribe('*', (event) async {
      if (event.record == null) return;
      final r = event.record!;
      final myId = await _myId();

      // Skip our own sent messages — already handled optimistically in sendMessage
      if (r.getStringValue('sender_id') == myId) return;

      final convId = r.getStringValue('conversation_id');
      try {
        final key = await _getConvKey(convId, myId);
        await _cacheMsg(r, myId, key);
        await _markDelivered(r.id, convId, myId);
        // Drift stream auto-emits — no manual push needed
      } catch (e) {
        debugPrint('[Msg] incoming error: $e');
      }
    });

    // Receipts subscription — updates tick status
    _pb.collection('message_receipts').subscribe('*', (event) async {
      if (event.record == null) return;
      final r   = event.record!;
      final myId = await _myId();
      final msgServerId = r.getStringValue('message_id');

      try {
        final local = await db.messagesDao.getMessageByServerId(msgServerId);
        if (local == null) return;

        // Only update status for messages I sent
        if (local.senderId != myId) return;

        await _updateMsgReceiptStatus(local.localId, msgServerId);
        // Drift auto-emits after the status update above
      } catch (e) {
        debugPrint('[Receipt] update error: $e');
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

    // ── Step 2: Upload in background (does NOT block UI) ──────
    _uploadMessage(
      localId:        localId,
      conversationId: conversationId,
      myId:           myId,
      plaintext:      plaintext,
      replyToLocalId: replyToLocalId,
      createdAt:      now,
    );
  }

  Future<void> _uploadMessage({
    required String localId,
    required String conversationId,
    required String myId,
    required String plaintext,
    String? replyToLocalId,
    required DateTime createdAt,
  }) async {
    // Encrypt
    EncryptResult encrypted;
    try {
      final key = await _getConvKey(conversationId, myId);
      encrypted  = await encryption.encryptMessage(plaintext, key);
    } catch (e) {
      debugPrint('[Enc] Encrypt error: $e');
      await db.messagesDao.updateMessageStatus(localId, 'failed');
      return;
    }

    // Upload
    try {
      final record = await _pb.collection('messages').create(body: {
        'conversation_id':        conversationId,
        'sender_id':              myId,
        'type':                   'text',
        'encrypted_body':         encrypted.ciphertext,
        'iv':                     encrypted.iv,
        'reply_to_id':            replyToLocalId ?? '',
        'is_deleted_for_everyone': false,
      });

      // Update Drift with server ID + 'sent' status → auto-emits
      await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId:        localId,
        serverId:       Value(record.id),
        conversationId: conversationId,
        senderId:       myId,
        type:           'text',
        encryptedBody:  encrypted.ciphertext,
        iv:             encrypted.iv,
        decryptedBody:  Value(plaintext),
        replyToId:      Value(replyToLocalId),
        status:         Value('sent'),
        createdAt:      createdAt,
        updatedAt:      DateTime.now(),
      ));

      await db.conversationsDao.updateLastMessage(
        conversationId,
        plaintext.length > 50 ? '${plaintext.substring(0, 50)}…' : plaintext,
        DateTime.now(),
      );

      await _createReceipts(record.id, conversationId, myId);
    } catch (e) {
      debugPrint('[Msg] upload failed (offline?): $e');
      await db.messagesDao.updateMessageStatus(localId, 'failed');
      // Message stays visible in UI as 'failed' — user can retry
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

    return _createDirectConversation(myId, otherUserId);
  }

  Future<Conversation> _createDirectConversation(
      String myId, String otherUserId) async {
    final conv = await _pb.collection('conversations').create(body: {
      'type': 'direct', 'created_by': myId,
    });
    final myMember = await _pb.collection('conversation_members').create(body: {
      'conversation_id': conv.id, 'user_id': myId, 'role': 'admin',
    });
    await _pb.collection('conversation_members').create(body: {
      'conversation_id': conv.id, 'user_id': otherUserId, 'role': 'member',
    });

    await db.conversationsDao.upsertConversation(
      ConversationsTableCompanion.insert(
        id: conv.id, type: 'direct', createdById: myId,
        createdAt: DateTime.tryParse(conv.created) ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await db.conversationsDao.upsertMember(
      ConversationMembersTableCompanion.insert(
        id: myMember.id, conversationId: conv.id,
        userId: myId, joinedAt: DateTime.now(),
      ),
    );
    await db.conversationsDao.upsertMember(
      ConversationMembersTableCompanion.insert(
        id: _uuid.v4(), conversationId: conv.id,
        userId: otherUserId, joinedAt: DateTime.now(),
      ),
    );

    final otherUser = await db.usersDao.getUserById(otherUserId);
    return Conversation(
      id: conv.id, type: 'direct',
      otherUser: otherUser != null ? _tableUserToEntity(otherUser) : null,
    );
  }

  @override
  Future<void> deleteMessage(String localId, {bool forEveryone = false}) async {
    if (forEveryone) {
      final msg = await db.messagesDao.getMessageByLocalId(localId);
      if (msg?.serverId != null) {
        try {
          await _pb.collection('messages').update(msg!.serverId!, body: {
            'is_deleted_for_everyone': true,
          });
        } catch (_) {}
      }
    }
    await db.messagesDao.updateMessageStatus(localId, 'failed');
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

    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId:               existing?.localId ?? _uuid.v4(),
      serverId:              Value(r.id),
      conversationId:        r.getStringValue('conversation_id'),
      senderId:              r.getStringValue('sender_id'),
      type:                  r.getStringValue('type'),
      encryptedBody:         encBody,
      iv:                    iv,
      decryptedBody:         Value(decrypted),
      replyToId:             Value(r.getStringValue('reply_to_id').isEmpty
          ? null : r.getStringValue('reply_to_id')),
      isDeletedForEveryone:  Value(r.getBoolValue('is_deleted_for_everyone')),
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
      if (res.items.isEmpty) return;

      final allRead      = res.items.every(
          (r) => r.getStringValue('read_at').isNotEmpty);
      final allDelivered = res.items.every(
          (r) => r.getStringValue('delivered_at').isNotEmpty);

      final status = allRead
          ? 'read'
          : allDelivered
              ? 'delivered'
              : 'sent';

      await db.messagesDao.updateMessageStatus(localId, status);
    } catch (e) {
      debugPrint('[Receipt] statusUpdate: $e');
    }
  }

  Future<void> _markDelivered(
      String serverId, String convId, String myId) async {
    try {
      final res = await _pb.collection('message_receipts').getList(
        filter: 'message_id="$serverId"&&recipient_id="$myId"',
        perPage: 1,
      );
      if (res.items.isEmpty) {
        await _pb.collection('message_receipts').create(body: {
          'message_id':     serverId,
          'conversation_id': convId,
          'recipient_id':   myId,
          'delivered_at':   DateTime.now().toIso8601String(),
        });
      } else if (res.items.first.getStringValue('delivered_at').isEmpty) {
        await _pb.collection('message_receipts').update(
          res.items.first.id,
          body: {'delivered_at': DateTime.now().toIso8601String()},
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
      for (final m in members) {
        if (m.userId == myId) continue;
        try {
          final existing = await _pb.collection('message_receipts').getList(
            filter: 'message_id="$serverId"&&recipient_id="${m.userId}"',
            perPage: 1,
          );
          if (existing.items.isEmpty) {
            await _pb.collection('message_receipts').create(body: {
              'message_id':     serverId,
              'conversation_id': convId,
              'recipient_id':   m.userId,
            });
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[Receipt] create: $e');
    }
  }

  Future<List<int>> _getConvKey(String convId, String myId) async {
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
        await db.conversationsDao.upsertConversation(
          ConversationsTableCompanion.insert(
            id:          conv.id,
            type:        conv.getStringValue('type'),
            name:        Value(conv.getStringValue('name').isEmpty
                ? null : conv.getStringValue('name')),
            createdById: conv.getStringValue('created_by'),
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
    final convs = <Conversation>[];
    for (final r in rows) {
      final other = await _getOtherUser(r.id, myId);
      convs.add(_convDataToEntity(r, other));
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
      ConversationsTableData r, User? otherUser) =>
      Conversation(
        id: r.id, type: r.type, name: r.name, iconUrl: r.iconUrl,
        lastMessagePreview: r.lastMessagePreview,
        lastMessageAt: r.lastMessageAt,
        isPinned: r.isPinned, otherUser: otherUser,
      );

  Message _rowToMessage(MessagesTableData r, String myId) => Message(
    localId: r.localId, serverId: r.serverId,
    conversationId: r.conversationId, senderId: r.senderId,
    type: r.type, decryptedBody: r.decryptedBody,
    replyToId: r.replyToId,
    isDeletedForEveryone: r.isDeletedForEveryone,
    isDeletedForMe: r.isDeletedForMe,
    isPinned: r.isPinned, isStarred: r.isStarred,
    status: r.status, createdAt: r.createdAt,
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
    pbClient:   ref.watch(pocketbaseClientProvider),
    db:         ref.read(appDatabaseProvider),
    storage:    ref.read(secureStorageProvider),
    encryption: ref.read(encryptionServiceProvider),
  );
});
