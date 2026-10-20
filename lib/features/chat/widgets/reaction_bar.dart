import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/network/pocketbase_client.dart';
import '../../../data/local/database/app_database.dart';
import '../../../data/local/database/tables/app_settings_table.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../message_offline_policy.dart';
import '../providers/chat_provider.dart';
import '../../../core/theme/tokens.dart';

const _reactionEmojis = [
  '👍',
  '👎',
  '❤️',
  '🔥',
  '😂',
  '😮',
  '😢',
  '🙏',
  '🎉',
  '💯',
  '😍',
  '🤔',
  '😡',
  '👏',
  '🤣',
  '😊',
  '💪',
  '🫡',
  '✅',
  '❌',
  '⭐',
  '💎',
  '🚀',
  '😴',
  '🥹',
  '🫶',
  '😎',
  '🤯',
  '🥳',
  '👀',
  '💀',
  '🫠',
];

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
    final groupsAsync = ref.watch(reactionsProvider(messageServerId));
    final isOnline = ref.watch(isOnlineProvider).value ?? true;
    final reactionsEnabled = isMessageActionEnabled(
      MessageAction.react,
      isOnline: isOnline,
    );

    return groupsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (groups) {
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

  Future<void> _showReactionDetail(BuildContext context, WidgetRef ref) async {
    // Fetch who reacted with this emoji
    final pb = ref.read(pocketbaseClientProvider).pb;
    final db = ref.read(appDatabaseProvider);
    final myId =
        await db.settingsDao.getSetting(AppSettingsKeys.currentUserId) ?? '';

    final reactors =
        <(String name, String userId, String reactionId, String? avatarUrl)>[];
    try {
      final res = await pb
          .collection('reactions')
          .getList(
            filter: 'message_id="$messageServerId"&&emoji="${group.emoji}"',
            expand: 'user_id',
            perPage: 50,
          );
      for (final r in res.items) {
        final expandedUsers = r.get<List<dynamic>>(
          'expand.user_id',
          const <dynamic>[],
        );
        final dynamic u = expandedUsers.isEmpty ? null : expandedUsers.first;
        final uid = r.getStringValue('user_id');
        final localUser = await db.usersDao.getUserById(uid);
        final expandedName = u?.getStringValue('display_name') ?? '';
        final name = expandedName.isNotEmpty
            ? expandedName
            : localUser?.displayName.isNotEmpty == true
            ? localUser!.displayName
            : 'Unknown';
        final cachedAvatar = localUser?.avatarUrl;
        final expandedAvatar = u?.getStringValue('avatar') ?? '';
        final avatarUrl = cachedAvatar?.isNotEmpty == true
            ? cachedAvatar
            : _avatarUrl(pb.baseURL, uid, expandedAvatar);
        reactors.add((name, uid, r.id, avatarUrl));
      }
    } catch (_) {}

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${group.emoji}  ${group.count} ${group.count == 1 ? "reaction" : "reactions"}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Divider(height: 20),
            ...reactors.map(
              (r) => ListTile(
                key: ValueKey('reaction-detail-user-${r.$2}'),
                leading: _ReactionAvatar(
                  key: ValueKey('reaction-detail-avatar-${r.$2}'),
                  name: r.$1,
                  avatarUrl: r.$4,
                ),
                title: Text(r.$1),
                subtitle: r.$2 == myId ? const Text('You') : null,
                trailing: r.$2 == myId
                    ? TextButton(
                        onPressed: () async {
                          await ref
                              .read(messageRepositoryProvider)
                              .removeReaction(r.$3);
                          ref.invalidate(reactionsProvider(messageServerId));
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: Text(
                          'Remove',
                          style: TextStyle(color: context.t.error),
                        ),
                      )
                    : null,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
          ],
        ),
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
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (pickerContext) => SafeArea(
        child: GridView.count(
          key: const Key('reaction-picker'),
          shrinkWrap: true,
          crossAxisCount: 6,
          padding: const EdgeInsets.all(16),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final emoji in _reactionEmojis)
              InkResponse(
                key: ValueKey('reaction-picker-$emoji'),
                onTap: () => Navigator.of(pickerContext).pop(emoji),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              ),
          ],
        ),
      ),
    );
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

class _ReactionAvatar extends StatelessWidget {
  const _ReactionAvatar({
    super.key,
    required this.name,
    required this.avatarUrl,
  });

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final trimmedName = name.trim();
    final initial = trimmedName.isEmpty ? '?' : trimmedName[0].toUpperCase();
    final fallback = Text(
      initial,
      style: TextStyle(color: context.t.accent, fontWeight: FontWeight.w700),
    );

    return CircleAvatar(
      backgroundColor: context.t.accentSoft,
      child: avatarUrl == null
          ? fallback
          : CachedNetworkImage(
              imageUrl: avatarUrl!,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              imageBuilder: (_, imageProvider) => CircleAvatar(
                backgroundColor: context.t.accentSoft,
                backgroundImage: imageProvider,
              ),
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback,
            ),
    );
  }
}
