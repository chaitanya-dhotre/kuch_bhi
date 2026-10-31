import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/decrypt/body_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../features/home/screens/add_friend_screen.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/conversation.dart';
import '../../../core/constants/app_strings.dart';
import '../../../domain/entities/friendship.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/chat/screens/chat_screen.dart';
import '../../../features/home/providers/friends_provider.dart';
import '../../../infrastructure/services/group_create_service.dart';
import '../../../services/encryption_service.dart';
import '../../chat/message_offline_policy.dart';
import '../member_key_missing_error.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  // ── Step state ────────────────────────────────────────────────
  bool _onStep2 = false;

  // ── Step 1 ────────────────────────────────────────────────────
  final Set<String> _selectedIds = {};
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Step 2 ────────────────────────────────────────────────────
  final _nameController = TextEditingController();
  File? _iconFile;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── Image picker ──────────────────────────────────────────────
  Future<void> _pickIcon() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      // J4: the picker can outlive the screen — never setState after dispose.
      setState(() => _iconFile = File(picked.path));
    }
  }

  // ── Create group ──────────────────────────────────────────────
  Future<void> _createGroup(List<Friendship> allFriends) async {
    final groupName = _nameController.text.trim();
    if (groupName.isEmpty) {
      setState(() => _error = 'Group name is required.');
      return;
    }

    setState(() {
      _creating = true;
      _error    = null;
    });

    String? createdConversationId;
    var creationCommitted = false;
    try {
      final auth = ref.read(authProvider).valueOrNull;
      if (auth is! AuthAuthenticated) throw Exception('Not authenticated.');

      final myId      = auth.user.id;
      final groupService = ref.read(groupCreateServiceProvider);
      final db        = ref.read(appDatabaseProvider);
      final encryption = ref.read(encryptionServiceProvider);

      final selectedFriends = allFriends
          .where((f) => _selectedIds.contains(f.friend.id))
          .toList();
      final allMemberIds = [myId, ...selectedFriends.map((f) => f.friend.id)];

      // A group without a key for one member is unrecoverable until another
      // rotation happens. Validate every public key before creating any
      // server rows, so a transient/missing key cannot leave an orphan group.
      for (final memberId in allMemberIds) {
        final user = await groupService.getUserRecord(memberId);
        if (user.getStringValue('public_key').isEmpty) {
          throw MemberKeyMissingError(memberId);
        }
      }

      // ── a) Create conversation on PocketBase ──────────────────
      final Map<String, dynamic> convBody = {
        'type':                    'group',
        'name':                    groupName,
        'created_by':              myId,
        'only_admins_can_message': false,
      };

      final conv = await groupService.createConversation(
        convBody: convBody,
        iconFile: _iconFile,
      );

      final convId = conv.id;
      createdConversationId = convId;

      // ── b) Add creator as admin ───────────────────────────────
      final myMemberRecord = await groupService.createMemberRecord({
        'conversation_id': convId,
        'user_id':         myId,
        'role':            'admin',
      });

      // ── c) Add selected friends as members ────────────────────
      final memberRecords = await groupService.addMembers(
        conversationId: convId,
        memberIds: selectedFriends.map((f) => f.friend.id).toList(),
      );

      // Save memberships locally in Drift
      await db.conversationsDao.upsertMember(
        ConversationMembersTableCompanion.insert(
          id:             myMemberRecord.id,
          conversationId: convId,
          userId:         myId,
          role:           const Value('admin'),
          joinedAt:       DateTime.tryParse(
                myMemberRecord.getStringValue('joined_at')) ??
              DateTime.tryParse(myMemberRecord.created) ??
              DateTime.now(),
        ),
      );

      for (final rec in memberRecords) {
        await db.conversationsDao.upsertMember(
          ConversationMembersTableCompanion.insert(
            id:             rec.id,
            conversationId: convId,
            userId:         rec.getStringValue('user_id'),
            role:           const Value('member'),
            joinedAt:       DateTime.tryParse(
                  rec.getStringValue('joined_at')) ??
                DateTime.tryParse(rec.created) ??
                DateTime.now(),
          ),
        );
      }

      // ── d) Generate and distribute group key ──────────────────
      final groupKey  = encryption.generateGroupKey();
      for (final memberId in allMemberIds) {
        String? publicKey;
        try {
          final r = await groupService.getUserRecord(memberId);
          publicKey = r.getStringValue('public_key');
          if (publicKey.isNotEmpty) {
            await db.usersDao.upsertUser(UsersTableCompanion.insert(
              id:          r.id,
              displayName: r.getStringValue('display_name'),
              username:    r.getStringValue('username'),
              email:       Value(r.getStringValue('email')),
              avatarUrl:   Value(r.getStringValue('avatar').isEmpty ? null : '${groupService.baseUrl}/api/files/users/${r.id}/${r.getStringValue('avatar')}'),
              friendCode:  r.getStringValue('friend_code'),
              publicKey:   Value(publicKey),
              createdAt:   DateTime.tryParse(r.created) ?? DateTime.now(),
              updatedAt:   DateTime.now(),
            ));
          }
        } catch (e) {
          debugPrint('[Group] Could not fetch public key for $memberId: $e');
        }

        if (publicKey == null || publicKey.isEmpty) {
          throw MemberKeyMissingError(memberId);
        }

        final encryptedKey = await encryption.encryptGroupKeyForMember(
          groupKey,
          publicKey,
          convId,
        );

        await groupService.createGroupKey({
          'conversation_id':      convId,
          'user_id':              memberId,
          'encrypted_key':        encryptedKey,
          'encrypted_by_user_id': myId,
          'key_version':          1,
        });
      }

      // Cache own group key. C: saveGroupKey = disk + process-memory
      // write-through (raw storage.write would leave the RAM map stale).
      await encryption.saveGroupKey(convId, groupKey);
      await encryption.saveGroupKey(convId, groupKey, version: 1);

      // ── e) Build icon URL ─────────────────────────────────────
      final iconField = conv.getStringValue('icon');
      final iconUrl   = iconField.isEmpty
          ? null
          : '${groupService.baseUrl}/api/files/conversations/$convId/$iconField';

      // ── f) Sync conversation to Drift ─────────────────────────
      final now = DateTime.now();
      await db.conversationsDao.upsertConversation(
        ConversationsTableCompanion.insert(
          id:          convId,
          type:        'group',
          name:        Value(groupName),
          iconUrl:     Value(iconUrl),
          createdById: myId,
          onlyAdminsCanMessage: Value(false),
          createdAt:   DateTime.tryParse(conv.created) ?? now,
          updatedAt:   now,
        ),
      );

      await db.conversationsDao.upsertMember(
        ConversationMembersTableCompanion.insert(
          id:             myMemberRecord.id,
          conversationId: convId,
          userId:         myId,
          role:           Value('admin'),
          joinedAt:       DateTime.tryParse(
                myMemberRecord.getStringValue('joined_at')) ??
              DateTime.tryParse(myMemberRecord.created) ??
              now,
        ),
      );

      for (int i = 0; i < selectedFriends.length; i++) {
        final f   = selectedFriends[i];
        final rec = memberRecords[i];
        await db.conversationsDao.upsertMember(
          ConversationMembersTableCompanion.insert(
            id:             rec.id,
            conversationId: convId,
            userId:         f.friend.id,
            role:           Value('member'),
            joinedAt:       DateTime.tryParse(
                  rec.getStringValue('joined_at')) ??
                DateTime.tryParse(rec.created) ??
                now,
          ),
        );
      }

      // ── f) Build Conversation entity and navigate to ChatScreen ─────────────────────────────
      final groupConv = Conversation(
        id:        convId,
        type:      'group',
        name:      groupName,
        iconUrl:   iconUrl,
        otherUser: null,
      );

      // Drop a "Group created by <my name>" bubble at the head of the
      // timeline so members see narrative context when they open the chat.
      // (Encryption needs the group_key_STORED_ABOVE; local cache row is
      // already visible immediately on this device via the SSE round-trip.)
      try {
        final myUser = await groupService.getUserRecord(myId);
        final myName = myUser.getStringValue('display_name').isNotEmpty
            ? myUser.getStringValue('display_name')
            : (myUser.getStringValue('username').isNotEmpty
                ? '@${myUser.getStringValue('username')}'
                : 'You');
        final sysRes = await encryption.encryptMessage(
          '$myName created the group "$groupName"',
          groupKey,
        );
        final sysRec = await groupService.createMessage({
          'conversation_id':          convId,
          'sender_id':                myId,
          'type':                     'system',
          'encrypted_body':           sysRes.ciphertext,
          'iv':                       sysRes.iv,
          'is_pinned':                false,
          'is_deleted_for_everyone':  false,
        });
        // `created` is auto-managed by PocketBase v0.37.5 — don't override.
        await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
          localId:           'sys_${sysRec.id}',
          serverId:          Value(sysRec.id),
          conversationId:    convId,
          senderId:          myId,
          type:              'system',
          encryptedBody:     sysRes.ciphertext,
          iv:                sysRes.iv,
          status:            const Value('sent'),
          createdAt:         DateTime.tryParse(sysRec.created) ??
              DateTime.now(),
          updatedAt:         DateTime.now(),
        ));
        // T9: system narrative is a body — session cache (spec §3: the
        // dropped column never carries it; ciphertext is on the row too).
        bodyCache.put('sys_${sysRec.id}',
            '$myName created the group "$groupName"');
      } catch (e) {
        debugPrint('[Group] create-group system message emit failed: $e');
      }

      if (context.mounted) {
        creationCommitted = true;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => ChatScreen(conversation: groupConv)),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      if (createdConversationId != null && !creationCommitted) {
        // Conversation/member/key creation is multi-request on PocketBase.
        // Roll back the server aggregate on any pre-navigation failure; the
        // live creator-only delete rule permits this and cascades children.
        try {
          await ref.read(groupCreateServiceProvider)
              .deleteConversation(createdConversationId!);
        } catch (rollbackError) {
          debugPrint('[Group] server rollback failed: $rollbackError');
        }
        try {
          await ref.read(appDatabaseProvider).conversationsDao
              .deleteConversation(createdConversationId!);
        } catch (rollbackError) {
          debugPrint('[Group] local rollback failed: $rollbackError');
        }
      }
      // J3/J4: user-visible copy never carries an exception or a raw id.
      // The missing-key case names the FRIEND (mapped from the typed error);
      // everything else gets the stable connection copy. Both setStates are
      // `mounted`-guarded (J4).
      debugPrint('[Group] create error: $e');
      if (mounted) {
        setState(() {
          _error = e is MemberKeyMissingError
              ? '${_memberDisplayName(e.memberId, allFriends)} can\'t be '
                  'added yet. They need to open Kuch Bhi once to set up '
                  'encryption.'
              : "Couldn't create the group. Check your connection and "
                  'try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  /// Maps the id on a [MemberKeyMissingError] back to a NAME (J3). A raw id
  /// must never reach user-visible text, so every path falls back to a name
  /// or a placeholder — never [memberId].
  String _memberDisplayName(String memberId, List<Friendship> friends) {
    for (final f in friends) {
      if (f.friend.id == memberId) {
        final name = f.friend.displayName.trim();
        if (name.isNotEmpty) return name;
        final handle = f.friend.username.trim();
        if (handle.isNotEmpty) return '@$handle';
        return 'Unknown';
      }
    }
    final auth = ref.read(authProvider).valueOrNull;
    if (auth is AuthAuthenticated && auth.user.id == memberId) {
      final name = auth.user.displayName.trim();
      if (name.isNotEmpty) return name;
      return 'You';
    }
    return 'Unknown';
  }

  void _openAddFriend() => showAddFriendSheet(context, ref);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final friendsAsync = ref.watch(friendshipsProvider);
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    // J1: system back on step 2 returns to step 1 with the selection kept.
    // J2: while creating, back is blocked — a pop mid-flight would orphan
    // the server rows the rollback is still deleting.
    return PopScope(
      canPop: !_onStep2 && !_creating,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _creating) return;
        if (_onStep2) setState(() => _onStep2 = false);
      },
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: _appBar(t),
        body: Column(
          children: [
            _OfflineStrip(visible: !online),
            Expanded(
              child: _onStep2
                  ? _buildStep2(context, friendsAsync, online)
                  : _buildStep1(context, friendsAsync, online),
            ),
          ],
        ),
      ),
    );
  }

  /// One app bar for both steps (A1/J5): the title is **New Group**.
  PreferredSizeWidget _appBar(ColorTokens t) {
    return AppBar(
      backgroundColor: t.bg,
      surfaceTintColor: t.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: _onStep2
          ? IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed:
                  _creating ? null : () => setState(() => _onStep2 = false),
              icon: Icon(Icons.arrow_back, color: t.ink),
            )
          : null,
      title: Semantics(
        header: true,
        child: Text(
          'New Group',
          style: TextStyle(
            color: t.ink,
            fontSize: 20,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      actions: [
        if (!_onStep2)
          SizedBox(
            height: 48,
            child: AppButton(
              variant: AppButtonVariant.text,
              onPressed: _selectedIds.isEmpty
                  ? null
                  : () => setState(() => _onStep2 = true),
              child: const Text('Next'),
            ),
          ),
      ],
    );
  }

  // ── Step 1: member selection ──────────────────────────────────

  Widget _buildStep1(
    BuildContext context,
    AsyncValue<List<Friendship>> friendsAsync,
    bool online,
  ) {
    final t = context.t;

    // H1: loading = R11 rows with the app bar present (it lives in `build`).
    if (friendsAsync.isLoading && friendsAsync.valueOrNull == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          for (var i = 0; i < 6; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Skeleton(width: 24, height: 24, radius: 999),
                  SizedBox(width: 12),
                  Skeleton(width: 40, height: 40, radius: 999),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Skeleton(width: 140, height: 14, radius: 7),
                        SizedBox(height: 8),
                        Skeleton(width: 90, height: 11, radius: 6),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    // H1: R7 error state — no `$e`, and the app bar stays reachable.
    if (friendsAsync.hasError && friendsAsync.valueOrNull == null) {
      return EmptyState(
        title: kLoadFriendsFailedCopy,
        subtitle: kConnectionRetryCopy,
        action: AppButton(
          onPressed: () => ref.invalidate(friendshipsProvider),
          child: const Text('Retry'),
        ),
      );
    }

    final friends = friendsAsync.valueOrNull ?? const <Friendship>[];
    if (friends.isEmpty) {
      return EmptyState(
        title: 'No friends yet',
        subtitle: 'Add a friend to start a group.',
        action: AppButton(
          onPressed: _openAddFriend,
          child: const Text(kAddFriendCtaLabel),
        ),
      );
    }

    final query = _searchQuery.trim().toLowerCase();
    final visible = query.isEmpty
        ? friends
        : friends
            .where((f) =>
                f.displayName.toLowerCase().contains(query) ||
                f.friend.username.toLowerCase().contains(query))
            .toList();

    return Column(
      children: [
        if (_selectedIds.isNotEmpty)
          _SelectedChips(
            friends: friends,
            selectedIds: _selectedIds,
            onRemove: (id) => setState(() => _selectedIds.remove(id)),
          ),
        if (friends.length > 8)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchField(
              controller: _searchController,
              hint: 'Search friends',
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? EmptyState(
                  withMascot: false,
                  title: 'No friends match',
                  subtitle: 'Try a different name.',
                )
              : ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (_, i) {
                    final f = visible[i];
                    final selected = _selectedIds.contains(f.friend.id);
                    final name = _friendName(f);
                    return Semantics(
                      container: true,
                      button: true,
                      checked: selected,
                      label: name,
                      excludeSemantics: true,
                      onTap: () => _toggleFriend(f.friend.id),
                      child: InkWell(
                        onTap: () => _toggleFriend(f.friend.id),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                _checkCircle(selected),
                                const SizedBox(width: 12),
                                AppAvatar(
                                  url: f.friend.avatarUrl,
                                  initials:
                                      _initial(name, fallback: '?'),
                                  radius: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 16,
                                          height: 1.375,
                                          fontWeight: FontWeight.w600,
                                          color: t.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '@${f.friend.username.trim()}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.38,
                                          color: t.inkSoft,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _toggleFriend(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  String _friendName(Friendship f) {
    final name = f.friend.displayName.trim();
    if (name.isNotEmpty) return name;
    final handle = f.friend.username.trim();
    if (handle.isNotEmpty) return '@$handle';
    return 'Unknown';
  }

  /// The round accent check (H2) — accent is a FILL, never text (C4).
  Widget _checkCircle(bool selected) {
    final t = context.t;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? t.accent : null,
        border: Border.all(
          color: selected ? t.accent : t.line,
          width: 1.5,
        ),
      ),
      child: selected ? Icon(Icons.check, size: 16, color: t.onAccent) : null,
    );
  }

  /// First letter WITHOUT a range-taking call (grep gate) — never throws on
  /// an empty name (H2).
  String _initial(String value, {required String fallback}) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed[0].toUpperCase();
  }

  // ── Step 2: group info ─────────────────────────────────────────

  Widget _buildStep2(
    BuildContext context,
    AsyncValue<List<Friendship>> friendsAsync,
    bool online,
  ) {
    final t = context.t;
    final friends = friendsAsync.valueOrNull ?? const <Friendship>[];
    final name = _nameController.text.trim();
    // Empty name → "G" (J5), never a RangeError.
    final letter = _initial(name, fallback: 'G');

    final photo = _iconFile == null
        ? AppAvatar(initials: letter, radius: 48, accentSoft: true)
        : CircleAvatar(
            radius: 48,
            backgroundColor: t.accentSoft,
            backgroundImage: FileImage(_iconFile!),
          );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // J5: R1 radius 48 + camera badge, 96dp disc is the hit target.
          Semantics(
            container: true,
            button: !_creating,
            label: 'Add group photo',
            excludeSemantics: true,
            onTap: _creating ? null : _pickIcon,
            child: GestureDetector(
              onTap: _creating ? null : _pickIcon,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  photo,
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: t.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.bg, width: 2),
                      ),
                      child: Icon(
                        Icons.camera_alt_outlined,
                        color: t.onAccent,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // J5: radiusMd 16, ONE counter (maxLength draws it), no prefixIcon.
          TextField(
            controller: _nameController,
            maxLength: 50,
            readOnly: _creating,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontSize: 15, color: t.ink),
            decoration: InputDecoration(
              labelText: 'Group name',
              hintText: 'Enter group name…',
              labelStyle: TextStyle(fontSize: 13, color: t.inkSoft),
              hintStyle: TextStyle(fontSize: 15, color: t.inkFaint),
              counterStyle: TextStyle(fontSize: 12, color: t.inkSoft),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(WarmPopTokens.radiusMd),
                borderSide: BorderSide(color: t.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(WarmPopTokens.radiusMd),
                borderSide: BorderSide(color: t.accent, width: 1.5),
              ),
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(WarmPopTokens.radiusMd),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Text(
            '${_selectedIds.length} member'
            '${_selectedIds.length == 1 ? '' : 's'} selected',
            style: TextStyle(fontSize: 13, height: 1.38, color: t.inkSoft),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius:
                    BorderRadius.circular(WarmPopTokens.radiusSm),
                border: Border(left: BorderSide(color: t.error, width: 3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 18, color: t.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: t.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          // I2: offline dims Create exactly once, with one hint below.
          Opacity(
            opacity: online ? 1 : .38,
            child: AppButton(
              onPressed: (_creating || name.isEmpty || !online)
                  ? null
                  : () => _createGroup(friends),
              busy: _creating,
              expanded: true,
              child: Text(_creating ? 'Creating…' : 'Create Group'),
            ),
          ),
          if (!online)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  kOfflineActionHint,
                  style: TextStyle(fontSize: 12, color: t.inkSoft),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Selected member chips ─────────────────────────────────────────

class _SelectedChips extends StatelessWidget {
  const _SelectedChips({
    required this.friends,
    required this.selectedIds,
    required this.onRemove,
  });

  final List<Friendship> friends;
  final Set<String>      selectedIds;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final selected =
        friends.where((f) => selectedIds.contains(f.friend.id)).toList();

    // H3/H5: a plain strip on bg with a bottom line, scrolling horizontally
    // past one row (Material Chip + surfaceContainerHighest are gone).
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < selected.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _chip(context, selected[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, Friendship f) {
    final t = context.t;
    final name = _label(f);
    final initials = _letter(name);
    // K2: the 48dp outer target owns the tap; the 36h pill is decorative.
    return SizedBox(
      height: 48,
      child: Semantics(
        container: true,
        button: true,
        label: 'Remove $name',
        excludeSemantics: true,
        onTap: () => onRemove(f.friend.id),
        child: InkWell(
          onTap: () => onRemove(f.friend.id),
          child: Center(
            child: IgnorePointer(
              child: AppChip(
                selected: true,
                onTap: () {},
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppAvatar(
                      url: f.friend.avatarUrl,
                      initials: initials,
                      radius: 14,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: t.ink),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.close, size: 16, color: t.inkSoft),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _label(Friendship f) {
    final name = f.friend.displayName.trim();
    if (name.isNotEmpty) return name;
    final handle = f.friend.username.trim();
    if (handle.isNotEmpty) return '@$handle';
    return 'Unknown';
  }

  /// First letter WITHOUT a range-taking call (grep gate) — never throws on
  /// an empty name (H3).
  String _letter(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }
}


class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : WarmPopTokens.motionBase,
      child: visible
          ? Semantics(
              key: const ValueKey('create-group-offline-strip'),
              container: true,
              label: kOfflineActionsCopy,
              child: Container(
                width: double.infinity,
                color: t.accentSoft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 18, color: t.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        kOfflineActionsCopy,
                        style: TextStyle(fontSize: 13, color: t.ink),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('create-group-online-space')),
    );
  }
}
