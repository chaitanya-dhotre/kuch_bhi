import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/chat_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_banner.dart';
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
import '../../chat/widgets/message_body_text.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final authState = ref.watch(authProvider).valueOrNull;
    final user = authState is AuthAuthenticated ? authState.user : null;
    final pendingCount = ref.watch(pendingRequestCountProvider);
    final convsAsync = ref.watch(conversationsProvider);
    final friendsAsync = ref.watch(friendshipsProvider);
    final showBanner = ref.watch(showBackupBannerProvider).valueOrNull ?? false;

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
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: t.error,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$pendingCount',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onError,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
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
              child: _AppAvatar(
                url: user?.avatarUrl,
                initials:
                    user?.displayName.substring(0, 1).toUpperCase() ?? 'K',
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (showBanner)
            Container(
              color: t.accentSoft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: t.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => context.push(AppRoutes.backupPinSetup),
                      child: Text(
                        'Backup your encryption key to restore messages after reinstall. Tap to set up.',
                        style: TextStyle(
                          color: t.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: t.inkSoft, size: 20),
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
              // Conversations are local-first, so render them as soon as the
              // stream has data. Friendships may still be establishing their
              // network/SSE subscription; only hold the empty state until
              // that first friendship result arrives.
              child: convsAsync.when(
                loading: _buildLoadingSkeleton,
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: StatusBanner(
                      message: 'Could not load your chats.',
                      onRetry: () {
                        ref.invalidate(conversationsProvider);
                        ref.invalidate(friendshipsProvider);
                      },
                    ),
                  ),
                ),
                data: (allConvs) {
                  final hasRenderableConversations = allConvs.any(
                    (conversation) =>
                        conversation.type != 'direct' ||
                        conversation.otherUser != null,
                  );
                  if (friendsAsync.isLoading && !hasRenderableConversations) {
                    return _buildLoadingSkeleton();
                  }
                  return _buildList(
                    context,
                    ref,
                    allConvs,
                    friendsAsync.asData?.value ?? const [],
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_main',
        onPressed: () => _showNewChatSheet(context, ref),
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        tooltip: 'New chat',
        child: const Icon(Icons.add_comment_outlined),
      ),
    );
  }

  Widget _buildLoadingSkeleton() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Skeleton(height: 56, radius: 16),
        SizedBox(height: 10),
        Skeleton(height: 56, radius: 16),
        SizedBox(height: 10),
        Skeleton(height: 56, radius: 16),
        SizedBox(height: 10),
        Skeleton(height: 56, radius: 16),
      ],
    ),
  );

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
          const SectionHeader('Chats'),
          ...convs.map((c) => _ConversationTile(conv: c)),
        ],
        if (newFriends.isNotEmpty) ...[
          const SectionHeader('Friends'),
          ...newFriends.map(
            (f) => _FriendsTile(
              entity: f,
              onTap: () => _openChat(context, ref, f.friend.id),
            ),
          ),
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
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(
                  sheetContext,
                ).colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_outlined),
              title: const Text('Add Friend'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showAddFriend(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('New Group'),
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
    return ChatTile(
      title: f.displayName,
      subtitle: f.friend.isOnline ? 'Online' : 'Tap to start chatting',
      subtitleColor: f.friend.isOnline ? context.t.success : null,
      avatarUrl: f.friend.avatarUrl,
      onTap: onTap,
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conv});
  final Conversation conv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // P7 (spec §3): no stored preview string exists anymore — the tile's
    // subtitle is DERIVED (newest row via messageBodyProvider; media/system
    // labels are constants; empty conversation → this fallback). Never a
    // durable plaintext fallback.
    const fallback = 'Tap to open chat';
    // #74: pointer-DOWN (not tap) kicks the predecrypt — the ~250ms open
    // transition then hides the decrypt work. Listener, NOT GestureDetector
    // onTapDown: a parent tap recognizer never WINS the arena (the tile's
    // own tap does), so its onTapDown would never fire. Raw pointer events
    // dispatch regardless of the arena. A failed/aborted press just warms
    // cache early; the method swallows its own errors.
    return Listener(
      onPointerDown: (_) {
        debugPrint('[Msg] TAPDOWN fired conv=${conv.id}');
        unawaited(
          ref
              .read(messageRepositoryProvider)
              .predecryptConversation(conv.id),
        );
      },
      child: ChatTile(
        title: conv.displayName,
        // Kept for the non-widget call paths / badge math; the visible
        // subtitle is the provider-driven preview below (spec §8: preview
        // shows a placeholder until the last body emits, never a blank).
        subtitle: fallback,
        subtitleWidget: ConversationPreviewText(
          conversation: conv,
          fallback: fallback,
        ),
        time: conv.lastMessageAt != null
            ? _formatTime(conv.lastMessageAt!)
            : null,
        unreadCount: conv.unreadCount,
        avatarUrl: conv.isGroup ? conv.iconUrl : conv.avatarUrl,
        isGroup: conv.isGroup,
        onTap: () => context.push(AppRoutes.chat, extra: conv),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return DateFormat('HH:mm').format(dt.toLocal());
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat('EEE').format(dt.toLocal());
    return DateFormat('dd/MM').format(dt.toLocal());
  }
}

class _AppAvatar extends StatelessWidget {
  const _AppAvatar({this.url, required this.initials});
  final String? url;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return CircleAvatar(
      radius: 18,
      backgroundColor: t.accentSoft,
      backgroundImage: url != null ? CachedNetworkImageProvider(url!) : null,
      child: url != null
          ? null
          : Text(
              initials,
              style: TextStyle(color: t.accent, fontWeight: FontWeight.w700),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddFriend});
  final VoidCallback onAddFriend;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: 'No chats yet',
      subtitle: 'Add friends to start chatting.',
      action: FilledButton.icon(
        onPressed: onAddFriend,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add a Friend'),
      ),
    );
  }
}
