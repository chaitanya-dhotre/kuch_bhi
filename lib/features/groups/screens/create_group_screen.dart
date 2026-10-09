import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../../core/decrypt/body_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../data/local/database/app_database.dart';
import '../../../data/local/secure_storage/secure_storage_service.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/friendship.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/chat/screens/chat_screen.dart';
import '../../../features/home/providers/friends_provider.dart';
import '../../../infrastructure/services/group_create_service.dart';
import '../../../services/encryption_service.dart';

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

  // ── Step 2 ────────────────────────────────────────────────────
  final _nameController = TextEditingController();
  File? _iconFile;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
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
    if (picked != null) {
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

    try {
      final auth = ref.read(authProvider).valueOrNull;
      if (auth is! AuthAuthenticated) throw Exception('Not authenticated.');

      final myId      = auth.user.id;
      final groupService = ref.read(groupCreateServiceProvider);
      final db        = ref.read(appDatabaseProvider);
      final encryption = ref.read(encryptionServiceProvider);
      final storage   = ref.read(secureStorageProvider);

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

      // ── b) Add creator as admin ───────────────────────────────
      final myMemberRecord = await groupService.createMemberRecord({
        'conversation_id': convId,
        'user_id':         myId,
        'role':            'admin',
      });

      // ── c) Add selected friends as members ────────────────────
      final selectedFriends = allFriends
          .where((f) => _selectedIds.contains(f.friend.id))
          .toList();

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
          joinedAt:       DateTime.now(),
        ),
      );

      for (final rec in memberRecords) {
        await db.conversationsDao.upsertMember(
          ConversationMembersTableCompanion.insert(
            id:             rec.id,
            conversationId: convId,
            userId:         rec.getStringValue('user_id'),
            role:           const Value('member'),
            joinedAt:       DateTime.now(),
          ),
        );
      }

      // ── d) Generate and distribute group key ──────────────────
      final groupKey  = encryption.generateGroupKey();
      final allMemberIds = [myId, ...selectedFriends.map((f) => f.friend.id)];

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

        if (publicKey == null || publicKey.isEmpty) continue;

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

      // Cache own group key
      await storage.write(
        key:   'group_key_$convId',
        value: base64.encode(groupKey),
      );

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
          joinedAt:       now,
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
            joinedAt:       now,
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
          createdAt:         DateTime.now(),
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
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => ChatScreen(conversation: groupConv)),
          (route) => route.isFirst,
        );
      }
    } catch (e) {
      setState(() => _error = 'Failed to create group: $e');
      debugPrint('[Group] create error: $e');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendshipsProvider);

    return friendsAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error:   (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (friends) => _onStep2
          ? _buildStep2(context, friends)
          : _buildStep1(context, friends),
    );
  }

  // ── Step 1: member selection ──────────────────────────────────

  Widget _buildStep1(BuildContext context, List<Friendship> friends) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'New Group',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _selectedIds.isEmpty
                ? null
                : () => setState(() => _onStep2 = true),
            child: Text(
              'Next',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _selectedIds.isEmpty
                    ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)
                    : context.t.accent,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_selectedIds.isNotEmpty) _SelectedChips(
            friends:     friends,
            selectedIds: _selectedIds,
            onRemove:    (id) => setState(() => _selectedIds.remove(id)),
          ),
          Expanded(
            child: friends.isEmpty
                ? const Center(child: Text('No friends to add.'))
                : ListView.builder(
                    itemCount: friends.length,
                    itemBuilder: (_, i) {
                      final f        = friends[i];
                      final selected = _selectedIds.contains(f.friend.id);
                      return CheckboxListTile(
                        value:    selected,
                        onChanged: (_) => setState(() {
                          if (selected) {
                            _selectedIds.remove(f.friend.id);
                          } else {
                            _selectedIds.add(f.friend.id);
                          }
                        }),
                        secondary: CircleAvatar(
                          backgroundColor: context.t.accentSoft,
                          backgroundImage: f.friend.avatarUrl != null
                              ? CachedNetworkImageProvider(f.friend.avatarUrl!)
                              : null,
                          child: f.friend.avatarUrl == null
                              ? Text(
                                  f.displayName.substring(0, 1).toUpperCase(),
                                  style: TextStyle(
                                    color: context.t.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                        title: Text(
                          f.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '@${f.friend.username}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        activeColor:   context.t.accent,
                        checkboxShape: const CircleBorder(),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: group info ─────────────────────────────────────────

  Widget _buildStep2(BuildContext context, List<Friendship> friends) {
    final name   = _nameController.text.trim();
    final letter = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => setState(() => _onStep2 = false)),
        title: const Text(
          'Group Info',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar picker
            GestureDetector(
              onTap: _pickIcon,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 56,
                    backgroundColor: context.t.accentSoft,
                    backgroundImage:
                        _iconFile != null ? FileImage(_iconFile!) : null,
                    child: _iconFile == null
                        ? Text(
                            letter,
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                              color: context.t.accent,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: context.t.accent, shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.camera_alt_outlined,
                        color: context.t.onAccent,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Group name field
            TextField(
              controller:     _nameController,
              maxLength:      50,
              textCapitalization: TextCapitalization.words,
              onChanged:      (_) => setState(() {}),
              decoration: InputDecoration(
                labelText:   'Group Name',
                hintText:    'Enter group name…',
                border:      OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                prefixIcon:  const Icon(Icons.group_outlined),
                counterText: '${_nameController.text.length}/50',
              ),
            ),
            const SizedBox(height: 12),

            // Selected member count
            Text(
              '${_selectedIds.length} member${_selectedIds.length == 1 ? '' : 's'} selected',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontSize: 13,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Create button
            AppButton(
              onPressed: (_creating || _nameController.text.trim().isEmpty)
                  ? null
                  : () => _createGroup(friends),
              busy: _creating,
              expanded: true,
              child: Text(_creating ? 'Creating…' : 'Create Group'),
            ),
          ],
        ),
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
    final selected = friends.where((f) => selectedIds.contains(f.friend.id)).toList();

    return Container(
      width:  double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: selected.map((f) => Chip(
          avatar: CircleAvatar(
            backgroundColor: context.t.accentSoft,
            backgroundImage: f.friend.avatarUrl != null
                ? CachedNetworkImageProvider(f.friend.avatarUrl!)
                : null,
            child: f.friend.avatarUrl == null
                ? Text(
                    f.displayName.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11, color: context.t.accent,
                    ),
                  )
                : null,
          ),
          label:        Text(f.displayName, style: const TextStyle(fontSize: 12)),
          deleteIcon:   const Icon(Icons.close, size: 16),
          onDeleted:    () => onRemove(f.friend.id),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        )).toList(),
      ),
    );
  }
}
