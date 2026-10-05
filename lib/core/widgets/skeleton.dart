import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

/// Loading placeholder block. The tween loop parks under reduced-motion
/// (rendered as a static surface2 block).
class Skeleton extends StatefulWidget {
  const Skeleton(
      {super.key, this.height = 16, this.width, this.radius = 8});
  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void initState() {
    super.initState();
    _shimmer.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
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
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        final v = _shimmer.value;
        final c = Color.lerp(t.surface2, t.line, (v * 0.6).clamp(0, 1))!;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}
