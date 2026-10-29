import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The registry's 18px busy spinner — the same widget R3 draws in its
/// `busy` slot, extracted so features that grep-gate the raw
/// `CircularProgressIndicator` out of their own source (checklist A6 /
/// grep gates) can still show a busy state.
///
/// Under reduced motion (K3) the ring does not spin: it parks as a static
/// surface2 ring, matching [Skeleton]'s shimmer park.
class BusySpinner extends StatelessWidget {
  const BusySpinner({super.key, this.size = 18, this.strokeWidth = 2});

  final double size;
  final double strokeWidth;

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
      child: CircularProgressIndicator(strokeWidth: strokeWidth),
    );
  }
}
