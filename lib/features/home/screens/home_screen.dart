import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/friendship.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/auth/providers/encryption_sync_provider.dart';
import '../../../data/local/database/app_database.dart';
import '../../../features/friend_requests/providers/friend_request_provider.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../providers/conversations_provider.dart';
import '../providers/friends_provider.dart';
import '../../home/screens/add_friend_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState    = ref.watch(authProvider).valueOrNull;
    final user = authState is AuthAuthenticated ? authState.user : null;
    final pendingCount = ref.watch(pendingRequestCountProvider);
    final convsAsync   = ref.watch(conversationsProvider);
    final friendsAsync = ref.watch(friendshipsProvider);
    final showBanner   = ref.watch(showBackupBannerProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Kuch Bhi',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
        ),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.person_add_alt_1_outlined),
                onPressed: () => context.push(AppRoutes.friendRequests),
              ),
              if (pendingCount > 0)
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    width: 16, height: 16,
                    decoration: const BoxDecoration(
                      color: AppColors.error, shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$pendingCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          GestureDetector(
            onTap: () => context.push(AppRoutes.profile),
            child: Padding(
              padding: const EdgeInsets.only(left: 8, right: 16),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primaryLight,
                backgroundImage: user?.avatarUrl != null
                    ? CachedNetworkImageProvider(user!.avatarUrl!)
                    : null,
                child: user?.avatarUrl == null
                    ? Text(
                        user?.displayName.substring(0, 1).toUpperCase() ?? 'K',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (showBanner)
            Container(
              color: Colors.amber.shade100,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => context.push(AppRoutes.backupPinSetup),
                      child: const Text(
                        'Backup your encryption key to restore messages after reinstall. Tap to set up.',
                        style: TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54, size: 20),
                    onPressed: () async {
                      final db = ref.read(appDatabaseProvider);
                      await db.settingsDao.setSetting(
                        'backup_reminder_dismissed_at',
                        DateTime.now().toIso8601String(),
                      );
                      ref.invalidate(showBackupBannerProvider);
                    },
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(conversationsProvider);
              },
              // Hold a spinner until BOTH `conversationsProvider` and
              // `friendshipsProvider` have produced their first real list.
              // Firing the empty-state UI the moment conversations returned
              // while friends was still loading caused a "blank list" flash
              // on cold start — peer DM rows whose `otherUser` was not yet
              // cached were filtered out and the friends list was still empty.
              // NOTE: do NOT add a third provider that watches the conversation
              // *stream* — a FutureProvider watching a StreamProvider re-runs on
              // every emit, toggling isLoading and causing the list to flicker
              // (and races the element lifecycle → defunct-element assertions).
              child: (convsAsync.isLoading || friendsAsync.isLoading)
                  ? const Center(child: CircularProgressIndicator())
                  : convsAsync.when(
                      // loading is handled by the outer branch above.
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) => Center(child: Text('Error: $e')),
                      data: (allConvs) => _buildList(
                        context,
                        ref,
                        allConvs,
                        friendsAsync.asData?.value ?? const [],
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag:         'fab_main',
        onPressed:       () => _showNewChatSheet(context, ref),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        tooltip:         'New chat',
        child:           const Icon(Icons.add_comment_outlined),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<Conversation> allConvs,
    List<Friendship> friends,
  ) {
    // Direct conversations only render when the peer user record has synced —
    // rows whose `otherUser` is null are dropped here and the friend still
    // appears under Friends, so a freshly accepted friend no longer surfaces
    // in both "Chats" and "Friends".
    final convs = allConvs
        .where((c) => !(c.type == 'direct' && c.otherUser == null))
        .toList();
    final convUserIds = convs
        .where((c) => c.type == 'direct' && c.otherUser != null)
        .map((c) => c.otherUser!.id)
        .toSet();
    final newFriends = friends
        .where((f) => !convUserIds.contains(f.friend.id))
        .toList();

    if (convs.isEmpty && newFriends.isEmpty) {
      return _EmptyState(onAddFriend: () => _showAddFriend(context, ref));
    }

    // Merge DMs + groups into one chronological block. The DB query
    // orders DESC by `last_message_at` (with `is_pinned` first) and
    // `_convRowsToEntities` preserves that order, so iterating together
    // gives a single intermixed Chats list.
    return ListView(
      children: [
        if (convs.isNotEmpty) ...[
          _SectionHeader(title: 'Chats'),
          ...convs.map((c) => _ConversationTile(conv: c)),
        ],
        if (newFriends.isNotEmpty) ...[
          _SectionHeader(title: 'Friends'),
          ...newFriends.map((f) => _FriendsTile(entity: f, onTap: () => _openChat(context, ref, f.friend.id))),
        ],
      ],
    );
  }

  void _showNewChatSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle.
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(sheetContext)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title:   const Text('Add Friend'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showAddFriend(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title:   const Text('New Group'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push(AppRoutes.createGroup);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openChat(
    BuildContext context,
    WidgetRef ref,
    String otherUserId,
  ) async {
    try {
      final conv = await ref
          .read(messageRepositoryProvider)
          .getOrCreateDirectConversation(otherUserId);
      if (context.mounted) {
        context.push(AppRoutes.chat, extra: conv);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat is not ready yet. Try again in a moment.'),
          ),
        );
      }
    }
  }

  void _showAddFriend(BuildContext context, WidgetRef ref) {
    ref.read(addFriendProvider.notifier).reset();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const AddFriendSheet(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.4),
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Friend entry shown under the "Friends" section — for friends that
/// have no active conversation yet. Kept here so the home build-list
/// stays small.
class _FriendsTile extends StatelessWidget {
  const _FriendsTile({required this.entity, required this.onTap});
  final Friendship entity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = entity;
    return ListTile(
      leading: CircleAvatar(
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
        f.friend.isOnline ? 'Online' : 'Tap to start chatting',
        style: TextStyle(
          fontSize: 12,
          color: f.friend.isOnline
              ? AppColors.success
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
      onTap: onTap,
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conv});
  final Conversation conv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUnread = conv.unreadCount > 0;
    return ListTile(
      leading: _ConvAvatar(conv: conv),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conv.displayName,
              style: TextStyle(
                // Bold the title when there are unread messages.
                fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conv.lastMessageAt != null)
            Text(
              _formatTime(conv.lastMessageAt!),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4),
              ),
            ),
        ],
      ),
      subtitle: Text(
        conv.lastMessagePreview ?? 'Tap to open chat',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: hasUnread ? 0.8 : 0.5),
        ),
      ),
      trailing: hasUnread
          ? Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              constraints: const BoxConstraints(minWidth: 22),
              child: Text(
                conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : null,
      onTap: () {
        context.push(AppRoutes.chat, extra: conv);
      },
    );
  }

  String _formatTime(DateTime dt) {
    final now  = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return DateFormat('HH:mm').format(dt.toLocal());
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7)  return DateFormat('EEE').format(dt.toLocal());
    return DateFormat('dd/MM').format(dt.toLocal());
  }
}

