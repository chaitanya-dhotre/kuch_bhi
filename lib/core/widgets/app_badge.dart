import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

/// Unread/counter pill. Renders nothing when [count] is <= 0.
class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.count, this.color});
  final int count;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final t = context.t;
    final label = count >= 100 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? t.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.27,
          fontWeight: FontWeight.w800,
          letterSpacing: .06,
          color: t.onAccent,
        ),
      ),
    );
  }
}
