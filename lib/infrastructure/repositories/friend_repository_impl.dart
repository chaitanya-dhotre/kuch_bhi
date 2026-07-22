import 'package:drift/drift.dart' show Value;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:uuid/uuid.dart';

import '../../data/local/database/tables/app_settings_table.dart';
import '../../core/network/pocketbase_client.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/friend_requests_table.dart';
import '../../data/local/database/tables/friendships_table.dart';
import '../../data/local/database/tables/conversations_table.dart';
import '../../data/local/database/tables/conversation_members_table.dart';
import '../../data/local/database/tables/users_table.dart';
import '../../data/local/secure_storage/secure_storage_service.dart';
import '../../domain/entities/friend_request.dart';
import '../../domain/entities/friendship.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/friend_repository.dart';

class FriendRepositoryImpl implements FriendRepository {
  FriendRepositoryImpl({
    required this.pbClient,
    required this.db,
    required this.storage,
  });

  final PocketBaseClient pbClient;
  final AppDatabase db;
  final SecureStorageService storage;

  PocketBase get _pb => pbClient.pb;
  static const _uuid = Uuid();

  // ── Find user ──────────────────────────────────────────────────

  @override
  Future<User?> findUserByCode(String code) async {
    try {
      final record = await _pb
          .collection('users')
          .getFirstListItem('friend_code="${code.toUpperCase()}"');
      return _recordToUser(record);
    } on ClientException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  // ── Send request ───────────────────────────────────────────────

  @override
  Future<FriendRequest> sendRequest(String toUserId) async {
    final currentUserId = await db.settingsDao
    .getSetting(AppSettingsKeys.currentUserId);
    if (currentUserId == null) throw Exception('Not authenticated');

    final record = await _pb.collection('friend_requests').create(
      body: {
        'from_user': currentUserId,
        'to_user':   toUserId,
        'status':    'pending',
      },
      expand: 'from_user,to_user',
    );

    return _recordToFriendRequest(record);
  }

  // ── Accept / decline ───────────────────────────────────────────

  @override
  Future<void> acceptRequest(String requestId) async {
    final currentUserId = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId);
    if (currentUserId == null) throw Exception('Not authenticated');

    final updated = await _pb.collection('friend_requests').update(
      requestId,
      body: {'status': 'accepted'},
      expand: 'from_user,to_user',
    );

    // Read IDs from record fields — stable and always present.
    // Never use expand for IDs since expand can be absent on some responses.
    final fromUserId = updated.getStringValue('from_user');
    final toUserId = updated.getStringValue('to_user');

    if (fromUserId.isEmpty || toUserId.isEmpty) {
      throw Exception('Invalid friend request: missing from_user/to_user');
    }

    if (toUserId != currentUserId) {
      throw Exception('Current user is not the receiver of this request');
    }

    // Prevent duplicate friendships (same pair accepted twice).
    final pairFilter =
        '(user_a="$fromUserId"&&user_b="$toUserId")||'
        '(user_a="$toUserId"&&user_b="$fromUserId")';

    try {
      await _pb.collection('friendships').getFirstListItem(pairFilter);
      // Already exists — skip creation.
    } on ClientException catch (e) {
      if (e.statusCode != 404) rethrow;

      // PocketBase createRule for friendships is @request.auth.id = user_a,
      // and this action is performed by the receiver (current user).
      await _pb.collection('friendships').create(body: {
        'user_a': currentUserId,
        'user_b': fromUserId,
      });
    }

    // Cache locally.
    final request = _recordToFriendRequest(updated);
    await _cacheRequestLocally(request, 'accepted');

    final otherUser = request.fromUser.id == currentUserId
        ? request.toUser
        : request.fromUser;
    await _cacheUserLocally(otherUser);

    final conversation = await _findOrCreateDirectConversation(
      currentUserId,
      fromUserId,
    );
    await _cacheConversationLocally(conversation, currentUserId, fromUserId);
  }

  @override
  Future<void> declineRequest(String requestId) async {
    await _pb.collection('friend_requests').update(
      requestId,
      body: {'status': 'declined'},
    );
    await db.friendsDao.updateRequestStatus(requestId, 'declined');
  }

  // ── Get requests ───────────────────────────────────────────────