class _ConvAvatar extends StatelessWidget {
  const _ConvAvatar({required this.conv});
  final Conversation conv;

  @override
  Widget build(BuildContext context) {
    if (!conv.isGroup) {
      return CircleAvatar(
        backgroundColor: AppColors.primaryLight,
        backgroundImage: conv.avatarUrl != null
            ? CachedNetworkImageProvider(conv.avatarUrl!)
            : null,
        child: conv.avatarUrl == null
            ? Text(
                conv.displayName.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w700,
                ),
              )
            : null,
      );
    }

    // Group avatar
    return Stack(
      children: [
        CircleAvatar(
          backgroundColor: AppColors.primaryLight,
          backgroundImage: conv.iconUrl != null
              ? CachedNetworkImageProvider(conv.iconUrl!)
              : null,
          child: conv.iconUrl == null
              ? Text(
                  conv.displayName.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        Positioned(
          bottom: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.group, size: 12, color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddFriend});
  final VoidCallback onAddFriend;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80,
              color: Theme.of(context)
                  .colorScheme.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('No chats yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme.onSurface.withValues(alpha: 0.5),
                  )),
          const SizedBox(height: 8),
          Text('Add friends to start chatting.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme.onSurface.withValues(alpha: 0.4),
                  )),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAddFriend,
            icon:  const Icon(Icons.person_add_outlined),
            label: const Text('Add a Friend'),
          ),
        ],
      ),
    );
  }
}
