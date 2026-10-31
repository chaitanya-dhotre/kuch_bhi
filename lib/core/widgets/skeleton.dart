import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/tokens.dart';

/// Loading placeholder block. The tween loop parks under reduced-motion
/// (rendered as a static surface2 block).
///
/// Registry R11 has two shapes:
/// * the default block takes [height] / [width] and pulses surface2↔line on
///   its own ticker;
/// * the [Skeleton.fill] variant has no box of its own — it takes the size
///   its parent hands it and sweeps the same surface2↔line pair, which is
///   the shimmer the media placeholders used to hand-roll (registry D2:
///   one skeleton, not two). It is the only place outside this file's
///   siblings that may build a `Shimmer.fromColors` (grep gate).
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.height = 16,
    this.width,
    this.radius = 8,
    this.duration = const Duration(milliseconds: 1200),
  }) : fill = false;

  /// R11 fill variant: same colours, same reduced-motion park, no fixed
  /// box — the block is as big as the constraints it is given.
  const Skeleton.fill({
    super.key,
    this.radius = 8,
    this.duration = const Duration(milliseconds: 1200),
  })  : height = 0,
        width = null,
        fill = true;

  final double height;
  final double? width;
  final double radius;
  final Duration duration;

  /// True when this block sizes itself to the incoming constraints instead
  /// of drawing [height] × [width].
  final bool fill;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;
  bool _motionInitialized = false;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(vsync: this, duration: widget.duration);
    // The fill variant drives its sweep through Shimmer's own ticker.
    if (!widget.fill) _shimmer.repeat();
  }

  @override
  void didUpdateWidget(covariant Skeleton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fill) return;
    if (oldWidget.duration != widget.duration) {
      _shimmer.duration = widget.duration;
      if (_motionInitialized && !_reducedMotion) {
        _shimmer
          ..stop()
          ..repeat();
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    _motionInitialized = true;
    _reducedMotion = reducedMotion;
    if (widget.fill) return;
    if (reducedMotion) {
      _shimmer.stop();
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (widget.fill) return _fill(context, t);
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        final v = _shimmer.value;
        final c = Color.lerp(t.surface2, t.line, (v * 0.6).clamp(0, 1))!;
        return _box(c, widget.width, widget.height);
      },
    );
  }

  /// The fill variant: no fixed box, so the size comes from the parent.
  /// Under reduced motion there is no Shimmer in the tree at all — just the
  /// static surface2 block the default variant parks on.
  Widget _fill(BuildContext context, ColorTokens t) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = _box(
          t.surface2,
          constraints.hasBoundedWidth ? constraints.maxWidth : null,
          constraints.hasBoundedHeight ? constraints.maxHeight : null,
        );
        if (MediaQuery.disableAnimationsOf(context)) return box;
        return Shimmer.fromColors(
          baseColor: t.surface2,
          highlightColor: t.line,
          period: widget.duration,
          child: box,
        );
      },
    );
  }

  Widget _box(Color color, double? width, double? height) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
}
