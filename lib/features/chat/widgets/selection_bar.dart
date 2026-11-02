import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../message_offline_policy.dart';
import 'message_context_menu.dart' show confirmAndDeleteForMe;

/// C19 (12.8 H1): the selection bar the chat and the album collage share.
/// A null [onCopy] / [onStar] leaves that slot out (the collage); a slot
/// that can't act right now is dimmed and not enabled.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.onExit,
    this.onCopy,
    this.canCopy = false,
    this.starState = false,
    this.onStar,
    this.canStar = false,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onExit;
  final VoidCallback? onCopy;
  final bool canCopy;

  /// True = every starrable selected row is starred, so the slot unstars.
  final bool starState;
  final VoidCallback? onStar;
  final bool canStar;

  /// Enabled while at least one row is selected.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Widget action(IconData icon, String tooltip, VoidCallback? onPressed) =>
        IconButton(
          tooltip: tooltip,
          color: t.inkSoft,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: onPressed,
          icon: Opacity(
            opacity: onPressed == null ? 0.38 : 1,
            child: Icon(icon),
          ),
        );

    return SizedBox(
      height: 56,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Exit selection',
            color: t.ink,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.close),
            onPressed: onExit,
          ),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '$count selected',
                  maxLines: 1,
                  style: TextStyle(
                    color: t.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          if (onCopy != null)
            action(
              Icons.copy_outlined,
              'Copy selected messages',
              canCopy ? onCopy : null,
            ),
          if (onStar != null)
            action(
              starState ? Icons.star : Icons.star_outline,
              starState ? 'Unstar selected messages' : 'Star selected messages',
              canStar ? onStar : null,
            ),
          action(
            Icons.delete_outline,
            'Delete selected messages',
            count > 0 ? onDelete : null,
          ),
        ],
      ),
    );
  }
}

/// D4/D5: every row yours (and still a member) → Delete for me / Delete for
/// everyone, else straight to delete for me. True = deleted; false =
/// cancelled, nothing deleted.
Future<bool> deleteSelectedMessages(
  BuildContext context,
  WidgetRef ref,
  List<Message> rows, {
  required bool canDeleteForEveryone,
  List<Message> Function()? current,
}) async {
  if (rows.isEmpty) return false;
  final repo = ref.read(messageRepositoryProvider);
  final choice = canDeleteForEveryone ? await _deleteChoice(context) : 'me';
  if (choice == null || !context.mounted) return false;

  if (choice == 'me') {
    return confirmAndDeleteForMe(context, [
      for (final row in rows) row.localId,
    ], repo.deleteMessage);
  }

  final one = rows.length == 1;
  final ok = await showConfirmDialog(
    context: context,
    title: one ? 'Delete message?' : 'Delete ${rows.length} messages?',
    body: one
        ? 'This message will be deleted for everyone in this chat.'
        : 'These messages will be deleted for everyone in this chat.',
    confirmLabel: 'Delete',
    confirmIcon: Icons.delete_outline,
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  // The connection can drop while the dialog is open: offline the server
  // refuses it and the next fetch brings the messages back.
  if (!(ref.read(isOnlineProvider).valueOrNull ?? true)) {
    showToast(context, kOfflineActionHint, error: true);
    return false;
  }
  // A row can gain its server id while the dialog is open.
  final now = {for (final m in current?.call() ?? rows) m.localId: m};
  for (final picked in rows) {
    final row = now[picked.localId];
    if (row == null) continue; // D7: gone meanwhile
    // D5: an unsent row reached no one; a tombstone is already gone for them.
    if (row.serverId != null && !row.isDeletedForEveryone) {
      await repo.deleteMessage(row.localId, forEveryone: true);
    } else {
      await repo.deleteMessage(row.localId);
    }
  }
  return true;
}

Future<String?> _deleteChoice(BuildContext context) {
  return showAppSheet<String>(
    context: context,
    useRootNavigator: true,
    // Watched, so the row dims and wakes as the connection changes.
    builder: (sheetContext) => Consumer(
      builder: (_, ref, _) {
        final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
        return AppSheetChrome(
          children: [
            SheetActionRow(
              icon: Icons.delete_outline,
              label: 'Delete for me',
              destructive: true,
              onTap: () => Navigator.of(sheetContext).pop('me'),
            ),
            SheetActionRow(
              icon: Icons.delete_forever_outlined,
              label: 'Delete for everyone',
              destructive: true,
              enabled: online,
              trailing: online ? null : kOfflineActionHint,
              onTap: () => Navigator.of(sheetContext).pop('everyone'),
            ),
          ],
        );
      },
    ),
  );
}
