import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/pocketbase_client.dart';
import '../../../data/local/database/app_database.dart';
import '../../../data/local/database/tables/app_settings_table.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../providers/chat_provider.dart';

class ReactionBar extends ConsumerWidget {
  const ReactionBar({
    super.key,
    required this.messageServerId,
    required this.isMine,
  });

  final String messageServerId;
  final bool   isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(reactionsProvider(messageServerId));

    return groupsAsync.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, __) => const SizedBox.shrink(),
      data: (groups) {
        if (groups.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(
            left:   isMine ? 0 : 12,
            right:  isMine ? 12 : 0,
            top:    2,
            bottom: 4,
          ),
          child: Wrap(
            spacing:  4,
            runSpacing: 4,
            alignment: isMine ? WrapAlignment.end : WrapAlignment.start,
            children: groups
                .map((g) => _ReactionChip(
                      group:           g,
                      messageServerId: messageServerId,
                      isMine:          isMine,
                    ))
                .toList(),
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
  final String        messageServerId;
  final bool          isMine;  // isMine = message is mine (bubble side)

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Colors that work in both light and dark, on both bubble sides
    final bg = group.isMine
        ? AppColors.primary.withValues(alpha: 0.15)
        : isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.07);

    final border = group.isMine
        ? AppColors.primary.withValues(alpha: 0.5)
        : Colors.transparent;

    return GestureDetector(
      onTap: () => _showReactionDetail(context, ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color:        bg,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: border),
        ),
        child: Text(
          '${group.emoji} ${group.count}',
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  Future<void> _showReactionDetail(BuildContext context, WidgetRef ref) async {
    // Fetch who reacted with this emoji
    final pb    = ref.read(pocketbaseClientProvider).pb;
    final db    = ref.read(appDatabaseProvider);
    final myId  = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId) ?? '';

    List<(String name, String userId, String reactionId)> reactors = [];
    try {
      final res = await pb.collection('reactions').getList(
        filter:  'message_id="$messageServerId"&&emoji="${group.emoji}"',
        expand:  'user_id',
        perPage: 50,
      );
      for (final r in res.items) {
        final u    = r.expand['user_id']?.firstOrNull;
        final name = u?.getStringValue('display_name') ?? 'Unknown';
        final uid  = r.getStringValue('user_id');
        reactors.add((name, uid, r.id));
      }
    } catch (_) {}

    if (!context.mounted) return;

    showModalBottomSheet(
      context:          context,
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
              style: const TextStyle(
                fontSize:   18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Divider(height: 20),
            ...reactors.map((r) => ListTile(
              leading:         const CircleAvatar(
                backgroundColor: AppColors.primaryLight,
                child: Icon(Icons.person, color: AppColors.primary, size: 18),
              ),
              title:           Text(r.$1),
              subtitle:        r.$2 == myId ? const Text('You') : null,
              trailing:        r.$2 == myId
                  ? TextButton(
                      onPressed: () async {
                        await ref
                            .read(messageRepositoryProvider)
                            .removeReaction(r.$3);
                        ref.invalidate(reactionsProvider(messageServerId));
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text(
                        'Remove',
                        style: TextStyle(color: AppColors.error),
                      ),
                    )
                  : null,
              contentPadding:  EdgeInsets.zero,
              dense:           true,
            )),
          ],
        ),
      ),
    );
  }
}
