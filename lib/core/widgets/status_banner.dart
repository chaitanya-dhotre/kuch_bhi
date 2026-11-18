import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

/// Inline status strip (offline, syncing, key waiting…). Optional retry.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    this.leading,
    this.onRetry,
    this.actionLabel,
    this.onAction,
  });
  final String message;
  final Widget? leading;
  final VoidCallback? onRetry;

  /// R12a (key-change warning): a labelled action instead of Retry.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.accentSoft,
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
        // Calm-rest A1: no marigold edge; icons passed in take accentText.
        border: Border.all(color: t.line, width: 1),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: t.ink),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                  foregroundColor: t.ink,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Retry',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          if (onAction != null && actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                  foregroundColor: t.ink,
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: Text(actionLabel!,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
