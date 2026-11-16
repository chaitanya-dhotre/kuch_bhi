import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/change_motion.dart';
import '../../../core/widgets/chat_tile.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_app_bar.dart';
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
import '../../../features/mascot/capy_spots.dart';
import '../../../features/mascot/offline_bath_banner.dart';
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
  // B2: the new-chat button hides while the list scrolls down.
  bool _fabHidden = false;
  bool _backupBannerVisible = false;
  bool _backupBannerDismissed = false;
  bool _upgradeBannerDismissed = false;
  String? _openingFriendId;
  double? _searchOriginOffset;

  // Motion D2: the last chat order, and each id's slot before a reorder.
  List<String> _order = const [];
  Map<String, int> _prevSlot = const {};
  int _reorderGen = 0;

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

  bool _handleScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    var hidden = _fabHidden;
    if (n is UserScrollNotification) {
      // A drag down starts at the top, so this one must not check the edge.
      if (n.direction == ScrollDirection.reverse) hidden = true;
      if (n.direction == ScrollDirection.forward) hidden = false;
    } else if (n.metrics.pixels <= n.metrics.minScrollExtent) {
      hidden = false;
    }
    if (hidden != _fabHidden) setState(() => _fabHidden = hidden);
    return false;
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
    final showUpgradeBanner =
        !showBackupBanner &&
        !_upgradeBannerDismissed &&
        ref.watch(showBackupUpgradeBannerProvider).valueOrNull == true;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: t.bg,
        surfaceTintColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(AppConstants.appName, style: pageTitleStyle(context)),
        actions: [
          _RequestsButton(
            count: pendingCount,
            onPressed: () => context.push(AppRoutes.friendRequests),
          ),
          _ProfileButton(
            url: user?.avatarUrl,
            initials: initialsOf(user?.displayName ?? 'K'),
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
      body: Column(
        children: [
          _BackupBannerSlot(
            upgrade: showUpgradeBanner,
            visible: showBackupBanner || showUpgradeBanner,
            onTap: () => context.push(
              showUpgradeBanner
                  ? AppRoutes.backupPinChange
                  : AppRoutes.backupPinSetup,
            ),
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
          OfflineBathBanner(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            tapToRetry: true,
            onRetry: () => unawaited(_refreshHome()),
          ),
          Expanded(
            child: RefreshIndicator(
              color: t.accent,
              onRefresh: _refreshHome,
              child: NotificationListener<ScrollNotification>(
                onNotification: _handleScroll,
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
          ),
        ],
      ),
      floatingActionButton: _searchFocused
          ? null
          : _HomeFab(
              hidden: _fabHidden,
              onPressed: () => _showNewChatSheet(context, ref),
            ),
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
    await ref
        .read(appDatabaseProvider)
        .settingsDao
        .setSetting(
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
    // A7: one group, one breath for every placeholder on Home.
    return SkeletonGroup(
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Skeleton(width: 56, height: 12, radius: 6),
            ),
          ),
          for (var index = 0; index < 4; index++)
            _HomeSkeletonTile(index: index),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .58,
          child: EmptyState(
            mascot: capySpot('X3').build(),
            title: 'Couldn’t load your chats',
            subtitle: kConnectionRetryCopy,
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

    // D2: a new order (not a search filter) slides the rows on screen.
    final ids = [for (final c in filteredConversations) c.id];
    if (!listEquals(ids, _order)) {
      if (query.isEmpty && _order.isNotEmpty) {
        _prevSlot = {for (var i = 0; i < _order.length; i++) _order[i]: i};
        _reorderGen++;
        // Only this frame's rows read it: one scrolled in later never fades.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _prevSlot = const {},
        );
      } else {
        _prevSlot = const {};
      }
      _order = ids;
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
        filteredConversations.indexed.map(
          (e) => ReorderSlide(
            key: ValueKey('conversation-${e.$2.id}'),
            slot: e.$1,
            previousSlot: _prevSlot[e.$2.id],
            generation: _reorderGen,
            child: _ConversationTile(conv: e.$2),
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
            opening: _openingFriendId == friendship.friend.id,
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
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: children.length,
      itemBuilder: (_, index) => children[index],
      // D2: a moved row keeps its element, so it can slide from its old slot.
      findChildIndexCallback: (key) {
        final i = children.indexWhere((w) => w.key == key);
        return i < 0 ? null : i;
      },
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
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .58,
          child: EmptyState(
            mascot: capySpot('X2').build(),
            title: 'No chats yet',
            subtitle: 'Add friends to start chatting.',
            action: FilledButton.icon(
              onPressed: () => showAddFriendSheet(context, ref),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text(kAddFriendCtaLabel),
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
      padding: const EdgeInsets.only(bottom: 88),
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
    if (_openingFriendId != null) return;
    setState(() => _openingFriendId = otherUserId);
    try {
      // Only the wait is bounded: a slow sync keeps running and lands in
      // Drift, so the next tap finds the chat locally.
      final conversation = await ref
          .read(messageRepositoryProvider)
          .getOrCreateDirectConversation(otherUserId)
          .timeout(const Duration(seconds: 8));
      if (mounted) {
        context.push(AppRoutes.chat, extra: conversation);
      }
    } catch (_) {
      if (!mounted) return;
      showToast(
        context,
        'Chat is not ready yet. Try again in a moment.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _openingFriendId = null);
    }
  }
}

class _RequestsButton extends StatelessWidget {
  const _RequestsButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = count > 0
        ? '$count pending requests'
        : kNoPendingRequestsCopy;
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
              Positioned(
                top: -7,
                right: -8,
                // B6: a new request pops the count on springSoft.
                child: PopOnChange(
                  value: count,
                  child: AppBadge(count: count),
                ),
              ),
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
                duration: motionOf(context, WarmPopTokens.motionFast),
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _pressed ? t.line : t.bg,
                    width: _pressed ? 1.5 : 0,
                  ),
                ),
                child: AppAvatar(
                  url: widget.url,
                  initials: widget.initials,
                  radius: 18,
                ),
              ),
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
      duration: motionOf(context, WarmPopTokens.motionBase),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topCenter,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      child: visible
          ? Padding(
              key: ValueKey(
                upgrade ? 'home-upgrade-banner' : 'home-backup-banner',
              ),
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
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: t.accentText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    copy,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                height: 14 / 11,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 13,
          height: 18 / 13,
          color: context.t.inkFaint,
        ),
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
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Skeleton(height: 40, width: 40, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Skeleton(height: 12, width: nameWidths[index], radius: 6),
                    const SizedBox(height: 8),
                    Skeleton(
                      height: 10,
                      width: previewWidths[index],
                      radius: 5,
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
  const _HomeFab({required this.onPressed, this.hidden = false});

  final VoidCallback onPressed;

  /// B2: slid 16 dp down and faded out (motionPress), back on motionFast.
  final bool hidden;

  @override
  State<_HomeFab> createState() => _HomeFabState();
}

class _HomeFabState extends State<_HomeFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final hidden = widget.hidden;
    final duration = motionOf(
      context,
      hidden ? WarmPopTokens.motionPress : WarmPopTokens.motionFast,
    );
    final curve = hidden ? WarmPopTokens.curveExit : WarmPopTokens.curveEnter;
    final fab = Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? .96 : 1,
        duration: motionOf(context, WarmPopTokens.motionFast),
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
    return IgnorePointer(
      ignoring: hidden,
      child: ExcludeSemantics(
        excluding: hidden,
        child: AnimatedSlide(
          offset: Offset(0, hidden ? 16 / 56 : 0),
          duration: duration,
          curve: curve,
          child: AnimatedOpacity(
            opacity: hidden ? 0 : 1,
            duration: duration,
            curve: curve,
            child: fab,
          ),
        ),
      ),
    );
  }
}

class _FriendsTile extends StatelessWidget {
  const _FriendsTile({
    super.key,
    required this.entity,
    required this.onTap,
    this.opening = false,
  });

  final Friendship entity;
  final VoidCallback onTap;

  /// The chat is being fetched: the tile says so and ignores taps.
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final friend = entity.friend;
    final online = friend.isOnline;
    final subtitle = opening
        ? 'Opening chat…'
        : online
        ? 'Online'
        : 'Tap to start chatting';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ChatTile(
        key: ValueKey('chat-tile-friend-${friend.id}'),
        title: entity.displayName,
        subtitle: subtitle,
        subtitleColor: online && !opening
            ? _accessibleOnlineTextColor(context)
            : null,
        avatarUrl: friend.avatarUrl,
        isOnline: online,
        semanticSubtitle: subtitle,
        onTap: opening ? null : onTap,
      ),
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
    // #74: pointer-DOWN (not tap) kicks the predecrypt — the ~250ms open
    // transition then hides the decrypt work. Listener, NOT GestureDetector
    // onTapDown: a parent tap recognizer never WINS the arena (the tile's
    // own tap does), so its onTapDown would never fire. Raw pointer events
    // dispatch regardless of the arena. A failed/aborted press just warms
    // cache early; the method swallows its own errors.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
      heroId: conv.id,
      flashKey: conv.lastMessageAt,
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
      showToast(context, pinned ? 'Pinned' : 'Unpinned');
    } catch (_) {
      if (!context.mounted) return;
      showToast(context, 'Couldn’t update pin.', error: true);
    }
  }

  Future<void> _markRead(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(messageRepositoryProvider).markConversationRead(conv.id);
      ref.invalidate(conversationsProvider);
      if (!context.mounted) return;
      showToast(context, 'Marked as read');
    } catch (_) {
      if (!context.mounted) return;
      showToast(context, 'Couldn’t mark chat as read.', error: true);
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
    final senderId = kTextLikeTypes.contains(lastMessage?.type)
        ? lastMessage!.senderId
        : '';
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
              // Chat calm D3: grey, not marigold.
              style: style.copyWith(
                color: context.t.inkSoft,
                fontWeight: FontWeight.w600,
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

Color _accessibleOnlineTextColor(BuildContext context) {
  final t = context.t;
  final foreground = t.success.computeLuminance();
  final background = t.surface.computeLuminance();
  final lighter = foreground > background ? foreground : background;
  final darker = foreground > background ? background : foreground;
  final ratio = (lighter + 0.05) / (darker + 0.05);
  return ratio >= 4.5 ? t.success : t.inkSoft;
}
