import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/user.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../../../features/home/providers/friends_provider.dart';
import '../../../features/media/screens/media_docs_screen.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';

class GroupSettingsScreen extends ConsumerStatefulWidget {
  const GroupSettingsScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<GroupSettingsScreen> createState() =>
      _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  Future<void> _pickIcon() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;
    try {
      await ref.read(messageRepositoryProvider).updateGroupInfo(
            widget.conversation.id,
            iconFile: File(picked.path),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update icon: $e')),
        );
      }
    }
  }

  Future<void> _editName(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Group Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: const InputDecoration(hintText: 'Enter group name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      try {
        await ref.read(messageRepositoryProvider).updateGroupInfo(
              widget.conversation.id,
              name: newName,
            );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update name: $e')),
          );
        }
      }
    }
  }

  void _disappearingDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disappearing Messages'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final opt in [
              ('Off', 0),
              ('24 hours', 86400),
              ('7 days', 604800),
              ('30 days', 2592000),
            ])
              ListTile(
                title: Text(opt.$1),
                onTap: () {
                  ref
                      .read(messageRepositoryProvider)
                      .setDisappearingDuration(widget.conversation.id, opt.$2);
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

  Future<void> _showAddMemberSheet(List<User> members) async {
    final friends = ref.read(friendshipsProvider).valueOrNull ?? [];
    final existingIds = members.map((u) => u.id).toSet();
    final available =
        friends.where((f) => !existingIds.contains(f.friend.id)).toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All friends are already in this group')),
      );
      return;
    }

    // Fetch per-friend invite statuses before opening the sheet (invites
    // sent earlier may be pending/declined). Degrade to an empty map so
    // the sheet still opens if the fetch fails.
    var inviteStatuses = <String, String>{};
    try {
      inviteStatuses = await ref
          .read(messageRepositoryProvider)
          .getInviteStatusesForConversation(widget.conversation.id);
    } catch (e) {
      debugPrint('[Group] invite status fetch failed: $e');
    }
    if (!mounted) return;

    final selected = <String>{};
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Add to Group',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                    FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () async {
                              Navigator.pop(ctx);
                              for (final id in selected) {
                                try {
                                  await ref
                                      .read(messageRepositoryProvider)
                                      .sendGroupInvite(
                                          widget.conversation.id, id);
                                } catch (e) {
                                  debugPrint('[Group] invite error: $e');
                                }
                              }
                              // Sheet is already popped; the guard checks the
                              // screen's `mounted` and shows the snackbar on
                              // the outer (screen) context.
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Invite(s) sent')),
                                );
                              }
                            },
                      child: Text('Invite ${selected.length}'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetCtx).size.height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: available.length,
                  itemBuilder: (_, i) {
                    final f = available[i];
                    final u = f.friend;
                    final isSelected = selected.contains(u.id);
                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (val) => setSheetState(() {
                        if (val == true) {
                          selected.add(u.id);
                        } else {
                          selected.remove(u.id);
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
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            : null,
                      ),
                      title: Text(f.displayName),
                      subtitle: inviteStatuses[u.id] == 'pending'
                          ? const Text('Invite pending',
                              style: TextStyle(
                                  color: Colors.orange, fontSize: 12))
                          : inviteStatuses[u.id] == 'declined'
                              ? const Text('Declined — invite again?',
                                  style: TextStyle(
                                      color: Colors.red, fontSize: 12))
                              : Text('@${u.username}'),
                      activeColor: AppColors.primary,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildMemberActions(User user, String myId, bool isAdmin, List<User> members) {
    if (user.id == myId) return null;
    if (!isAdmin) return null;

    final adminCount = members.where((u) => u.groupRole == 'admin').length;

    return PopupMenuButton<String>(
      onSelected: (action) async {
        final repo = ref.read(messageRepositoryProvider);
        try {
          if (action == 'make_admin') {
            await repo.promoteMemberToAdmin(widget.conversation.id, user.id);
          } else if (action == 'remove_admin') {
            await repo.demoteAdminToMember(widget.conversation.id, user.id);
          } else if (action == 'remove') {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Remove from Group'),
                content: Text('Remove ${user.displayName} from the group?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await repo.removeMemberFromGroup(widget.conversation.id, user.id);
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Operation failed: $e')),
            );
          }
        }
      },
      itemBuilder: (_) => [
        if (user.groupRole == 'member')
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
    );
  }

  void _confirmLeaveGroup() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Group?'),
        content:
            const Text('You will lose access to this group and its messages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(messageRepositoryProvider)
                    .leaveGroup(widget.conversation.id);
                if (mounted) {
                  Navigator.of(context).pop(); // Back to ChatScreen!
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to leave group: $e')),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(currentUserIdProvider).asData?.value ?? '';
    final convAsync = ref.watch(conversationStreamProvider(widget.conversation.id));
    final conv = convAsync.asData?.value ?? widget.conversation;

    final membersAsync = ref.watch(groupMembersProvider(widget.conversation.id));
    final members = membersAsync.asData?.value ?? [];

    final activeMembers = members.where((m) => m.groupRole != 'left').toList();
    final myMember = members.where((m) => m.id == myId).firstOrNull;
    final isAdmin = myMember?.groupRole == 'admin';
    final isLeft = myMember?.groupRole == 'left';

    final groupName = conv.name ?? 'Group';
    final iconUrl = conv.iconUrl;

    if (convAsync.isLoading || membersAsync.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 24),

            // ── HEADER ──────────────────────────────────────────────────────────
            GestureDetector(
              onTap: (isAdmin && !isLeft) ? _pickIcon : null,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.primaryLight,
                    backgroundImage: iconUrl != null
                        ? CachedNetworkImageProvider(iconUrl)
                        : null,
                    child: iconUrl == null
                        ? Text(
                            groupName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          )
                        : null,
                  ),
                  if (isAdmin && !isLeft)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Group name
            if (isAdmin && !isLeft)
              InkWell(
                onTap: () => _editName(groupName),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      groupName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined,
                        size: 18, color: AppColors.primary),
                  ],
                ),
              )
            else
              Text(
                groupName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 4),

            Text(
              '${activeMembers.length} members',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 16),

            // ── MEMBERS SECTION ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'MEMBERS',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  if (isAdmin && !isLeft)
                    IconButton(
                      icon: const Icon(Icons.person_add_outlined,
                          color: AppColors.primary),
                      onPressed: () => _showAddMemberSheet(activeMembers),
                    ),
                ],
              ),
            ),

            for (final user in activeMembers)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primaryLight,
                  backgroundImage: user.avatarUrl != null
                      ? CachedNetworkImageProvider(user.avatarUrl!)
                      : null,
                  child: user.avatarUrl == null
                      ? Text(
                          user.displayName.isNotEmpty
                              ? user.displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        user.displayName,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (user.groupRole == 'admin') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: user.id == myId
                    ? const Text('You',
                        style: TextStyle(color: AppColors.primary))
                    : null,
                trailing: _buildMemberActions(user, myId, isAdmin && !isLeft, activeMembers),
              ),

            // ── SETTINGS SECTION (admin only) ───────────────────────────────────
            if (isAdmin && !isLeft) ...[
              _sectionHeader('Settings'),
              SwitchListTile(
                title: const Text('Only Admins Can Message'),
                subtitle: const Text('Members cannot send messages'),
                value: conv.onlyAdminsCanMessage,
                activeColor: AppColors.primary,
                onChanged: (v) async {
                  await ref
                      .read(messageRepositoryProvider)
                      .setOnlyAdminsCanMessage(
                          widget.conversation.id, v);
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Disappearing Messages'),
                onTap: _disappearingDialog,
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Media & Docs'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MediaDocsScreen(
                        conversationId: widget.conversation.id),
                  ),
                ),
              ),
            ],

            // ── DANGER ZONE ──────────────────────────────────────────────────────
            if (!isLeft)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.exit_to_app,
                        color: AppColors.error),
                    label: const Text('Leave Group',
                        style: TextStyle(color: AppColors.error)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.error),
                    ),
                    onPressed: _confirmLeaveGroup,
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
