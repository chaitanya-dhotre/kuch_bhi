import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The registry's 18px busy spinner — the same widget R3 draws in its
/// `busy` slot, extracted so features that grep-gate the raw
/// `CircularProgressIndicator` out of their own source (checklist A6 /
/// grep gates) can still show a busy state.
///
/// Under reduced motion (K3) the ring does not spin: it parks as a static
/// surface2 ring, matching [Skeleton]'s reduced-motion park.
class BusySpinner extends StatelessWidget {
  const BusySpinner({
    super.key,
    this.size = 18,
    this.strokeWidth = 2,
    this.color,
  });

  final double size;
  final double strokeWidth;

  /// Ring tint. `null` (the default) = the theme's accent ring, which is
  /// what every default site renders. Sites whose ring sits on an accent
  /// disc keep their own tint through this slot — swapping them for an
  /// untinted ring would paint accent on accent.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: context.t.surface2, width: strokeWidth),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: strokeWidth, color: color),
    );
  }
}
