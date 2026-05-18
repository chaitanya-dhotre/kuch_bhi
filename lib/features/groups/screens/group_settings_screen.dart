import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/pocketbase_client.dart';
import '../../../core/router/app_router.dart';
import '../../../data/local/database/app_database.dart';
import '../../../data/local/database/tables/conversations_table.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/user.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../../../features/home/providers/friends_provider.dart';
import '../../../features/media/screens/media_docs_screen.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import 'package:drift/drift.dart' show Value;

class GroupSettingsScreen extends ConsumerStatefulWidget {
  const GroupSettingsScreen({super.key, required this.conversation});
  final Conversation conversation;

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  late Conversation _conv;

  bool   _editingName   = false;
  bool   _savingName    = false;
  bool   _uploadingIcon = false;
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _conv    = widget.conversation;
    _nameCtrl = TextEditingController(text: _conv.name ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────

  String get _cid => _conv.id;

  Future<void> _pickAndUploadIcon() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512, maxHeight: 512, imageQuality: 80,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingIcon = true);
    try {
      final pb    = ref.read(pocketbaseClientProvider).pb;
      final bytes = await File(picked.path).readAsBytes();
      final rec   = await pb.collection('conversations').update(
        _cid,
        files: [
          http.MultipartFile.fromBytes('icon', bytes, filename: 'icon.jpg'),
        ],
      );
      final iconField = rec.getStringValue('icon');
      final iconUrl   = iconField.isEmpty
          ? null
          : '${pb.baseUrl}/api/files/conversations/$_cid/$iconField';

      // Sync Drift
      final db = ref.read(appDatabaseProvider);
      await db.conversationsDao.upsertConversation(
        ConversationsTableCompanion(
          id:        Value(_cid),
          iconUrl:   Value(iconUrl),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (mounted) {
        setState(() => _conv = Conversation(
          id:                   _conv.id,
          type:                 _conv.type,
          name:                 _conv.name,
          iconUrl:              iconUrl,
          lastMessagePreview:   _conv.lastMessagePreview,
          lastMessageAt:        _conv.lastMessageAt,
          isPinned:             _conv.isPinned,
          otherUser:            _conv.otherUser,
          onlyAdminsCanMessage: _conv.onlyAdminsCanMessage,
          memberCount:          _conv.memberCount,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update icon: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingIcon = false);
    }
  }

  Future<void> _saveName() async {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty || newName == _conv.name) {
      setState(() => _editingName = false);
      return;
    }
    setState(() => _savingName = true);
    try {
      final pb = ref.read(pocketbaseClientProvider).pb;
      await pb.collection('conversations').update(_cid, body: {'name': newName});
      final db = ref.read(appDatabaseProvider);
      await db.conversationsDao.upsertConversation(
        ConversationsTableCompanion(
          id:        Value(_cid),
          name:      Value(newName),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (mounted) {
        setState(() {
          _conv = Conversation(
            id:                   _conv.id,
            type:                 _conv.type,
            name:                 newName,
            iconUrl:              _conv.iconUrl,
            lastMessagePreview:   _conv.lastMessagePreview,
            lastMessageAt:        _conv.lastMessageAt,
            isPinned:             _conv.isPinned,
            otherUser:            _conv.otherUser,
            onlyAdminsCanMessage: _conv.onlyAdminsCanMessage,
            memberCount:          _conv.memberCount,
          );
          _editingName = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update name: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _onlyAdminsChanged(bool value) async {
    try {
      await ref
          .read(messageRepositoryProvider)
          .setOnlyAdminsCanMessage(_cid, value);
      if (mounted) {
        setState(() => _conv = Conversation(
          id:                   _conv.id,
          type:                 _conv.type,
          name:                 _conv.name,
          iconUrl:              _conv.iconUrl,
          lastMessagePreview:   _conv.lastMessagePreview,
          lastMessageAt:        _conv.lastMessageAt,
          isPinned:             _conv.isPinned,
          otherUser:            _conv.otherUser,
          onlyAdminsCanMessage: value,
          memberCount:          _conv.memberCount,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  void _disappearingDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title:   const Text('Disappearing Messages'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final opt in [
              ('Off',      0),
              ('24 hours', 86400),
              ('7 days',   604800),
              ('30 days',  2592000),
            ])
              ListTile(
                title: Text(opt.$1),
                onTap: () {
                  ref.read(messageRepositoryProvider)
                      .setDisappearingDuration(_cid, opt.$2);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Disappearing: ${opt.$1}')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:   const Text('Leave Group?'),
        content: const Text(
            'You will lose access to group messages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.error),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(messageRepositoryProvider).leaveGroup(_cid);
      if (mounted) context.go(AppRoutes.home);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to leave: $e')),
        );
      }
    }
  }

  Future<void> _showAddMemberSheet(
    List<User> existingMembers,
  ) async {
    final friends = ref.read(friendshipsProvider).valueOrNull ?? [];
    final existingIds = existingMembers.map((u) => u.id).toSet();
    final available  = friends
        .where((f) => !existingIds.contains(f.friend.id))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All friends are already in this group')),
      );
      return;
    }

    final selected = <String>{};
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddMemberSheet(
        available:  available.map((f) => f.friend).toList(),
        onConfirm:  (ids) async {
          Navigator.pop(ctx);
          for (final id in ids) {
            try {
              await ref
                  .read(messageRepositoryProvider)
                  .addMemberToGroup(_cid, id);
            } catch (e) {
              debugPrint('[GroupSettings] addMember error: $e');
            }
          }
          ref.invalidate(groupMembersProvider(_cid));
        },
      ),
    );
  }

  Future<void> _handleMemberAction(
    String action,
    User member,
    List<User> allMembers,
  ) async {
    final repo = ref.read(messageRepositoryProvider);
    try {
      if (action == 'make_admin') {
        await repo.promoteMemberToAdmin(_cid, member.id);
      } else if (action == 'remove_admin') {
        await repo.demoteAdminToMember(_cid, member.id);
      } else if (action == 'remove') {
        await repo.removeMemberFromGroup(_cid, member.id);
      }
      ref.invalidate(groupMembersProvider(_cid));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e')),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final myId         = ref.watch(currentUserIdProvider).asData?.value ?? '';
    final membersAsync = ref.watch(groupMembersProvider(_cid));
    final isAdminAsync = ref.watch(_isAdminProvider(_cid));
    final isAdmin      = isAdminAsync.asData?.value ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Group Info')),
      body: ListView(
        children: [
          // ── Header ────────────────────────────────────────────
          _GroupHeader(
            conv:           _conv,
            isAdmin:        isAdmin,
            uploadingIcon:  _uploadingIcon,
            editingName:    _editingName,
            savingName:     _savingName,
            nameCtrl:       _nameCtrl,
            onPickIcon:     _pickAndUploadIcon,
            onEditName:     () => setState(() => _editingName = true),
            onSaveName:     _saveName,
            onCancelEdit:   () => setState(() {
              _editingName = false;
              _nameCtrl.text = _conv.name ?? '';
            }),
          ),

          const SizedBox(height: 8),

          // ── Members section ───────────────────────────────────
          _SectionHeader(
            title: 'Members',
            trailing: isAdmin
                ? IconButton(
                    icon:      const Icon(Icons.person_add_outlined,
                        color: AppColors.primary),
                    tooltip:   'Add Member',
                    onPressed: () => membersAsync.whenData(
                      (members) => _showAddMemberSheet(members),
                    ),
                  )
                : null,
          ),

          membersAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child:   Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child:   Text('Error loading members: $e',
                  style: const TextStyle(color: AppColors.error)),
            ),
            data: (members) => Column(
              children: members.map((member) {
                // Determine role by checking members list for this user
                // We use the member count provider from Drift to get role
                return _MemberTile(
                  member:       member,
                  myId:         myId,
                  convId:       _cid,
                  isAdmin:      isAdmin,
                  allMembers:   members,
                  onAction:     _handleMemberAction,
                );
              }).toList(),
            ),
          ),

          // ── Admin settings section ────────────────────────────
          if (isAdmin) ...[
            const SizedBox(height: 8),
            const _SectionHeader(title: 'Group Settings'),

            SwitchListTile(
              title:     const Text('Only Admins Can Message'),
              subtitle:  const Text('Members cannot send messages'),
              value:     _conv.onlyAdminsCanMessage,
              onChanged: _onlyAdminsChanged,
              activeColor: AppColors.primary,
            ),

            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title:   const Text('Disappearing Messages'),
              onTap:   _disappearingDialog,
            ),

            ListTile(
              leading: const Icon(Icons.perm_media_outlined),
              title:   const Text('Media & Docs'),
              onTap:   () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MediaDocsScreen(conversationId: _cid),
              )),
            ),
          ],

          // ── Danger zone ───────────────────────────────────────
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.exit_to_app,
                color: AppColors.error),
            title: const Text(
              'Leave Group',
              style: TextStyle(
                color:      AppColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: _confirmLeave,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Header widget ─────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.conv,
    required this.isAdmin,
    required this.uploadingIcon,
    required this.editingName,
    required this.savingName,
    required this.nameCtrl,
    required this.onPickIcon,
    required this.onEditName,
    required this.onSaveName,
    required this.onCancelEdit,
  });

  final Conversation          conv;
  final bool                  isAdmin;
  final bool                  uploadingIcon;
  final bool                  editingName;
  final bool                  savingName;
  final TextEditingController nameCtrl;
  final VoidCallback          onPickIcon;
  final VoidCallback          onEditName;
  final VoidCallback          onSaveName;
  final VoidCallback          onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final memberCount = conv.memberCount ?? 0;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          // Avatar
          GestureDetector(
            onTap: isAdmin ? onPickIcon : null,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: AppColors.primaryLight,
                  backgroundImage: conv.iconUrl != null
                      ? CachedNetworkImageProvider(conv.iconUrl!)
                      : null,
                  child: uploadingIcon
                      ? const CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary)
                      : conv.iconUrl == null
                          ? Text(
                              (conv.name ?? 'G')
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                fontSize:   36,
                                color:      AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                ),
                if (isAdmin)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color:  AppColors.primary,
                      shape:  BoxShape.circle,
                      border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 2),
                    ),
                    child: const Icon(Icons.camera_alt,
                        size: 14, color: Colors.white),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Name
          if (editingName)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller:  nameCtrl,
                    autofocus:   true,
                    maxLength:   50,
                    decoration:  const InputDecoration(
                      hintText:       'Group name',
                      counterText:    '',
                      border:         OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onSubmitted: (_) => onSaveName(),
                    onEditingComplete: onSaveName,
                  ),
                ),
                const SizedBox(width: 8),
                if (savingName)
                  const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  IconButton(
                    icon:      const Icon(Icons.check,
                        color: AppColors.success),
                    onPressed: onSaveName,
                  ),
                  IconButton(
                    icon:      const Icon(Icons.close,
                        color: AppColors.error),
                    onPressed: onCancelEdit,
                  ),
                ],
              ],
            )
          else
            GestureDetector(
              onTap: isAdmin ? onEditName : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    conv.name ?? 'Group',
                    style: const TextStyle(
                      fontSize:   20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined,
                        size: 16, color: AppColors.primary),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 4),

          Text(
            '$memberCount member${memberCount == 1 ? '' : 's'}',
            style: TextStyle(
              fontSize: 13,
              color:    Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String  title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize:      11,
                fontWeight:    FontWeight.w700,
                color:         Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4),
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ── Member tile ───────────────────────────────────────────────────────────

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.member,
    required this.myId,
    required this.convId,
    required this.isAdmin,
    required this.allMembers,
    required this.onAction,
  });

  final User     member;
  final String   myId;
  final String   convId;
  final bool     isAdmin;
  final List<User> allMembers;
  final Future<void> Function(String action, User member, List<User> all)
      onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memberRoleAsync = ref.watch(_memberRoleProvider((
      convId: convId,
      userId: member.id,
    )));
    final role = memberRoleAsync.asData?.value ?? 'member';
    final isMe = member.id == myId;

    // Count admins to decide whether "Remove Admin" is shown
    final adminCount = allMembers
        .where((u) => ref
            .read(_memberRoleProvider((convId: convId, userId: u.id)))
            .asData
            ?.value ==
            'admin')
        .length;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primaryLight,
        backgroundImage: member.avatarUrl != null
            ? CachedNetworkImageProvider(member.avatarUrl!)
            : null,
        child: member.avatarUrl == null
            ? Text(
                member.displayName.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color:      AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              )
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              isMe ? '${member.displayName} (You)' : member.displayName,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (role == 'admin')
            Container(
              margin:  const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color:        AppColors.primaryLight,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Admin',
                style: TextStyle(
                  fontSize:   10,
                  fontWeight: FontWeight.w600,
                  color:      AppColors.primary,
                ),
              ),
            ),
        ],
      ),
      trailing: (isAdmin && !isMe)
          ? PopupMenuButton<String>(
              onSelected: (action) =>
                  onAction(action, member, allMembers),
              itemBuilder: (_) => [
                if (role == 'member')
                  const PopupMenuItem(
                    value: 'make_admin',
                    child: Text('Make Admin'),
                  )
                else if (adminCount > 1)
                  const PopupMenuItem(
                    value: 'remove_admin',
                    child: Text('Remove Admin'),
                  ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    'Remove from Group',
                    style: TextStyle(color: AppColors.error),
                  ),
                ),
              ],
            )
          : null,
    );
  }
}

