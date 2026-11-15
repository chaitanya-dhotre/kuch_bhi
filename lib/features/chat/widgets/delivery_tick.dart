import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/busy_spinner.dart';

/// Canonical delivery-state indicator used by chat surfaces.
class DeliveryTick extends StatelessWidget {
  const DeliveryTick({super.key, required this.status, this.size = 13});

  final String status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final normalizedStatus = status == 'pending' ? 'queued' : status;

    // Motion C4: a status change cross-fades over motionFast, no bounce.
    final Widget icon = switch (normalizedStatus) {
      'sending' => BusySpinner(size: size, strokeWidth: 2, color: t.inkFaint),
      'sent' => Icon(Icons.check, size: size, color: t.inkSoft),
      'delivered' => Icon(
        Icons.done_all,
        size: size,
        color: t.inkSoft.withValues(alpha: .54),
      ),
      'read' => Icon(Icons.done_all, size: size, color: t.info),
      'failed' => Icon(Icons.warning_amber_rounded, size: size, color: t.error),
      'queued' => Icon(Icons.schedule, size: size, color: t.inkFaint),
      _ => Icon(Icons.schedule, size: size, color: t.inkFaint),
    };
    return AnimatedSwitcher(
      duration: motionOf(context, WarmPopTokens.motionFast),
      child: KeyedSubtree(key: ValueKey(normalizedStatus), child: icon),
    );
  }
}
