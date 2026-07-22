import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../providers/chat_provider.dart';

// Extended emoji set — horizontally scrollable
const _reactionEmojis = [
  '👍','👎','❤️','🔥','😂','😮','😢','🙏',
  '🎉','💯','😍','🤔','😡','👏','🤣','😊',
  '💪','🫡','✅','❌','⭐','💎','🚀','😴',
  '🥹','🫶','😎','🤯','🥳','👀','💀','🫠',
];

void showMessageMenu({
  required BuildContext context,
  required WidgetRef    ref,
  required Message      message,
  required bool         isMine,
  required String       senderName,
}) {
  showModalBottomSheet(
    context:          context,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ContextSheet(
      message:    message,
      isMine:     isMine,
      senderName: senderName,
      parentRef:  ref,
    ),
  );
}

class _ContextSheet extends ConsumerWidget {
  const _ContextSheet({
    required this.message,
    required this.isMine,
    required this.senderName,
    required this.parentRef,
  });

  final Message   message;
  final bool      isMine;
  final String    senderName;
  final WidgetRef parentRef;

  void _afterAction(BuildContext context) {
    Navigator.of(context).pop();
    // Invalidate pinned cache so UI refreshes immediately
    // Reactions are now reactive via StreamProvider, no manual invalidation needed
    parentRef.invalidate(pinnedMessagesProvider(message.conversationId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(messageRepositoryProvider);
    final body = message.decryptedBody ?? '';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline
                    .withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Scrollable reaction row
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount:  _reactionEmojis.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final emoji = _reactionEmojis[i];
                return GestureDetector(
                  onTap: () async {
                    if (message.serverId != null) {
                      await repo.addReaction(message.serverId!, emoji);
                    }
                    if (context.mounted) _afterAction(context);
                  },
                  child: Container(
                    width:  46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                );
              },
            ),
          ),

          const Divider(height: 20),

          // Actions
          _tile(Icons.reply_rounded, 'Reply', () {
            parentRef.read(replyProvider.notifier).state = message;
            Navigator.of(context).pop();
          }),

          if (body.isNotEmpty)
            _tile(Icons.copy_outlined, 'Copy', () {
              Clipboard.setData(ClipboardData(text: body));
              _afterAction(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:  Text('Copied'),
                  duration: Duration(seconds: 1),
                ),
              );
            }),

          _tile(
            message.isStarred ? Icons.star : Icons.star_outline,
            message.isStarred ? 'Unstar' : 'Star',
            () async {
              await repo.toggleStar(message.localId);
              if (context.mounted) _afterAction(context);
            },
          ),

          _tile(
            message.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            message.isPinned ? 'Unpin' : 'Pin',
            () async {
              try {
                await repo.togglePin(
                  message.localId,
                  message.conversationId,
                  !message.isPinned,
                );
                if (context.mounted) _afterAction(context);
              } on StateError catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.message)),
                  );
                }
              }
            },
          ),

          _tile(
            Icons.delete_outline, 'Delete for me',
            () async {
              final confirmed = await _confirmDelete(
                context,
                'This message will be deleted for you only.',
              );
              if (!confirmed) return;
              await repo.deleteMessage(message.localId);
              if (context.mounted) _afterAction(context);
            },
            color: AppColors.error,
          ),

          if (isMine && message.serverId != null)
            _tile(
              Icons.delete_forever_outlined, 'Delete for everyone',
              () async {
                final confirmed = await _confirmDelete(
                  context,
                  'This message will be deleted for everyone in this chat.',
                );
                if (!confirmed) return;
                await repo.deleteMessage(message.localId, forEveryone: true);
                if (context.mounted) _afterAction(context);
              },
              color: AppColors.error,
            ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title:   const Text('Delete message?'),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:     const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    return ListTile(
      leading:         Icon(icon, color: color),
      title:           Text(label, style: TextStyle(color: color)),
      onTap:           onTap,
      dense:           true,
      contentPadding:  EdgeInsets.zero,
    );
  }
}
