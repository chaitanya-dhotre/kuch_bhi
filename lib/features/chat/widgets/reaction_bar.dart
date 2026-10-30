import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pocketbase_client.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../data/local/database/app_database.dart';
import '../../../data/local/database/tables/app_settings_table.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../message_offline_policy.dart';
import '../providers/chat_provider.dart';
import '../../../core/theme/tokens.dart';
import 'reaction_picker.dart';

// shortcut: one small list per message seen this run, never evicted; move
// reactions into drift if this ever matters.
final _lastReactions = <String, List<ReactionGroup>>{};

class ReactionBar extends ConsumerWidget {
  const ReactionBar({
    super.key,
    required this.messageServerId,
    required this.isMine,
  });

  final String messageServerId;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Coming back online reads again.
    ref.listen(isOnlineProvider, (prev, next) {
      if (prev?.value == false && next.value == true) {
        ref.invalidate(reactionsProvider(messageServerId));
      }
    });
    final groupsAsync = ref.watch(reactionsProvider(messageServerId));
    final isOnline = ref.watch(isOnlineProvider).value ?? true;
    final reactionsEnabled = isMessageActionEnabled(
      MessageAction.react,
      isOnline: isOnline,
    );

    // A reconnect re-reads: keep the chips up meanwhile, no blink.
    return groupsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (read) {
        // An offline read answers [] (the repository swallows the failure):
        // that is not "no reactions", so keep the last known set.
        final groups = !isOnline && read.isEmpty
            ? _lastReactions[messageServerId] ?? read
            : _lastReactions[messageServerId] = read;
        if (groups.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(
            left: isMine ? 0 : 12,
            right: isMine ? 12 : 0,
            top: 2,
            bottom: 4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IgnorePointer(
                ignoring: !reactionsEnabled,
                child: Opacity(
                  opacity: reactionsEnabled ? 1 : 0.38,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    alignment: isMine ? WrapAlignment.end : WrapAlignment.start,
                    children: [
                      ...groups.map(
                        (g) => _ReactionChip(
                          group: g,
                          messageServerId: messageServerId,
                          isMine: isMine,
                        ),
                      ),
                      _ReactionAddChip(messageServerId: messageServerId),
                    ],
                  ),
                ),
              ),
              if (!reactionsEnabled)
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(kOfflineActionHint),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReactionChip extends ConsumerWidget {
  const _ReactionChip({
    required this.group,
    required this.messageServerId,
    required this.isMine,
  });

  final ReactionGroup group;
  final String messageServerId;
  final bool isMine; // isMine = message is mine (bubble side)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Colors that work in both light and dark, on both bubble sides
    final bg = group.isMine
        ? context.t.accent.withValues(alpha: 0.15)
        : isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.07);

    final border = group.isMine
        ? context.t.accent.withValues(alpha: 0.5)
        : Colors.transparent;

    return GestureDetector(
      key: ValueKey('reaction-chip-$messageServerId-${group.emoji}'),
      onTap: () async {
        final repo = ref.read(messageRepositoryProvider);
        if (group.isMine && group.reactionId != null) {
          await repo.removeReaction(group.reactionId!);
        } else {
          await repo.addReaction(messageServerId, group.emoji);
        }
        ref.invalidate(reactionsProvider(messageServerId));
      },
      onLongPress: () => _showReactionDetail(context, ref),
      child: Semantics(
        button: true,
        label: '${group.emoji} reaction, ${group.count}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Text(
            '${group.emoji} ${group.count}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }

  // C2: opens at once; the sheet loads who reacted itself.
  void _showReactionDetail(BuildContext context, WidgetRef ref) {
    showAppSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _ReactionDetailSheet(
        messageServerId: messageServerId,
        group: group,
      ),
    );
  }
}

typedef Reactor = ({
  String name,
  String userId,
  String reactionId,
  String? avatarUrl,
});

/// Who reacted to a message with one emoji, keyed by (message, emoji).
/// Decision 5: the PocketBase query stays here for now (K2); the 8s bound is
/// on the `getList` call only.
final reactionDetailProvider = FutureProvider.autoDispose
    .family<({String myId, List<Reactor> reactors}), (String, String)>((
      ref,
      key,
    ) async {
      final (messageServerId, emoji) = key;
      final pb = ref.read(pocketbaseClientProvider).pb;
      final db = ref.read(appDatabaseProvider);
      final myId =
          await db.settingsDao.getSetting(AppSettingsKeys.currentUserId) ?? '';

      final reactors = <Reactor>[];
      final res = await pb
          .collection('reactions')
          .getList(
            filter: 'message_id="$messageServerId"&&emoji="$emoji"',
            expand: 'user_id',
            perPage: 50,
          )
          .timeout(const Duration(seconds: 8));
      for (final r in res.items) {
        final uid = r.getStringValue('user_id');
        final localUser = await db.usersDao.getUserById(uid);
        // user_id is a single relation: it expands to one object, which a
        // dot path reads ('' when the rule hides it).
        final expandedName = r.getStringValue('expand.user_id.display_name');
        final name = expandedName.isNotEmpty
            ? expandedName
            : localUser?.displayName.isNotEmpty == true
            ? localUser!.displayName
            : 'Unknown';
        final cachedAvatar = localUser?.avatarUrl;
        final expandedAvatar = r.getStringValue('expand.user_id.avatar');
        final avatarUrl = cachedAvatar?.isNotEmpty == true
            ? cachedAvatar
            : _avatarUrl(pb.baseURL, uid, expandedAvatar);
        reactors.add((
          name: name,
          userId: uid,
          reactionId: r.id,
          avatarUrl: avatarUrl,
        ));
      }
      return (myId: myId, reactors: reactors);
    });

class _ReactionDetailSheet extends ConsumerWidget {
  const _ReactionDetailSheet({
    required this.messageServerId,
    required this.group,
  });

  final String messageServerId;
  final ReactionGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.t;
    final key = (messageServerId, group.emoji);
    final async = ref.watch(reactionDetailProvider(key));
    final online = isMessageActionEnabled(
      MessageAction.react,
      isOnline: ref.watch(isOnlineProvider).value ?? true,
    );
    final caption = TextStyle(fontSize: 13, height: 18 / 13, color: t.inkSoft);

    final Widget body = switch (async) {
      AsyncData(:final value) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final r in value.reactors)
            _reactorRow(context, ref, r, isMe: r.userId == value.myId,
                online: online),
          if (!online && value.reactors.any((r) => r.userId == value.myId))
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(kOfflineActionHint, style: caption),
            ),
        ],
      ),
      AsyncError() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: StatusBanner(
          message: "Couldn't load reactions.",
          onRetry: () => ref.invalidate(reactionDetailProvider(key)),
        ),
      ),
      _ => ListView(
        key: const Key('reaction-detail-loading'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (var i = 0; i < 3; i++)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Skeleton(
                    width: 40,
                    height: 40,
                    radius: WarmPopTokens.radiusPill,
                  ),
                  SizedBox(width: 12),
                  Skeleton(width: 140, height: 14),
                ],
              ),
            ),
        ],
      ),
    };

    return AppSheetChrome(
      title:
          '${group.emoji} ${group.count} '
          '${group.count == 1 ? 'reaction' : 'reactions'}',
      body: body,
    );
  }

  Widget _reactorRow(
    BuildContext context,
    WidgetRef ref,
    Reactor r, {
    required bool isMe,
    required bool online,
  }) {
    final t = context.t;
    return ConstrainedBox(
      key: ValueKey('reaction-detail-user-${r.userId}'),
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          AppAvatar(
            key: ValueKey('reaction-detail-avatar-${r.userId}'),
            url: r.avatarUrl,
            initials: initialsOf(r.name),
            radius: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  r.name,
                  style: TextStyle(
                    fontSize: 16,
                    height: 22 / 16,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                if (isMe)
                  Text(
                    'You',
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: t.inkSoft,
                    ),
                  ),
              ],
            ),
          ),
          if (isMe)
            // C4: ink, not red. Offline: one 38% dim, as the reaction row.
            IgnorePointer(
              ignoring: !online,
              child: Opacity(
                opacity: online ? 1 : 0.38,
                child: AppButton(
                  variant: AppButtonVariant.text,
                  onPressed: () async {
                    // The sheet may be swiped away mid-write; its ref dies
                    // with it, the container does not.
                    final container = ProviderScope.containerOf(context);
                    await container
                        .read(messageRepositoryProvider)
                        .removeReaction(r.reactionId);
                    container.invalidate(reactionsProvider(messageServerId));
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Remove'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReactionAddChip extends ConsumerWidget {
  const _ReactionAddChip({required this.messageServerId});

  final String messageServerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Add reaction',
      child: GestureDetector(
        key: ValueKey('reaction-add-$messageServerId'),
        onTap: () => _showPicker(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: context.t.surface,
            border: Border.all(color: context.t.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('＋', style: TextStyle(color: context.t.inkSoft)),
        ),
      ),
    );
  }

  Future<void> _showPicker(BuildContext context, WidgetRef ref) async {
    final selected = await showReactionPicker(context);
    if (selected == null) return;
    await ref
        .read(messageRepositoryProvider)
        .addReaction(messageServerId, selected);
    ref.invalidate(reactionsProvider(messageServerId));
  }
}

String? _avatarUrl(String baseUrl, String userId, String avatar) {
  if (avatar.isEmpty) return null;
  if (avatar.startsWith('http://') || avatar.startsWith('https://')) {
    return avatar;
  }
  final root = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  return '$root/api/files/users/$userId/$avatar';
}
