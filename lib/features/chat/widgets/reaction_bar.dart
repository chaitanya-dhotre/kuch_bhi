import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../data/local/database/app_database.dart';
import '../../../data/local/database/tables/app_settings_table.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../providers/chat_provider.dart';
import '../../../core/theme/tokens.dart';

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

    // A reconnect re-reads: keep the chips up meanwhile, no blink.
    return groupsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (groups) {
        if (groups.isEmpty) return const SizedBox.shrink();
        // C8: on the sender's side, 4 in from the bubble's corner; the
        // caller lifts the row 8 dp onto the bubble's lower edge. No "+"
        // chip: long-press adds a reaction.
        return Padding(
          padding: EdgeInsets.only(left: isMine ? 0 : 16, right: isMine ? 16 : 0),
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
    final t = context.t;
    // D2: my reaction = soft accent (fill + 1.5 accent ring); others = a
    // surface2 chip ringed in the page colour so it sits on the bubble edge.
    final bg = group.isMine ? t.accentSoft : t.surface2;
    final border = group.isMine ? t.accent : t.bg;

    return GestureDetector(
      key: ValueKey('reaction-chip-$messageServerId-${group.emoji}'),
      onTap: () async {
        final repo = ref.read(messageRepositoryProvider);
        if (group.isMine && group.reactionId != null) {
          await repo.removeReaction(group.reactionId!);
        } else {
          await repo.addReaction(messageServerId, group.emoji);
        }
      },
      onLongPress: () => _showReactionDetail(context, ref),
      child: Semantics(
        button: true,
        label: '${group.emoji} reaction, ${group.count}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusPill),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Text(
            '${group.emoji} ${group.count}',
            style: TextStyle(fontSize: 13, height: 18 / 13, color: t.ink),
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

/// Who reacted to a message with one emoji, from the local store (names
/// and avatars from cached users), live as reactions change.
final reactionDetailProvider = StreamProvider.autoDispose
    .family<({String myId, List<Reactor> reactors}), (String, String)>((
      ref,
      key,
    ) async* {
      final (messageServerId, emoji) = key;
      final db = ref.read(appDatabaseProvider);
      final myId =
          await db.settingsDao.getSetting(AppSettingsKeys.currentUserId) ?? '';
      final msg = await db.messagesDao.getMessageByServerId(messageServerId);
      if (msg == null) {
        yield (myId: myId, reactors: const <Reactor>[]);
        return;
      }
      final rows = (db.select(db.reactionsTable)
            ..where((r) =>
                r.messageLocalId.equals(msg.localId) & r.emoji.equals(emoji))
            ..orderBy([(r) => OrderingTerm(expression: r.createdAt)]))
          .watch();
      await for (final list in rows) {
        final reactors = <Reactor>[];
        for (final r in list) {
          final user = await db.usersDao.getUserById(r.userId);
          reactors.add((
            name: user?.displayName.isNotEmpty == true
                ? user!.displayName
                : 'Unknown',
            userId: r.userId,
            reactionId: r.id,
            avatarUrl: user?.avatarUrl,
          ));
        }
        yield (myId: myId, reactors: reactors);
      }
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
    final key = (messageServerId, group.emoji);
    final async = ref.watch(reactionDetailProvider(key));

    final Widget body = switch (async) {
      AsyncData(:final value) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final r in value.reactors)
            _reactorRow(context, ref, r, isMe: r.userId == value.myId),
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
            // C4: ink, not red. Works offline: the removal is queued.
            AppButton(
              variant: AppButtonVariant.text,
              onPressed: () async {
                // The sheet may be swiped away mid-write; its ref dies with
                // it, the container does not.
                final container = ProviderScope.containerOf(context);
                await container
                    .read(messageRepositoryProvider)
                    .removeReaction(r.reactionId);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Remove'),
            ),
        ],
      ),
    );
  }
}
