import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

/// Inline status strip (offline, syncing, key waiting…). Optional retry.
class StatusBanner extends StatelessWidget {
  const StatusBanner(
      {super.key, required this.message, this.leading, this.onRetry});
  final String message;
  final Widget? leading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: t.accentSoft,
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
        border: Border.all(
            color: t.accent.withValues(alpha: .45), width: 1),
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
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Retry',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