  @override
  Future<List<FriendRequest>> getIncomingRequests() async {
    final currentUserId = await db.settingsDao
    .getSetting(AppSettingsKeys.currentUserId);
    if (currentUserId == null) return [];

    // getFullList — plain getList caps at 30 and silently drops the rest.
    final items = await _pb.collection('friend_requests').getFullList(
      filter: 'to_user="$currentUserId"&&status="pending"',
      expand: 'from_user,to_user',
      sort:   '-created',
      batch:  200,
    );

    final requests = items.map(_recordToFriendRequest).toList();

    // Cache locally.
    for (final req in requests) {
      await _cacheRequestLocally(req, 'pending');
      await _cacheUserLocally(req.fromUser);
    }

    return requests;
  }

  @override
  Stream<List<FriendRequest>> watchIncomingRequests() {
    final controller = StreamController<List<FriendRequest>>.broadcast();

    getIncomingRequests().then((initial) {
      if (!controller.isClosed) controller.add(initial);
    });

    _pb.collection('friend_requests').subscribe('*', (event) async {
      if (event.record == null) return;
      final currentUserId = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId);
      if (currentUserId == null) return;

      // Only care about requests directed at the current user.
      final toUser = event.record!.getStringValue('to_user');
      if (toUser != currentUserId) return;

      final updated = await getIncomingRequests();
      if (!controller.isClosed) controller.add(updated);
    });

