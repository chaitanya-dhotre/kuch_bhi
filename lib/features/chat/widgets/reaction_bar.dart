import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/press_scale.dart';
import '../../../core/utils/app_haptic.dart';
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
        return _ReactionRow(
          groups: groups,
          messageServerId: messageServerId,
          isMine: isMine,
        );
      },
    );
  }
}

/// Motion C5: chips already there at first paint stay still; a new one
/// pops in on springSoft, a removed one shrinks to 0.8 and fades (120 ms).
class _ReactionRow extends StatefulWidget {
  const _ReactionRow({
    required this.groups,
    required this.messageServerId,
    required this.isMine,
  });

  final List<ReactionGroup> groups;
  final String messageServerId;
  final bool isMine;

  @override
  State<_ReactionRow> createState() => _ReactionRowState();
}

class _ReactionRowState extends State<_ReactionRow> {
  Set<String>? _seen;
  List<ReactionGroup> _last = const [];
  final Map<String, ReactionGroup> _leaving = {};

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    final now = {for (final g in groups) g.emoji};
    final firstPaint = _seen == null;
    final seen = _seen ??= {...now};
    for (final g in _last) {
      if (!now.contains(g.emoji)) _leaving[g.emoji] = g;
    }
    _leaving.removeWhere((emoji, _) => now.contains(emoji));
    _last = groups;
    if (groups.isEmpty && _leaving.isEmpty) return const SizedBox.shrink();
    Widget chip(ReactionGroup g, {bool leaving = false}) => _ChipMotion(
      key: ValueKey(g.emoji),
      popIn: !firstPaint && seen.add(g.emoji),
      leaving: leaving,
      onGone: () {
        seen.remove(g.emoji);
        if (mounted) setState(() => _leaving.remove(g.emoji));
      },
      child: _ReactionChip(
        group: g,
        messageServerId: widget.messageServerId,
        isMine: widget.isMine,
      ),
    );
    // C8: on the sender's side, 4 in from the bubble's corner; the
    // caller lifts the row 8 dp onto the bubble's lower edge. No "+"
    // chip: long-press adds a reaction.
    return Padding(
      padding: EdgeInsets.only(
        left: widget.isMine ? 0 : 16,
        right: widget.isMine ? 16 : 0,
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: widget.isMine ? WrapAlignment.end : WrapAlignment.start,
        children: [
          for (final g in groups) chip(g),
          for (final g in _leaving.values) chip(g, leaving: true),
        ],
      ),
    );
  }
}

class _ChipMotion extends StatefulWidget {
  const _ChipMotion({
    super.key,
    required this.popIn,
    required this.leaving,
    required this.onGone,
    required this.child,
  });

  final bool popIn;
  final bool leaving;
  final VoidCallback onGone;
  final Widget child;

  @override
  State<_ChipMotion> createState() => _ChipMotionState();
}

class _ChipMotionState extends State<_ChipMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: widget.popIn ? 0 : 1,
    reverseDuration: WarmPopTokens.motionPress,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.popIn) springTo(context, _c, WarmPopTokens.springSoft);
    if (widget.leaving) _leave();
  }

  @override
  void didUpdateWidget(_ChipMotion old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) _leave();
  }

  void _leave() {
    if (MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onGone());
      return;
    }
    _c.reverse(from: 1).whenComplete(() {
      if (mounted) widget.onGone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: widget.leaving,
    child: Builder(
      builder: (context) {
        final eased = widget.leaving
            ? _c.drive(CurveTween(curve: WarmPopTokens.curveExit.flipped))
            : _c.view;
        return FadeTransition(
          opacity: eased,
          child: ScaleTransition(
            scale: eased.drive(
              Tween(begin: widget.leaving ? 0.8 : 0.6, end: 1.0),
            ),
            child: widget.child,
          ),
        );
      },
    ),
  );
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
          appHaptic(HapticsType.light); // C5
          await repo.addReaction(messageServerId, group.emoji);
        }
      },
      onLongPress: () => _showReactionDetail(context, ref),
      child: Semantics(
        button: true,
        label: '${group.emoji} reaction, ${group.count}',
        child: PressScale(
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusPill),
            border: Border.all(color: border, width: 1.5),
          ),
          child: _CountRoll(
            emoji: group.emoji,
            count: group.count,
            style: TextStyle(fontSize: 13, height: 18 / 13, color: t.ink),
          ),
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

/// Motion C5: a count change slides the number 6 dp up (more) or down
/// (fewer) while it cross-fades, over motionFast. At rest: one plain Text.
class _CountRoll extends StatefulWidget {
  const _CountRoll({
    required this.emoji,
    required this.count,
    required this.style,
  });

  final String emoji;
  final int count;
  final TextStyle style;

  @override
  State<_CountRoll> createState() => _CountRollState();
}

class _CountRollState extends State<_CountRoll>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: WarmPopTokens.motionFast,
    value: 1,
  );
  int? _old;

  @override
  void didUpdateWidget(_CountRoll old) {
    super.didUpdateWidget(old);
    if (old.count == widget.count) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    _old = old.count;
    _c.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _old = null);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final old = _old;
    if (old == null || !_c.isAnimating) {
      return Text('${widget.emoji} ${widget.count}', style: widget.style);
    }
    final dir = widget.count > old ? -1.0 : 1.0; // more: the number rises
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = WarmPopTokens.curveEnter.transform(_c.value);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.emoji} ', style: widget.style),
            Stack(
              children: [
                Opacity(
                  opacity: 1 - v,
                  child: Transform.translate(
                    offset: Offset(0, 6 * dir * v),
                    child: Text('$old', style: widget.style),
                  ),
                ),
                Opacity(
                  opacity: v,
                  child: Transform.translate(
                    offset: Offset(0, -6 * dir * (1 - v)),
                    child: Text('${widget.count}', style: widget.style),
                  ),
                ),
              ],
            ),
          ],
        );
      },
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
