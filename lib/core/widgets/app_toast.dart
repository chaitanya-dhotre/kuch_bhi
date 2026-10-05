import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

/// Floating snackbar with the Warm Pop treatment. [error] shows an error
/// stripe (t.error) instead of the neutral ink surface.
void showToast(BuildContext context, String message, {bool error = false}) {
  final t = context.t;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      backgroundColor: t.surface,
      elevation: 2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
        side: BorderSide(
            color: error ? t.error : t.line,
            width: error ? 1.5 : 1),
      ),
      content: Row(
        children: [
          if (error) ...[
            Icon(Icons.error_outline, color: t.error, size: 18),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 14, color: t.ink)),
          ),
        ],
      ),
      duration: const Duration(seconds: 3),
    ));
}