    return controller.stream;
  }

  // ── Get friendships ────────────────────────────────────────────

  @override
  Future<List<Friendship>> getFriendships() async {
    final currentUserId = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId);
    if (currentUserId == null) return [];

    // getFullList — plain getList caps at 30 and silently drops friends.
    final items = await _pb.collection('friendships').getFullList(
      filter: 'user_a="$currentUserId"||user_b="$currentUserId"',
      expand: 'user_a,user_b',
      sort:   '-created',
      batch:  200,
    );

    final friendships = <Friendship>[];

    for (final record in items) {
      final friendship = await _recordToFriendship(record, currentUserId);
      if (friendship != null) friendships.add(friendship);
    }

    return friendships;
  }

  @override
  Stream<List<Friendship>> watchFriendships() {
    final controller = StreamController<List<Friendship>>.broadcast();

    getFriendships().then((initial) {
      if (!controller.isClosed) controller.add(initial);
    });

    _pb.collection('friendships').subscribe('*', (event) async {
      final updated = await getFriendships();
      if (!controller.isClosed) controller.add(updated);
    });

    return controller.stream;
  }

  // ── Nickname ───────────────────────────────────────────────────

  @override
  Future<void> setNickname(String friendshipId, String? nickname) =>
      db.friendsDao.setCustomNickname(friendshipId, nickname);

  // ── Block ──────────────────────────────────────────────────────

  @override
  Future<void> blockUser(String userId) async {
    final currentUserId = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId);
    if (currentUserId == null) return;

    await _pb.collection('blocked_users').create(body: {
      'blocker_id': currentUserId,
      'blocked_id': userId,
    });
  }

  @override
  Future<void> unblockUser(String userId) async {
    final currentUserId = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId);
    if (currentUserId == null) return;

    try {
      final record = await _pb
          .collection('blocked_users')
          .getFirstListItem('blocker_id="$currentUserId"&&blocked_id="$userId"');
      await _pb.collection('blocked_users').delete(record.id);
    } on ClientException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
  }

  @override
  Future<List<String>> getBlockedUserIds() async {
    final currentUserId = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId);
    if (currentUserId == null) return [];

    final items = await _pb.collection('blocked_users').getFullList(
      filter: 'blocker_id="$currentUserId"',
      batch: 200,
    );

    return items.map((r) => r.getStringValue('blocked_id')).toList();
  }

  // ── Private helpers ────────────────────────────────────────────

  User _recordToUser(RecordModel record) {
    final avatar = record.getStringValue('avatar');
    final avatarUrl = avatar.isEmpty
        ? null
        : '${_pb.baseUrl}/api/files/users/${record.id}/$avatar';

    return User(
      id:          record.id,
      displayName: record.getStringValue('display_name'),
      username:    record.getStringValue('username'),
      email:       record.getStringValue('email'),
      friendCode:  record.getStringValue('friend_code'),
      avatarUrl:   avatarUrl,
      about:       record.getStringValue('about').isEmpty
                       ? null
                       : record.getStringValue('about'),
      publicKey:   record.getStringValue('public_key').isEmpty
                       ? null
                       : record.getStringValue('public_key'),
      isOnline:    record.getBoolValue('is_online'),
      createdAt:   DateTime.tryParse(record.created) ?? DateTime.now(),
    );
  }

  FriendRequest _recordToFriendRequest(RecordModel record) {
    final expandedFrom = record.expand['from_user'];
    final expandedTo   = record.expand['to_user'];

    final fromUser = expandedFrom != null && expandedFrom.isNotEmpty
        ? _recordToUser(expandedFrom[0])
        : User(
            id: record.getStringValue('from_user'),
            displayName: 'Unknown',
            username: '',
            email: '',
            friendCode: '',
            createdAt: DateTime.now(),
          );

    final toUser = expandedTo != null && expandedTo.isNotEmpty
        ? _recordToUser(expandedTo[0])
        : User(
            id: record.getStringValue('to_user'),
            displayName: 'Unknown',
            username: '',
            email: '',
            friendCode: '',
            createdAt: DateTime.now(),
          );

    return FriendRequest(
      id:        record.id,
      fromUser:  fromUser,
      toUser:    toUser,
      status:    record.getStringValue('status'),
      createdAt: DateTime.tryParse(record.created) ?? DateTime.now(),
    );
  }

  Future<Friendship?> _recordToFriendship(
    RecordModel record,
    String currentUserId,
  ) async {
    final expandedA = record.expand['user_a'];
    final expandedB = record.expand['user_b'];

    final userA = expandedA != null && expandedA.isNotEmpty
        ? _recordToUser(expandedA[0])
        : null;
    final userB = expandedB != null && expandedB.isNotEmpty
        ? _recordToUser(expandedB[0])
        : null;

    // The friend is whichever user is NOT the current user.
    final friend = userA?.id == currentUserId ? userB : userA;
    if (friend == null) return null;

    // Check for local nickname.
    final localFriendship =
        await db.friendsDao.getAllFriendships().then(
          (list) => list
              .where((f) => f.id == record.id)
              .firstOrNull,
        );

    // Cache the friend user locally.
    await _cacheUserLocally(friend);

    return Friendship(
      id:             record.id,
      friend:         friend,
      createdAt:      DateTime.tryParse(record.created) ?? DateTime.now(),
      customNickname: localFriendship?.customNickname,
    );
  }

  Future<void> _cacheUserLocally(User user) async {
    await db.usersDao.upsertUser(UsersTableCompanion.insert(
      id:          user.id,
      displayName: user.displayName,
      username:    user.username,
      email:       Value(user.email),
      avatarUrl:   Value(user.avatarUrl),
      about:       Value(user.about),
      friendCode:  user.friendCode,
      publicKey:   Value(user.publicKey),
      isOnline:    Value(user.isOnline),
      createdAt:   user.createdAt,
      updatedAt:   DateTime.now(),
    ));
  }

  Future<void> _cacheRequestLocally(
      FriendRequest req, String status) async {
    await db.friendsDao.upsertFriendRequest(
      FriendRequestsTableCompanion.insert(
        id:         req.id,
        fromUserId: req.fromUser.id,
        toUserId:   req.toUser.id,
        status:     Value(status),
        createdAt:  req.createdAt,
      ),
    );
  }

  Future<RecordModel> _findOrCreateDirectConversation(
      String currentUserId, String otherUserId) async {
    final existing = await _findDirectConversationOnServer(
      currentUserId,
      otherUserId,
    );
    if (existing != null) return existing;

    final conv = await _pb.collection('conversations').create(body: {
      'type': 'direct',
      'created_by': currentUserId,
    });
    await _pb.collection('conversation_members').create(body: {
      'conversation_id': conv.id,
      'user_id': currentUserId,
      'role': 'admin',
    });
    await _pb.collection('conversation_members').create(body: {
      'conversation_id': conv.id,
      'user_id': otherUserId,
      'role': 'member',
    });
    return conv;
  }

  Future<RecordModel?> _findDirectConversationOnServer(
      String userA,
      String userB,
  ) async {
    try {
      final aMembers = await _pb.collection('conversation_members').getList(
        filter: 'user_id="$userA"',
        expand: 'conversation_id',
        perPage: 200,
      );
      final bMembers = await _pb.collection('conversation_members').getList(
        filter: 'user_id="$userB"',
        expand: 'conversation_id',
        perPage: 200,
      );

      final bConversationIds = bMembers.items
          .map((r) => r.getStringValue('conversation_id'))
          .toSet();

      RecordModel? bestConversation;
      DateTime? bestLastMessageAt;
      DateTime? bestCreatedAt;

      for (final member in aMembers.items) {
        final conversationId = member.getStringValue('conversation_id');
        if (!bConversationIds.contains(conversationId)) continue;
        final conv = member.expand['conversation_id']?.firstOrNull ??
            await _pb.collection('conversations').getOne(conversationId);

        final candidateLastMessageAt = DateTime.tryParse(
          conv.getStringValue('last_message_at'),
        );
        final candidateCreatedAt = DateTime.tryParse(conv.created)
            ?? DateTime.now();

        final shouldReplace = bestConversation == null ||
            (candidateLastMessageAt != null &&
                (bestLastMessageAt == null ||
                    candidateLastMessageAt.isAfter(bestLastMessageAt))) ||
            (candidateLastMessageAt == bestLastMessageAt &&
                candidateCreatedAt.isAfter(bestCreatedAt ??
                    DateTime.fromMillisecondsSinceEpoch(0)));

        if (shouldReplace) {
          bestConversation = conv;
          bestLastMessageAt = candidateLastMessageAt;
          bestCreatedAt = candidateCreatedAt;
        }
      }

      if (bestConversation != null) return bestConversation;
    } catch (e) {
      debugPrint('[Conv] find direct conversation: $e');
    }
    return null;
  }

  Future<void> _cacheConversationLocally(
      RecordModel conv,
      String currentUserId,
      String otherUserId,
  ) async {
    await db.conversationsDao.upsertConversation(
      ConversationsTableCompanion.insert(
        id: conv.id,
        type: conv.getStringValue('type').isEmpty
            ? 'direct'
            : conv.getStringValue('type'),
        createdById: conv.getStringValue('created_by').isEmpty
            ? currentUserId
            : conv.getStringValue('created_by'),
        createdAt: DateTime.tryParse(conv.created) ?? DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final members = await _pb.collection('conversation_members').getList(
      filter: 'conversation_id="${conv.id}"',
      expand: 'user_id',
      perPage: 200,
    );

    for (final member in members.items) {
      await db.conversationsDao.upsertMember(
        ConversationMembersTableCompanion.insert(
          id: member.id,
          conversationId: conv.id,
          userId: member.getStringValue('user_id'),
          role: Value(member.getStringValue('role').isEmpty
              ? 'member'
              : member.getStringValue('role')),
          joinedAt: DateTime.tryParse(member.getStringValue('joined_at'))
              ?? DateTime.now(),
        ),
      );

      final expandedUser = member.expand['user_id']?.firstOrNull;
      if (expandedUser != null) {
        await _cacheUserLocally(_recordToUser(expandedUser));
      }
    }

    final selfMemberExists = members.items.any(
      (member) => member.getStringValue('user_id') == currentUserId,
    );
    final otherMemberExists = members.items.any(
      (member) => member.getStringValue('user_id') == otherUserId,
    );

    if (!selfMemberExists) {
      await db.conversationsDao.upsertMember(
        ConversationMembersTableCompanion.insert(
          id: _uuid.v4(),
          conversationId: conv.id,
          userId: currentUserId,
          joinedAt: DateTime.now(),
        ),
      );
    }
    if (!otherMemberExists) {
      await db.conversationsDao.upsertMember(
        ConversationMembersTableCompanion.insert(
          id: _uuid.v4(),
          conversationId: conv.id,
          userId: otherUserId,
          joinedAt: DateTime.now(),
        ),
      );
    }
  }
}

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  return FriendRepositoryImpl(
    pbClient: ref.watch(pocketbaseClientProvider),
    db:       ref.read(appDatabaseProvider),
    storage:  ref.read(secureStorageProvider),
  );
});
