import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/chat_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/friendship.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/auth/providers/encryption_sync_provider.dart';
import '../../../features/chat/providers/message_body_provider.dart';
import '../../../features/chat/widgets/message_body_text.dart';
import '../../../features/chat/widgets/message_context_menu.dart';
import '../../../features/friend_requests/providers/friend_request_provider.dart';
import '../../../features/mascot/capybara.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../providers/conversations_provider.dart';
import '../providers/friends_provider.dart';
import '../widgets/home_search_bar.dart';
import 'add_friend_screen.dart';

final _groupSenderNameProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, senderId) async {
      if (senderId.isEmpty) return null;
      final user = await ref
          .read(appDatabaseProvider)
          .usersDao
          .getUserById(senderId);
      final name = user?.displayName.trim();
      return name == null || name.isEmpty ? null : name;
    });

/// Gives the app-bar badge a real loading boundary. The underlying count
/// provider intentionally collapses its two async sources to zero while they
/// load; keeping this value async prevents a transient zero/count swap from
/// becoming visible chrome.
final _pendingRequestCountAsyncProvider = FutureProvider<int>((ref) async {
  return ref.watch(pendingRequestCountProvider);
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final ScrollController _scrollController;

  String _query = '';
  bool _searchFocused = false;
  bool _backupBannerVisible = false;
  bool _backupBannerDismissed = false;
  bool _upgradeBannerDismissed = false;
  double? _searchOriginOffset;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _scrollController = ScrollController();
    _searchFocusNode.addListener(_handleSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSearchFocusChanged() {
    if (!mounted) return;
    final focused = _searchFocusNode.hasFocus;
    if (focused == _searchFocused) return;
    setState(() => _searchFocused = focused);
  }

  void _handleSearchChanged(String value) {
    final oldQuery = _query.trim();
    final nextQuery = value.trim();
    if (oldQuery.isEmpty && nextQuery.isNotEmpty) {
      _searchOriginOffset = _scrollController.hasClients
          ? _scrollController.offset
          : null;
    }
    if (value == _query) return;
    setState(() => _query = value);
    if (oldQuery.isNotEmpty && nextQuery.isEmpty) {
      _restoreSearchScroll();
    }
  }

  void _restoreSearchScroll() {
    final origin = _searchOriginOffset;
    _searchOriginOffset = null;
    if (origin == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(origin.clamp(0.0, max).toDouble());
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final authState = ref.watch(authProvider).valueOrNull;
    final user = authState is AuthAuthenticated ? authState.user : null;
    final pendingCount =
        ref.watch(_pendingRequestCountAsyncProvider).valueOrNull ?? 0;
    final conversationsAsync = ref.watch(conversationsProvider);
    final friendsAsync = ref.watch(friendshipsProvider);
    final backupAsync = ref.watch(showBackupBannerProvider);
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;

    // Keep an already-visible banner through a provider refresh. Initial
    // loading remains hidden until the provider has produced its first value.
    ref.listen<AsyncValue<bool>>(showBackupBannerProvider, (_, next) {
      final value = next.valueOrNull;
      if (value == null || !mounted) return;
      if (value) {
        if (!_backupBannerDismissed && !_backupBannerVisible) {
          setState(() => _backupBannerVisible = true);
        }
      } else if (_backupBannerVisible || _backupBannerDismissed) {
        setState(() {
          _backupBannerVisible = false;
          _backupBannerDismissed = false;
        });
      }
    });
    if (backupAsync.valueOrNull == true &&
        !_backupBannerVisible &&
        !_backupBannerDismissed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _backupBannerVisible || _backupBannerDismissed) return;
        setState(() => _backupBannerVisible = true);
      });
    }
    final showBackupBanner =
        !_backupBannerDismissed &&
        (backupAsync.hasValue
            ? backupAsync.valueOrNull == true
            : _backupBannerVisible);
    // B4 / D9: one banner at a time, no backup wins.
    final showUpgradeBanner = !showBackupBanner &&
        !_upgradeBannerDismissed &&
        ref.watch(showBackupUpgradeBannerProvider).valueOrNull == true;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: t.bg,
        surfaceTintColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Kuch Bhi',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -.02,
          ),
        ),
        actions: [
          _RequestsButton(
            count: pendingCount,
            onPressed: () => context.push(AppRoutes.friendRequests),
          ),
          _ProfileButton(
            url: user?.avatarUrl,
            initials: _initials(user?.displayName ?? 'K'),
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
      body: Column(
        children: [
          _BackupBannerSlot(
            upgrade: showUpgradeBanner,
            visible: showBackupBanner || showUpgradeBanner,
            onTap: () => context.push(showUpgradeBanner
                ? AppRoutes.backupPinChange
                : AppRoutes.backupPinSetup),
            onDismiss: showUpgradeBanner
                ? _dismissUpgradeBanner
                : _dismissBackupBanner,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: HomeSearchBar(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _handleSearchChanged,
              onClear: _restoreSearchScroll,
            ),
          ),
          _OfflineBannerSlot(
            visible: !isOnline,
            onRetry: () => unawaited(_refreshHome()),
          ),
          Expanded(
            child: RefreshIndicator(
              color: t.accent,
              onRefresh: _refreshHome,
              child: conversationsAsync.when(
                loading: _buildLoadingSkeleton,
                error: (error, stackTrace) => _buildErrorState(),
                data: (allConversations) {
                  final hasRenderableConversations = allConversations.any(
                    (conversation) =>
                        conversation.type != 'direct' ||
                        conversation.otherUser != null,
                  );
                  if (friendsAsync.isLoading && !hasRenderableConversations) {
                    return _buildLoadingSkeleton();
                  }
                  return _buildList(
                    allConversations,
                    friendsAsync.valueOrNull ?? const [],
                    friendsHasError: friendsAsync.hasError,
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _searchFocused
          ? null
          : _HomeFab(onPressed: () => _showNewChatSheet(context, ref)),
    );
  }

  Future<void> _dismissBackupBanner() async {
    if (mounted) {
      setState(() {
        _backupBannerDismissed = true;
        _backupBannerVisible = false;
      });
    }
    final db = ref.read(appDatabaseProvider);
    await db.settingsDao.setSetting(
      'backup_reminder_dismissed_at',
      DateTime.now().toIso8601String(),
    );
    ref.invalidate(showBackupBannerProvider);
  }

  Future<void> _dismissUpgradeBanner() async {
    setState(() => _upgradeBannerDismissed = true);
    await ref.read(appDatabaseProvider).settingsDao.setSetting(
          'backup_upgrade_dismissed_at',
          DateTime.now().toIso8601String(),
        );
    ref.invalidate(showBackupUpgradeBannerProvider);
  }

  Future<void> _refreshHome() async {
    ref.invalidate(conversationsProvider);
    ref.invalidate(friendshipsProvider);
    try {
      await Future.wait<void>([
        ref.read(conversationsProvider.future).then<void>((_) {}),
        ref.read(friendshipsProvider.future).then<void>((_) {}),
      ]);
    } catch (_) {
      // RefreshIndicator should finish quietly; the provider error branch is
      // the durable recovery surface.
    }
  }

  Widget _buildLoadingSkeleton() {
    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Skeleton(
              width: 56,
              height: 12,
              radius: 6,
              duration: Duration(milliseconds: 1400),
            ),
          ),
        ),
        for (var index = 0; index < 4; index++) _HomeSkeletonTile(index: index),
      ],
    );
  }

  Widget _buildErrorState() {
    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .58,
          child: EmptyState(
            mascot: const Capybara(
              mood: CapyMood.sleepy,
              showKey: true,
              size: Size(84, 76),
            ),
            title: 'Couldn’t load your chats',
            subtitle: 'Check your connection and try again.',
            action: FilledButton(
              onPressed: () => unawaited(_refreshHome()),
              child: const Text('Retry'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList(
    List<Conversation> allConversations,
    List<Friendship> friendships, {
    required bool friendsHasError,
  }) {
    // Unsynced direct conversations are intentionally excluded from Chats.
    // The matching friend remains in Friends until its peer row is available.
    final conversations = allConversations
        .where(
          (conversation) =>
              !(conversation.type == 'direct' &&
                  conversation.otherUser == null),
        )
        .toList();
    final conversationUserIds = conversations
        .where(
          (conversation) =>
              conversation.type == 'direct' && conversation.otherUser != null,
        )
        .map((conversation) => conversation.otherUser!.id)
        .toSet();
    final friends = friendships
        .where(
          (friendship) => !conversationUserIds.contains(friendship.friend.id),
        )
        .toList();

    final query = _query.trim().toLowerCase();
    final filteredConversations = _filterByName(conversations, query);
    final filteredFriends = _filterByName(friends, query);

    if (query.isEmpty && conversations.isEmpty && friends.isEmpty) {
      return _buildEmptyList();
    }

    if (query.isNotEmpty &&
        filteredConversations.isEmpty &&
        filteredFriends.isEmpty) {
      return _buildNoResultsList(
        'No chats or friends match ‘${_query.trim()}’.',
      );
    }

    final children = <Widget>[];
    if (filteredConversations.isNotEmpty) {
      children.add(
        _HomeSectionHeader(
          key: const ValueKey('home-section-chats'),
          title: 'Chats',
          count: filteredConversations.length,
        ),
      );
      children.addAll(
        filteredConversations.map(
          (conversation) => _ConversationTile(
            key: ValueKey('conversation-${conversation.id}'),
            conv: conversation,
          ),
        ),
      );
    } else if (query.isNotEmpty &&
        conversations.isNotEmpty &&
        filteredFriends.isNotEmpty) {
      children.add(_NoResultsLine('No chats match ‘${_query.trim()}’.'));
    }

    if (friendsHasError && filteredFriends.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: StatusBanner(
            message: 'Couldn’t load your friends.',
            onRetry: () => unawaited(_refreshHome()),
          ),
        ),
      );
    }

    if (filteredFriends.isNotEmpty) {
      children.add(
        _HomeSectionHeader(
          key: const ValueKey('home-section-friends'),
          title: 'Friends',
          count: filteredFriends.length,
        ),
      );
      children.addAll(
        filteredFriends.map(
          (friendship) => _FriendsTile(
            key: ValueKey('friend-${friendship.friend.id}'),
            entity: friendship,
            onTap: () => _openChat(friendship.friend.id),
          ),
        ),
      );
    } else if (query.isNotEmpty &&
        friends.isNotEmpty &&
        filteredConversations.isNotEmpty) {
      children.add(_NoResultsLine('No friends match ‘${_query.trim()}’.'));
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: children.length,
      itemBuilder: (_, index) => children[index],
    );
  }

  List<T> _filterByName<T>(List<T> values, String query) {
    if (query.isEmpty) return List<T>.of(values);
    return values.where((value) {
      final name = value is Conversation
          ? value.displayName
          : (value as Friendship).displayName;
      return name.toLowerCase().contains(query);
    }).toList();
  }

  Widget _buildEmptyList() {
    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .58,
          child: EmptyState(
            mascot: const Capybara(
              mood: CapyMood.neutral,
              size: Size(130, 117),
            ),
            title: 'No chats yet',
            subtitle: 'Add friends to start chatting.',
            action: FilledButton.icon(
              onPressed: () => showAddFriendSheet(context, ref),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add a Friend'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoResultsList(String message) {
    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .45,
          child: Center(child: _NoResultsLine(message)),
        ),
      ],
    );
  }

  void _showNewChatSheet(BuildContext context, WidgetRef ref) {
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => AppSheetChrome(
        title: 'New chat',
        children: [
          SheetActionRow(
            icon: Icons.person_add_outlined,
            label: 'Add a friend',
            onTap: () {
              Navigator.of(sheetContext).pop();
              showAddFriendSheet(context, ref);
            },
          ),
          SheetActionRow(
            icon: Icons.group_add_outlined,
            label: 'New group',
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.push(AppRoutes.createGroup);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openChat(String otherUserId) async {
    try {
      final conversation = await ref
          .read(messageRepositoryProvider)
          .getOrCreateDirectConversation(otherUserId);
      if (mounted) {
        context.push(AppRoutes.chat, extra: conversation);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat is not ready yet. Try again in a moment.'),
        ),
      );
    }
  }
}

class _RequestsButton extends StatelessWidget {
  const _RequestsButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = count > 0 ? '$count pending requests' : 'No pending requests';
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: 48,
        height: 48,
        child: IconButton(
          onPressed: onPressed,
          tooltip: 'Friend requests',
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.person_add_alt_1_outlined),
              Positioned(top: -7, right: -8, child: AppBadge(count: count)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileButton extends StatefulWidget {
  const _ProfileButton({
    this.url,
    required this.initials,
    required this.onPressed,
  });

  final String? url;
  final String initials;
  final VoidCallback onPressed;

  @override
  State<_ProfileButton> createState() => _ProfileButtonState();
}

class _ProfileButtonState extends State<_ProfileButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      button: true,
      label: 'Your profile',
      child: SizedBox(
        width: 56,
        height: 48,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onPressed,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            child: Center(
              child: AnimatedContainer(
                duration: _homeMotionDuration(
                  context,
                  WarmPopTokens.motionFast,
                ),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _pressed ? t.accent : t.bg,
                    width: _pressed ? 1.5 : 0,
                  ),
                ),
                child: AppAvatar(
                  url: widget.url,
                  initials: widget.initials,
                  radius: 18,
                  accentSoft: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineBannerSlot extends StatelessWidget {
  const _OfflineBannerSlot({required this.visible, required this.onRetry});

  final bool visible;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _homeMotionDuration(context, WarmPopTokens.motionBase),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      child: visible
          ? Padding(
              key: const ValueKey('home-offline-banner'),
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: _OfflineBanner(onRetry: onRetry),
            )
          : const SizedBox.shrink(key: ValueKey('home-online-space')),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      container: true,
      label: "You're offline — messages will send when you're back.",
      child: Material(
        color: t.accentSoft,
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
          onTap: onRetry,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 16,
                  color: t.accentPressed,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "You're offline — messages will send when you're back.",
                    style: TextStyle(fontSize: 12, color: t.ink),
                  ),
                ),
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: t.ink,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackupBannerSlot extends StatelessWidget {
  const _BackupBannerSlot({
    required this.upgrade,
    required this.visible,
    required this.onTap,
    required this.onDismiss,
  });

  final bool upgrade;
  final bool visible;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: _homeMotionDuration(context, WarmPopTokens.motionBase),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      child: visible
          ? Padding(
              key: ValueKey(
                  upgrade ? 'home-upgrade-banner' : 'home-backup-banner'),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: upgrade
                  ? _BackupBanner(
                      copy: _BackupBanner.upgradeCopy,
                      dismissLabel: 'Dismiss reminder',
                      onTap: onTap,
                      onDismiss: onDismiss,
                    )
                  : _BackupBanner(onTap: onTap, onDismiss: onDismiss),
            )
          : const SizedBox.shrink(key: ValueKey('home-no-backup-banner')),
    );
  }
}

class _BackupBanner extends StatelessWidget {
  const _BackupBanner({
    required this.onTap,
    required this.onDismiss,
    this.copy = setupCopy,
    this.dismissLabel = 'Dismiss backup reminder',
  });

  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final String copy;
  final String dismissLabel;

  static const setupCopy =
      'Back up your encryption key so you can restore your messages after a reinstall. Tap to set up.';
  static const upgradeCopy =
      "Your backup uses a short PIN that's easy to crack. Tap to get a recovery key.";

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      container: true,
      label: copy,
      child: Material(
        color: t.accentSoft,
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 5, 4, 5),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: t.accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    copy,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                Semantics(
                  button: true,
                  label: dismissLabel,
                  child: IconButton(
                    onPressed: onDismiss,
                    tooltip: dismissLabel,
                    icon: Icon(Icons.close, color: t.inkSoft, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({
    super.key,
    required this.title,
    required this.count,
  });

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.27,
              letterSpacing: .1,
              color: t.inkFaint,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: t.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoResultsLine extends StatelessWidget {
  const _NoResultsLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: context.t.inkFaint),
      ),
    );
  }
}

class _HomeSkeletonTile extends StatelessWidget {
  const _HomeSkeletonTile({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final nameWidths = const [88.0, 118.0, 70.0, 102.0];
    final previewWidths = const [158.0, 120.0, 136.0, 104.0];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: context.t.surface,
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Skeleton(
                height: 40,
                width: 40,
                radius: 20,
                duration: Duration(milliseconds: 1400),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(
                      height: 12,
                      width: nameWidths[index],
                      radius: 6,
                      duration: const Duration(milliseconds: 1400),
                    ),
                    const SizedBox(height: 7),
                    Skeleton(
                      height: 10,
                      width: previewWidths[index],
                      radius: 5,
                      duration: const Duration(milliseconds: 1400),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeFab extends StatefulWidget {
  const _HomeFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_HomeFab> createState() => _HomeFabState();
}

class _HomeFabState extends State<_HomeFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? .96 : 1,
        duration: _homeMotionDuration(context, WarmPopTokens.motionFast),
        child: FloatingActionButton(
          heroTag: 'fab_main',
          onPressed: widget.onPressed,
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          tooltip: 'New chat',
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
          ),
          child: const Icon(Icons.add_comment_outlined),
        ),
      ),
    );
  }
}

class _FriendsTile extends StatelessWidget {
  const _FriendsTile({super.key, required this.entity, required this.onTap});

  final Friendship entity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final friend = entity.friend;
    final online = friend.isOnline;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ChatTile(
        key: ValueKey('chat-tile-friend-${friend.id}'),
        title: entity.displayName,
        subtitle: online ? 'Online' : 'Tap to start chatting',
        subtitleColor: online ? _accessibleOnlineTextColor(context) : null,
        avatarUrl: friend.avatarUrl,
        isOnline: online,
        semanticSubtitle: online ? 'Online' : 'Tap to start chatting',
        onTap: onTap,
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({super.key, required this.conv});

  final Conversation conv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // P7 (spec §3): no stored preview string exists anymore — the tile's
    // subtitle is DERIVED (newest row via messageBodyProvider; media/system
    // labels are constants; empty conversation → this fallback). Never a
    // durable plaintext fallback.
    // #74: pointer-DOWN (not tap) kicks the predecrypt — the ~250ms open
    // transition then hides the decrypt work. Listener, NOT GestureDetector
    // onTapDown: a parent tap recognizer never WINS the arena (the tile's
    // own tap does), so its onTapDown would never fire. Raw pointer events
    // dispatch regardless of the arena. A failed/aborted press just warms
    // cache early; the method swallows its own errors.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Listener(
        onPointerDown: (_) {
          debugPrint('[Msg] TAPDOWN fired conv=${conv.id}');
          unawaited(
            ref.read(messageRepositoryProvider).predecryptConversation(conv.id),
          );
        },
        child: _ConversationTileContent(conv: conv),
      ),
    );
  }
}

class _ConversationTileContent extends ConsumerWidget {
  const _ConversationTileContent({required this.conv});

  final Conversation conv;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const fallback = 'Tap to open chat';
    final authState = ref.watch(authProvider).valueOrNull;
    final currentUserId = authState is AuthAuthenticated
        ? authState.user.id
        : null;
    final unread = conv.unreadCount > 0;
    final previewStyle = TextStyle(
      fontSize: 13,
      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
      color: unread ? context.t.ink : context.t.inkSoft,
    );
    final preview = conv.isGroup
        ? _GroupConversationPreview(
            conversation: conv,
            currentUserId: currentUserId,
            fallback: fallback,
            style: previewStyle,
          )
        : ConversationPreviewText(
            conversation: conv,
            fallback: fallback,
            style: previewStyle,
          );

    return ChatTile(
      key: ValueKey('chat-tile-conversation-${conv.id}'),
      title: conv.displayName,
      subtitle: fallback,
      subtitleWidget: preview,
      semanticSubtitle: fallback,
      time: conv.lastMessageAt != null
          ? _formatTime(conv.lastMessageAt!)
          : null,
      unreadCount: conv.unreadCount,
      avatarUrl: conv.isGroup ? conv.iconUrl : conv.avatarUrl,
      isGroup: conv.isGroup,
      isPinned: conv.isPinned,
      isOnline: conv.isGroup ? null : conv.otherUser?.isOnline,
      onTap: () => context.push(AppRoutes.chat, extra: conv),
      onLongPress: () => _showConversationMenu(context, ref),
    );
  }

  void _showConversationMenu(BuildContext context, WidgetRef ref) {
    const fallback = 'Tap to open chat';
    final actions = <ConversationMenuAction>[
      ConversationMenuAction(
        label: 'Pin conversation',
        icon: conv.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
        trailing: conv.isPinned ? 'On' : 'Off',
        semanticsLabel: conv.isPinned
            ? 'Unpin conversation'
            : 'Pin conversation',
        callback: () => unawaited(_togglePinned(context, ref)),
      ),
      if (conv.unreadCount > 0)
        ConversationMenuAction(
          label: 'Mark as read',
          icon: Icons.check_circle_outline,
          semanticsLabel: 'Mark conversation as read',
          callback: () => unawaited(_markRead(context, ref)),
        ),
      ConversationMenuAction(
        label: 'Conversation info',
        icon: Icons.info_outline,
        semanticsLabel: 'Open conversation info',
        callback: () => _openConversationInfo(context),
      ),
    ];
    showConversationMenu(
      context: context,
      ref: ref,
      conversation: conv,
      preview: ConversationPreviewText(conversation: conv, fallback: fallback),
      actions: actions,
    );
  }

  Future<void> _togglePinned(BuildContext context, WidgetRef ref) async {
    final pinned = !conv.isPinned;
    try {
      await ref
          .read(appDatabaseProvider)
          .conversationsDao
          .setPinned(conv.id, pinned);
      ref.invalidate(conversationsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(pinned ? 'Pinned' : 'Unpinned')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Couldn’t update pin.')));
    }
  }

  Future<void> _markRead(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(messageRepositoryProvider).markConversationRead(conv.id);
      ref.invalidate(conversationsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked as read')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t mark chat as read.')),
      );
    }
  }

  void _openConversationInfo(BuildContext context) {
    if (conv.isGroup) {
      context.push(AppRoutes.groupSettings, extra: conv);
    } else if (conv.otherUser != null) {
      context.push(AppRoutes.viewProfile, extra: conv.otherUser);
    }
  }

  static String _formatTime(DateTime dateTime) {
    final now = DateTime.now().toLocal();
    final local = dateTime.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(local.year, local.month, local.day);
    final dayDelta = today.difference(date).inDays;
    if (dayDelta == 0) return DateFormat('HH:mm').format(local);
    if (dayDelta == 1) return 'Yesterday';
    if (dayDelta > 1 && dayDelta < 7) return DateFormat('EEE').format(local);
    if (local.year != now.year) return DateFormat('dd/MM/yyyy').format(local);
    return DateFormat('dd/MM').format(local);
  }
}

class _GroupConversationPreview extends ConsumerWidget {
  const _GroupConversationPreview({
    required this.conversation,
    required this.currentUserId,
    required this.fallback,
    required this.style,
  });

  final Conversation conversation;
  final String? currentUserId;
  final String fallback;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastMessage = ref
        .watch(conversationLastMessageProvider(conversation.id))
        .valueOrNull;
    final senderId = lastMessage?.type == 'text' ? lastMessage!.senderId : '';
    final lookupId = senderId == currentUserId ? '' : senderId;
    final senderName = ref
        .watch(_groupSenderNameProvider(lookupId))
        .valueOrNull;
    final prefix = senderId.isEmpty
        ? null
        : senderId == currentUserId
        ? 'you'
        : (senderName ?? 'Unknown');

    return Row(
      children: [
        if (prefix != null) ...[
          Flexible(
            child: Text(
              '$prefix:',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(
                color: context.t.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: ConversationPreviewText(
            conversation: conversation,
            fallback: fallback,
            style: style,
          ),
        ),
      ],
    );
  }
}

String _initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.substring(0, 1).toUpperCase();
}

Duration _homeMotionDuration(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

Color _accessibleOnlineTextColor(BuildContext context) {
  final t = context.t;
  final foreground = t.success.computeLuminance();
  final background = t.surface.computeLuminance();
  final lighter = foreground > background ? foreground : background;
  final darker = foreground > background ? background : foreground;
  final ratio = (lighter + 0.05) / (darker + 0.05);
  return ratio >= 4.5 ? t.success : t.inkSoft;
}
