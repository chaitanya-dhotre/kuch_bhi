import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../domain/entities/friend_request.dart';
import '../../../domain/entities/group_invite.dart';
import '../../../features/mascot/capybara.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../home/screens/add_friend_screen.dart';
import '../providers/friend_request_provider.dart';
import '../widgets/group_invite_card.dart';
import '../widgets/request_card.dart';

const _offlineCopy = "You're offline — actions are available when you're back.";

class FriendRequestsScreen extends ConsumerStatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  ConsumerState<FriendRequestsScreen> createState() =>
      _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends ConsumerState<FriendRequestsScreen> {
  final _busyIds = <String>{};
  final _busyActions = <String, RequestAction>{};
  final _hiddenIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final requests = ref.watch(incomingRequestsProvider);
    final invites = ref.watch(incomingGroupInvitesProvider);
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        surfaceTintColor: t.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Semantics(
          header: true,
          child: Text(
            'Requests',
            style: TextStyle(
              color: t.ink,
              fontSize: 20,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          _OfflineStrip(visible: !online),
          Expanded(
            child: SafeArea(
              top: false,
              child: RefreshIndicator(
                color: t.accent,
                onRefresh: _refreshAll,
                child: _buildList(
                  context,
                  requests: requests,
                  invites: invites,
                  online: online,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context, {
    required AsyncValue<List<FriendRequest>> requests,
    required AsyncValue<List<GroupInvite>> invites,
    required bool online,
  }) {
    final friendRows = _visibleFriends(requests.valueOrNull);
    final inviteRows = _visibleInvites(invites.valueOrNull);
    final hasRows = friendRows.isNotEmpty || inviteRows.isNotEmpty;
    final bothFailed = requests.hasError && invites.hasError && !hasRows;
    if (bothFailed) {
      return _scrollableState(
        context,
        EmptyState(
          mascot: const Capybara(mood: CapyMood.sleepy, size: Size(120, 106)),
          title: "Couldn't load requests.",
          subtitle: 'Check your connection and try again.',
          action: AppButton(
            onPressed: () => unawaited(
              _retryFailed(retryRequests: true, retryInvites: true),
            ),
            child: const Text('Retry'),
          ),
        ),
      );
    }

    final partialFailure = requests.hasError || invites.hasError;
    final sourceLoading =
        (requests.isLoading && requests.valueOrNull == null) ||
        (invites.isLoading && invites.valueOrNull == null);
    final settled =
        !requests.isLoading &&
        !invites.isLoading &&
        !requests.hasError &&
        !invites.hasError;
    final children = <Widget>[];

    if (partialFailure) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Semantics(
            container: true,
            label: "Some requests didn't load.",
            child: StatusBanner(
              message: "Some requests didn't load.",
              leading: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: context.t.accent,
              ),
              onRetry: () => unawaited(
                _retryFailed(
                  retryRequests: requests.hasError,
                  retryInvites: invites.hasError,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (friendRows.isNotEmpty) {
      children.addAll(
        friendRows.map(
          (request) => RequestCard(
            request: request,
            locked: _busyIds.contains(_requestKey(request.id)),
            offline: !online,
            busyAction: _busyActions[_requestKey(request.id)],
            onAccept: () =>
                unawaited(_handleFriendAction(request, RequestAction.accept)),
            onDecline: () =>
                unawaited(_handleFriendAction(request, RequestAction.decline)),
          ),
        ),
      );
    }

    if (inviteRows.isNotEmpty) {
      children.add(SectionHeader('Group invites', count: inviteRows.length));
      children.addAll(
        inviteRows.map(
          (invite) => GroupInviteCard(
            invite: invite,
            locked: _busyIds.contains(_inviteKey(invite.id)),
            offline: !online,
            busyAction: _busyActions[_inviteKey(invite.id)],
            onAccept: () =>
                unawaited(_handleInviteAction(invite, RequestAction.accept)),
            onDecline: () =>
                unawaited(_handleInviteAction(invite, RequestAction.decline)),
          ),
        ),
      );
    }

    if (sourceLoading) {
      final skeletonCount = hasRows ? 1 : 3;
      children.addAll(
        List<Widget>.generate(
          skeletonCount,
          (_) => const _RequestSkeletonCard(),
        ),
      );
    } else if (!hasRows && settled && !partialFailure) {
      children.add(_emptyState(context));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
      children: children,
    );
  }

  Widget _scrollableState(BuildContext context, Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * .58, child: child),
      ],
    );
  }

  Widget _emptyState(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .58,
      child: EmptyState(
        mascot: const Capybara(mood: CapyMood.neutral, size: Size(120, 106)),
        title: 'No pending requests',
        subtitle: 'Friend requests and group invites will show up here.',
        action: AppButton(
          onPressed: _openAddFriend,
          child: const Text('Add a Friend'),
        ),
      ),
    );
  }

  List<FriendRequest> _visibleFriends(List<FriendRequest>? rows) {
    final visible = (rows ?? const <FriendRequest>[])
        .where((row) => !_hiddenIds.contains(_requestKey(row.id)))
        .toList();
    visible.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return visible;
  }

  List<GroupInvite> _visibleInvites(List<GroupInvite>? rows) {
    final visible = (rows ?? const <GroupInvite>[])
        .where((row) => !_hiddenIds.contains(_inviteKey(row.id)))
        .toList();
    visible.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return visible;
  }

  Future<void> _refreshAll() async {
    ref.invalidate(incomingRequestsProvider);
    ref.invalidate(incomingGroupInvitesProvider);
    try {
      await Future.wait<void>([
        ref.read(incomingRequestsProvider.future).then<void>((_) {}),
        ref.read(incomingGroupInvitesProvider.future).then<void>((_) {}),
      ]);
    } catch (_) {
      // The source-specific error state is the durable recovery surface.
    }
  }

  Future<void> _retryFailed({
    required bool retryRequests,
    required bool retryInvites,
  }) async {
    final futures = <Future<void>>[];
    if (retryRequests) {
      ref.invalidate(incomingRequestsProvider);
      futures.add(ref.read(incomingRequestsProvider.future).then<void>((_) {}));
    }
    if (retryInvites) {
      ref.invalidate(incomingGroupInvitesProvider);
      futures.add(
        ref.read(incomingGroupInvitesProvider.future).then<void>((_) {}),
      );
    }
    try {
      await Future.wait(futures);
    } catch (_) {
      // Leave the source error visible for another retry.
    }
  }

  Future<void> _handleFriendAction(
    FriendRequest request,
    RequestAction action,
  ) async {
    final key = _requestKey(request.id);
    if (_busyIds.contains(key) || !mounted) return;
    final name = _safeName(request.fromUser.displayName);
    _beginAction(key, action);

    try {
      final notifier = ref.read(incomingRequestsProvider.notifier);
      if (action == RequestAction.accept) {
        await notifier.accept(request.id);
      } else {
        await notifier.decline(request.id);
      }
      if (!mounted) return;
      setState(() {
        _busyIds.remove(key);
        _busyActions.remove(key);
        _hiddenIds.add(key);
      });
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          '$name removed',
          Directionality.of(context),
        ),
      );
      if (action == RequestAction.accept) {
        showToast(context, 'Friend added');
      }
    } catch (_) {
      if (!mounted) return;
      _endAction(key);
      showToast(context, "Couldn't update. Try again.", error: true);
    }
  }

  Future<void> _handleInviteAction(
    GroupInvite invite,
    RequestAction action,
  ) async {
    final key = _inviteKey(invite.id);
    if (_busyIds.contains(key) || !mounted) return;
    final name = _safeGroupName(invite.conversationName);
    _beginAction(key, action);

    try {
      final notifier = ref.read(incomingGroupInvitesProvider.notifier);
      if (action == RequestAction.accept) {
        await notifier.accept(invite.id);
      } else {
        await notifier.decline(invite.id);
      }
      if (!mounted) return;
      setState(() {
        _busyIds.remove(key);
        _busyActions.remove(key);
        _hiddenIds.add(key);
      });
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          '$name removed',
          Directionality.of(context),
        ),
      );
      if (action == RequestAction.accept) {
        showToast(context, 'Joined $name');
      }
    } catch (_) {
      if (!mounted) return;
      _endAction(key);
      showToast(context, "Couldn't update. Try again.", error: true);
    }
  }

  void _beginAction(String key, RequestAction action) {
    setState(() {
      _busyIds.add(key);
      _busyActions[key] = action;
    });
  }

  void _endAction(String key) {
    setState(() {
      _busyIds.remove(key);
      _busyActions.remove(key);
    });
  }

  void _openAddFriend() => showAddFriendSheet(context, ref);

  static String _requestKey(String id) => 'friend:$id';

  static String _inviteKey(String id) => 'invite:$id';

  static String _safeName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Unknown' : trimmed;
  }

  static String _safeGroupName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Group' : trimmed;
  }
}

class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return AnimatedSwitcher(
      duration: _motionDuration(context, WarmPopTokens.motionBase),
      child: visible
          ? Semantics(
              key: const ValueKey('requests-offline-strip'),
              container: true,
              label: _offlineCopy,
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
                        _offlineCopy,
                        style: TextStyle(fontSize: 13, color: t.ink),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('requests-online-space')),
    );
  }
}

class _RequestSkeletonCard extends StatelessWidget {
  const _RequestSkeletonCard();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    const duration = Duration(milliseconds: 1400);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
          boxShadow: WarmPopTokens.cardShadow(t.shadow),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  const Skeleton(
                    width: 52,
                    height: 52,
                    radius: 26,
                    duration: duration,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Skeleton(
                          width: 144,
                          height: 14,
                          radius: 7,
                          duration: duration,
                        ),
                        const SizedBox(height: 8),
                        const Skeleton(
                          width: 96,
                          height: 12,
                          radius: 6,
                          duration: duration,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Skeleton(
                      height: 48,
                      radius: WarmPopTokens.radiusMd,
                      duration: duration,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Skeleton(
                      height: 48,
                      radius: WarmPopTokens.radiusMd,
                      duration: duration,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Duration _motionDuration(BuildContext context, Duration duration) {
  return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
