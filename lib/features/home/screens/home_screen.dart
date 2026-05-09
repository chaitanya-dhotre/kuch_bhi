import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../domain/entities/friendship.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/friend_requests/providers/friend_request_provider.dart';
import '../providers/friends_provider.dart';
import 'add_friend_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState  = ref.watch(authProvider).valueOrNull;
    final user = authState is AuthAuthenticated ? authState.user : null;
    final pendingCount = ref.watch(pendingRequestCountProvider);
    final friendships  = ref.watch(friendshipsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Kuch Bhi',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
        ),
        actions: [
          // Friend requests icon with badge.
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.group_add_outlined),
                tooltip: 'Friend Requests',
                onPressed: () => context.push(AppRoutes.friendRequests),
              ),
              if (pendingCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$pendingCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Profile avatar.
          GestureDetector(
            onTap: () => context.push(AppRoutes.profile),
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
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
      body: friendships.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Failed to load friends: $e'),
        ),
        data: (list) => list.isEmpty
            ? _EmptyState(onAddFriend: () => _showAddFriend(context, ref))
            : _FriendsList(friendships: list),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddFriend(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add Friend'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddFriend});
  final VoidCallback onAddFriend;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 80,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No friends yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add friends using their friend code\nor scan their QR code.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.4),
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAddFriend,
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Add a Friend'),
          ),
        ],
      ),
    );
  }
}

class _FriendsList extends StatelessWidget {
  const _FriendsList({required this.friendships});
  final List<Friendship> friendships;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: friendships.length,
      itemBuilder: (context, index) {
        final f = friendships[index];
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
            f.friend.isOnline ? 'Online' : 'Last seen recently',
            style: TextStyle(
              fontSize: 12,
              color: f.friend.isOnline
                  ? AppColors.success
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (f.friend.isOnline)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
          onTap: () {
            // Phase 4: open chat with this friend.
          },
        );
      },
    );
  }
}
