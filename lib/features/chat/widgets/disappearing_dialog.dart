import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/local/database/app_database.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';

/// Canonical label for a disappearing-messages duration (registry C11).
/// Shared by the chat menu trailing slot and the Group Info settings row.
String disappearingDurationLabel(int seconds) => switch (seconds) {
      0 => 'Off',
      86400 => '24 hours',
      604800 => '7 days',
      2592000 => '30 days',
      _ => '${seconds ~/ 86400} days',
    };

/// The disappearing-messages dialog (registry C11) — ONE definition for both
/// entry points: the chat menu and the Group Info settings row.
///
/// The checkmark rides `ink` (foundation C4: accent-coloured text on a light
/// surface fails 4.5:1; accent is a fill/track/border only). The write is
/// awaited inside try/catch so a failure surfaces as a toast instead of an
/// unhandled async error.
Future<void> showDisappearingDialog(
  BuildContext context,
  WidgetRef ref,
  String conversationId,
) async {
  final row = await ref
      .read(appDatabaseProvider)
      .conversationsDao
      .getConversationById(conversationId);
  if (!context.mounted) return;
  var selectedDuration = row?.disappearingDuration ?? 0;
  await showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Disappearing Messages'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final opt in [
              ('Off', 0),
              ('24 hours', 86400),
              ('7 days', 604800),
              ('30 days', 2592000),
            ])
              ListTile(
                title: Text(opt.$1),
                subtitle: const Text('Applies to new messages only'),
                trailing: selectedDuration == opt.$2
                    // C11: the tick rides `ink` explicitly — the dialog's
                    // IconTheme would otherwise fall back to black87.
                    ? Icon(Icons.check, color: dialogContext.t.ink)
                    : null,
                onTap: () async {
                  setDialogState(() => selectedDuration = opt.$2);
                  Navigator.pop(dialogContext);
                  try {
                    await ref
                        .read(messageRepositoryProvider)
                        .setDisappearingDuration(conversationId, opt.$2);
                    if (context.mounted) {
                      showToast(context, 'Disappearing: ${opt.$1}');
                    }
                  } catch (_) {
                    debugPrint(
                      '[Disappearing] write failed for $conversationId',
                    );
                    if (context.mounted) {
                      showToast(
                        context,
                        kUpdateFailedCopy,
                        error: true,
                      );
                    }
                  }
                },
              ),
          ],
        ),
      ),
    ),
  );
}
