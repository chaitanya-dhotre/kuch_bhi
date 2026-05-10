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
import '../../data/local/secure_storage/secure_storage_service.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/message_repository.dart';
import '../../services/encryption_service.dart';

class MessageRepositoryImpl implements MessageRepository {
  MessageRepositoryImpl({
    required this.pbClient,
    required this.db,
    required this.storage,
    required this.encryption,
  });

  final PocketBaseClient     pbClient;
  final AppDatabase          db;
  final SecureStorageService storage;
  final EncryptionService    encryption;

  PocketBase get _pb => pbClient.pb;
  static const _uuid = Uuid();

  // ── Get or create direct conversation ─────────────────────────

  @override
  Future<Conversation> getOrCreateDirectConversation(
    String otherUserId,
  ) async {
    final myId = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId) ?? '';

    final existingId = await db.conversationsDao
        .findDirectConversationId(myId, otherUserId);

    if (existingId != null) {
      final conv = await db.conversationsDao.getConversationById(existingId);
      if (conv != null) return _convDataToEntity(conv, myId, await _getOtherUser(existingId, myId));
    }

    return _createDirectConversation(myId, otherUserId);
  }

  Future<Conversation> _createDirectConversation(
    String myId,
    String otherUserId,
  ) async {
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

  // ── Watch conversations ────────────────────────────────────────

  @override
  Stream<List<Conversation>> watchConversations() {
    final ctrl = StreamController<List<Conversation>>.broadcast();
    _emitConversations(ctrl);
    _pb.collection('messages').subscribe('*',    (_) => _emitConversations(ctrl));
    _pb.collection('conversations').subscribe('*', (_) => _emitConversations(ctrl));
    return ctrl.stream;
  }

  Future<void> _emitConversations(
    StreamController<List<Conversation>> ctrl,
  ) async {
    if (ctrl.isClosed) return;
    try {
      final myId = await db.settingsDao
          .getSetting(AppSettingsKeys.currentUserId) ?? '';
      await _syncConversations(myId);
      final rows  = await db.conversationsDao.watchAllConversations().first;
      final convs = <Conversation>[];
      for (final r in rows) {
        final other = await _getOtherUser(r.id, myId);
        convs.add(_convDataToEntity(r, myId, other));
      }
      if (!ctrl.isClosed) ctrl.add(convs);
    } catch (e) { debugPrint('[Msg] emitConversations: $e'); }
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
            id: conv.id, type: conv.getStringValue('type'),
            name: Value(conv.getStringValue('name').isEmpty ? null : conv.getStringValue('name')),
            createdById: conv.getStringValue('created_by'),
            lastMessagePreview: Value(conv.getStringValue('last_message_preview').isEmpty
                ? null : conv.getStringValue('last_message_preview')),
            lastMessageAt: Value(conv.getStringValue('last_message_at').isEmpty
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
        // Cache other members.
        final otherMembers = await _pb.collection('conversation_members').getList(
          filter: 'conversation_id="${conv.id}"&&user_id!="$myId"',
          expand: 'user_id',
        );
        for (final om in otherMembers.items) {
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
    } catch (e) { debugPrint('[Msg] syncConversations: $e'); }
  }

  // ── Watch messages ─────────────────────────────────────────────

  @override
  Stream<List<Message>> watchMessages(String conversationId) {
    final ctrl = StreamController<List<Message>>.broadcast();
    _emitMessages(conversationId, ctrl);
    _pb.collection('messages').subscribe(
      '*', (e) => _handleIncoming(e, conversationId, ctrl),
      filter: 'conversation_id="$conversationId"',
    );
    // Watch receipts to update tick status.
    _pb.collection('message_receipts').subscribe(
      '*', (_) => _emitMessages(conversationId, ctrl),
      filter: 'conversation_id="$conversationId"',
    );
    final connectSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        unawaited(retryPendingMessages());
        unawaited(_emitMessages(conversationId, ctrl));
      }
    });

    ctrl.onCancel = () async {
      await connectSub.cancel();
      _pb.collection('messages').unsubscribe();
      _pb.collection('message_receipts').unsubscribe();
    };

    return ctrl.stream;
  }

  Future<void> _emitMessages(
    String conversationId,
    StreamController<List<Message>> ctrl,
  ) async {
    if (ctrl.isClosed) return;
    final myId = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId) ?? '';

    // Emit local Drift data immediately so the UI has something to render.
    try {
      final localRows = await db.messagesDao.watchMessages(conversationId).first;
      final localMsgs = <Message>[];
      for (final r in localRows) {
        localMsgs.add(await _applyReceiptStatus(_rowToMessage(r, myId), myId));
      }
      if (!ctrl.isClosed) ctrl.add(localMsgs);
    } catch (e) { debugPrint('[Msg] emitMessages: $e'); }

    // Then sync from the server in the background and refresh the stream.
    try {
      await _fetchMessages(conversationId, myId);
      final updatedRows = await db.messagesDao.watchMessages(conversationId).first;
      final updatedMsgs = <Message>[];
      for (final r in updatedRows) {
        updatedMsgs.add(await _applyReceiptStatus(_rowToMessage(r, myId), myId));
      }
      if (!ctrl.isClosed) ctrl.add(updatedMsgs);
    } catch (e) {
      debugPrint('[Msg] server sync error: $e');
    }
  }

  Future<void> _fetchMessages(String convId, String myId) async {
    try {
      final res = await _pb.collection('messages').getList(
        filter: 'conversation_id="$convId"&&is_deleted_for_everyone=false',
        sort: '-created', perPage: 40,
      );
      final key = await _getConvKey(convId, myId);
      for (final r in res.items) await _cacheMsg(r, myId, key);
    } catch (e) { debugPrint('[Msg] fetchMessages: $e'); }
  }

  Future<void> _handleIncoming(
    RecordSubscriptionEvent event,
    String conversationId,
    StreamController<List<Message>> ctrl,
  ) async {
    if (event.record == null) return;
    final r = event.record!;
    if (r.getStringValue('conversation_id') != conversationId) return;
    final myId = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId) ?? '';

    // Skip our own optimistic sends to avoid duplicate inserts.
    if (r.getStringValue('sender_id') == myId) return;

    try {
      final key = await _getConvKey(conversationId, myId);
      await _cacheMsg(r, myId, key);
      await _markDelivered(r.id, conversationId, myId);
      await _emitMessages(conversationId, ctrl);
    } catch (e) { debugPrint('[Msg] handleIncoming: $e'); }
  }

  // ── Send message ───────────────────────────────────────────────

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String plaintext,
    String? replyToLocalId,
    String? replyPreview,
  }) async {
    final myId    = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId) ?? '';
    final localId = _uuid.v4();

    // Optimistic insert.
    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: localId, conversationId: conversationId,
      senderId: myId, type: 'text',
      encryptedBody: '__pending__', iv: '',
      decryptedBody: Value(plaintext),
      replyToId: Value(replyToLocalId), replyPreview: Value(replyPreview),
      status: Value('pending'),
      createdAt: DateTime.now(), updatedAt: DateTime.now(),
    ));

    // Encrypt.
    EncryptResult encrypted;
    try {
      final key = await _getConvKey(conversationId, myId);
      encrypted  = await encryption.encryptMessage(plaintext, key);
    } catch (e) {
      await db.messagesDao.updateMessageStatus(localId, 'failed');
      return;
    }

    // Upload.
    try {
      final record = await _pb.collection('messages').create(body: {
        'conversation_id': conversationId,
        'sender_id':       myId,
        'type':            'text',
        'encrypted_body':  encrypted.ciphertext,
        'iv':              encrypted.iv,
        'reply_to_id':     replyToLocalId ?? '',
        'is_deleted_for_everyone': false,
      });

      await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId: localId, serverId: Value(record.id),
        conversationId: conversationId, senderId: myId, type: 'text',
        encryptedBody: encrypted.ciphertext, iv: encrypted.iv,
        decryptedBody: Value(plaintext), status: Value('sent'),
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      ));

      await db.conversationsDao.updateLastMessage(
        conversationId,
        plaintext.length > 50 ? '${plaintext.substring(0, 50)}…' : plaintext,
        DateTime.now(),
      );

      await _createReceipts(record.id, conversationId, myId);
    } catch (e) {
      debugPrint('[Msg] upload error: $e');
      await db.messagesDao.updateMessageStatus(localId, 'failed');
    }
  }

  // ── Mark read ──────────────────────────────────────────────────

  @override
  Future<void> markConversationRead(String conversationId) async {
    try {
      final myId = await db.settingsDao
          .getSetting(AppSettingsKeys.currentUserId) ?? '';
      final res = await _pb.collection('message_receipts').getList(
        filter: 'conversation_id="$conversationId"&&recipient_id="$myId"&&read_at=""',
      );
      for (final r in res.items) {
        await _pb.collection('message_receipts').update(r.id, body: {
          'read_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) { debugPrint('[Receipt] markRead: $e'); }
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

  @override
  Future<void> retryPendingMessages() async {
    final pending = await db.messagesDao.getPendingMessages();
    for (final msg in pending) {
      if (msg.decryptedBody == null) continue;
      await sendMessage(
        conversationId: msg.conversationId,
        plaintext: msg.decryptedBody!,
      );
    }
  }

  @override
  Future<void> loadMoreMessages(String conversationId, int offset) async {
    try {
      final myId = await db.settingsDao
          .getSetting(AppSettingsKeys.currentUserId) ?? '';
      final res = await _pb.collection('messages').getList(
        filter: 'conversation_id="$conversationId"',
        sort: '-created', page: (offset ~/ 40) + 1, perPage: 40,
      );
      final key = await _getConvKey(conversationId, myId);
      for (final r in res.items) await _cacheMsg(r, myId, key);
    } catch (e) { debugPrint('[Msg] loadMore: $e'); }
  }

  // ── Private helpers ────────────────────────────────────────────

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

  Future<void> _cacheMsg(
    RecordModel r,
    String myId,
    List<int> key,
  ) async {
    final encBody = r.getStringValue('encrypted_body');
    final iv      = r.getStringValue('iv');
    String? decrypted;
    if (encBody.isNotEmpty && iv.isNotEmpty && encBody != '__pending__') {
      decrypted = await encryption.decryptMessage(encBody, iv, key);
    }
    final existing = await db.messagesDao.getMessageByServerId(r.id);
    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: existing?.localId ?? _uuid.v4(),
      serverId: Value(r.id),
      conversationId: r.getStringValue('conversation_id'),
      senderId: r.getStringValue('sender_id'),
      type: r.getStringValue('type'),
      encryptedBody: encBody, iv: iv,
      decryptedBody: Value(decrypted),
      replyToId: Value(r.getStringValue('reply_to_id').isEmpty
          ? null : r.getStringValue('reply_to_id')),
      isDeletedForEveryone: Value(r.getBoolValue('is_deleted_for_everyone')),
      status: Value(r.getStringValue('sender_id') == myId ? 'sent' : 'delivered'),
      createdAt: DateTime.tryParse(r.created) ?? DateTime.now(),
      updatedAt: DateTime.now(),
    ));
  }

  Future<Message> _applyReceiptStatus(Message msg, String myId) async {
    if (msg.senderId != myId) return msg;
    if (msg.serverId == null) return msg;
    try {
      final res = await _pb.collection('message_receipts').getList(
        filter: 'message_id="${msg.serverId}"',
      );
      bool allRead      = res.items.isNotEmpty;
      bool allDelivered = res.items.isNotEmpty;
      for (final r in res.items) {
        if (r.getStringValue('read_at').isEmpty)      allRead      = false;
        if (r.getStringValue('delivered_at').isEmpty) allDelivered = false;
      }
      final status = allRead ? 'read' : allDelivered ? 'delivered' : 'sent';
      await db.messagesDao.updateMessageStatus(msg.localId, status);
      return Message(
        localId: msg.localId, serverId: msg.serverId,
        conversationId: msg.conversationId, senderId: msg.senderId,
        type: msg.type, decryptedBody: msg.decryptedBody,
        replyToId: msg.replyToId, status: status,
        createdAt: msg.createdAt,
      );
    } catch (_) { return msg; }
  }

  Future<void> _markDelivered(
    String serverId, String conversationId, String myId,
  ) async {
    try {
      final res = await _pb.collection('message_receipts').getList(
        filter: 'message_id="$serverId"&&recipient_id="$myId"',
      );
      if (res.items.isEmpty) {
        await _pb.collection('message_receipts').create(body: {
          'message_id': serverId, 'conversation_id': conversationId,
          'recipient_id': myId, 'delivered_at': DateTime.now().toIso8601String(),
        });
      } else if (res.items.first.getStringValue('delivered_at').isEmpty) {
        await _pb.collection('message_receipts').update(
          res.items.first.id,
          body: {'delivered_at': DateTime.now().toIso8601String()},
        );
      }
    } catch (e) { debugPrint('[Receipt] delivered: $e'); }
  }

  Future<void> _createReceipts(
    String serverId, String conversationId, String myId,
  ) async {
    try {
      final members = await db.conversationsDao
          .getMembersForConversation(conversationId);
      for (final m in members) {
        if (m.userId == myId) continue;
        try {
          final existing = await _pb.collection('message_receipts').getList(
            filter: 'message_id="$serverId"&&recipient_id="${m.userId}"',
            perPage: 1,
          );
          if (existing.items.isNotEmpty) continue;

          await _pb.collection('message_receipts').create(body: {
            'message_id': serverId,
            'conversation_id': conversationId,
            'recipient_id': m.userId,
          });
        } catch (e) {
          debugPrint('[Receipt] create for ${m.userId}: $e');
        }
      }
    } catch (e) { debugPrint('[Receipt] create: $e'); }
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
    ConversationsTableData r,
    String myId,
    User? otherUser,
  ) =>
      Conversation(
        id: r.id, type: r.type, name: r.name, iconUrl: r.iconUrl,
        lastMessagePreview: r.lastMessagePreview,
        lastMessageAt: r.lastMessageAt,
        isPinned: r.isPinned, otherUser: otherUser,
      );

  Message _rowToMessage(dynamic r, String myId) => Message(
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
