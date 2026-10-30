import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_button.dart';
import 'page_app_bar.dart';

/// Registry R20: the one confirm dialog. Cancel and a barrier tap give
/// `false`. [destructive] = [confirmIcon] in `t.error` + an ink label (C4).
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  IconData? confirmIcon,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final t = ctx.t;
      return AlertDialog(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusXl),
        ),
        title: Text(title, style: pageTitleStyle(ctx)),
        content: Text(
          body,
          style: TextStyle(fontSize: 15, height: 22 / 15, color: t.ink),
        ),
        actions: [
          AppButton(
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          AppButton(
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: confirmIcon == null
                ? Text(confirmLabel)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        confirmIcon,
                        size: 18,
                        color: destructive ? t.error : t.ink,
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(confirmLabel)),
                    ],
                  ),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}