// ── Add-member bottom sheet ───────────────────────────────────────────────

class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet({
    required this.available,
    required this.onConfirm,
  });

  final List<User>              available;
  final Future<void> Function(Set<String> ids) onConfirm;

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final Set<String> _selected = {};
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Add Members',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton(
                  onPressed: (_selected.isEmpty || _adding)
                      ? null
                      : () async {
                          setState(() => _adding = true);
                          await widget.onConfirm(_selected);
                        },
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: _adding
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                      : const Text('Add'),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.available.length,
              itemBuilder: (_, i) {
                final u = widget.available[i];
                return CheckboxListTile(
                  value:   _selected.contains(u.id),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(u.id);
                    } else {
                      _selected.remove(u.id);
                    }
                  }),
                  secondary: CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    backgroundImage: u.avatarUrl != null
                        ? CachedNetworkImageProvider(u.avatarUrl!)
                        : null,
                    child: u.avatarUrl == null
                        ? Text(
                            u.displayName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color:      AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  title: Text(u.displayName),
                  activeColor: AppColors.primary,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Providers ─────────────────────────────────────────────────────────────

final _isAdminProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, convId) {
  return ref.read(messageRepositoryProvider).isCurrentUserAdmin(convId);
});

final _memberRoleProvider = FutureProvider.autoDispose
    .family<String, ({String convId, String userId})>((ref, args) async {
  final db      = ref.read(appDatabaseProvider);
  final member  = await db.conversationsDao
      .getMemberByUserAndConv(args.userId, args.convId);
  return member?.role ?? 'member';
});
