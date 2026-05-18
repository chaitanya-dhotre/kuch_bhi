import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/pocketbase_client.dart';
import '../../../core/router/app_router.dart';
import '../../../data/local/database/app_database.dart';
import '../../../data/local/database/tables/conversation_members_table.dart';
import '../../../data/local/database/tables/conversations_table.dart';
import '../../../data/local/secure_storage/secure_storage_service.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/friendship.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/home/providers/friends_provider.dart';
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
      final pb        = ref.read(pocketbaseClientProvider).pb;
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

      RecordModel conv;
      if (_iconFile != null) {
        conv = await pb.collection('conversations').create(
          body: convBody,
          files: [
            http.MultipartFile.fromBytes(
              'icon',
              await _iconFile!.readAsBytes(),
              filename: 'icon.jpg',
            ),
          ],
        );
      } else {
        conv = await pb.collection('conversations').create(body: convBody);
      }

      final convId = conv.id;

      // ── b) Add creator as admin ───────────────────────────────
      final myMemberRecord = await pb.collection('conversation_members').create(body: {
        'conversation_id': convId,
        'user_id':         myId,
        'role':            'admin',
      });

      // ── c) Add selected friends as members ────────────────────
      final selectedFriends = allFriends
          .where((f) => _selectedIds.contains(f.friend.id))
          .toList();

      final List<RecordModel> memberRecords = [];
      for (final f in selectedFriends) {
        final rec = await pb.collection('conversation_members').create(body: {
          'conversation_id': convId,
          'user_id':         f.friend.id,
          'role':            'member',
        });
        memberRecords.add(rec);
      }

      // ── d) Generate and distribute group key ──────────────────
      final groupKey  = encryption.generateGroupKey();
      final allMemberIds = [myId, ...selectedFriends.map((f) => f.friend.id)];

      for (final memberId in allMemberIds) {
        // Try local Drift cache first, fallback to PocketBase fetch
        var userRow = await db.usersDao.getUserById(memberId);
        String? publicKey = userRow?.publicKey;

        if (publicKey == null || publicKey.isEmpty) {
          try {
            final r = await pb.collection('users').getOne(memberId);
            publicKey = r.getStringValue('public_key');
          } catch (e) {
            debugPrint('[Group] Could not fetch public key for $memberId: $e');
          }
        }

        if (publicKey == null || publicKey.isEmpty) continue;

        final encryptedKey = await encryption.encryptGroupKeyForMember(
          groupKey,
          publicKey,
          convId,
        );

        await pb.collection('group_keys').create(body: {
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
          : '${pb.baseUrl}/api/files/conversations/$convId/$iconField';

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

      // ── g) Navigate to ChatScreen ─────────────────────────────
      final groupConversation = Conversation(
        id:      convId,
        type:    'group',
        name:    groupName,
        iconUrl: iconUrl,
      );

      if (mounted) {
        context.go(AppRoutes.home);
        context.push(AppRoutes.chat, extra: groupConversation);
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
                    : AppColors.primary,
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
                          backgroundColor: AppColors.primaryLight,
                          backgroundImage: f.friend.avatarUrl != null
                              ? CachedNetworkImageProvider(f.friend.avatarUrl!)
                              : null,
                          child: f.friend.avatarUrl == null
                              ? Text(
                                  f.displayName.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.primary,
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
                        activeColor:   AppColors.primary,
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
                    backgroundColor: AppColors.primaryLight,
                    backgroundImage:
                        _iconFile != null ? FileImage(_iconFile!) : null,
                    child: _iconFile == null
                        ? Text(
                            letter,
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        color: Colors.white,
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
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_creating || _nameController.text.trim().isEmpty)
                    ? null
                    : () => _createGroup(friends),
                icon:  _creating
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_creating ? 'Creating…' : 'Create Group'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
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
            backgroundColor: AppColors.primaryLight,
            backgroundImage: f.friend.avatarUrl != null
                ? CachedNetworkImageProvider(f.friend.avatarUrl!)
                : null,
            child: f.friend.avatarUrl == null
                ? Text(
                    f.displayName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11, color: AppColors.primary,
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
