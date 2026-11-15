import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';

/// R11 (chat calm §F): a placeholder appears only after this much loading.
const kSkeletonDelay = Duration(milliseconds: 300); // motion-allow: Chat calm placeholder, kept

/// R11: one breath, 1.0 ↔ 0.55 opacity, back and forth.
const kSkeletonBreath = Duration(milliseconds: 1600); // motion-allow: Chat calm placeholder, kept

/// R11: one clock for every [Skeleton] inside it, so a loading layout
/// breathes together. Its blocks stay invisible (but keep their size, so
/// nothing jumps) until [delay] has passed. Under reduced motion there is
/// no ticker at all: the blocks are static at full opacity.
///
/// A [Skeleton] with no group above it makes its own.
class SkeletonGroup extends StatefulWidget {
  const SkeletonGroup({
    super.key,
    required this.child,
    this.delay = kSkeletonDelay,
    this.duration = kSkeletonBreath,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Live breathing controllers, for the R11 one-clock test.
  static int debugLiveControllers = 0;

  @override
  State<SkeletonGroup> createState() => _SkeletonGroupState();
}

class _SkeletonGroupState extends State<SkeletonGroup>
    with TickerProviderStateMixin {
  AnimationController? _breath;
  Timer? _delay;
  late bool _shown = widget.delay == Duration.zero;

  @override
  void initState() {
    super.initState();
    if (!_shown) {
      _delay = Timer(widget.delay, () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      _stop();
    } else if (_breath == null) {
      _breath = AnimationController(vsync: this, duration: widget.duration)
        ..repeat(reverse: true);
      SkeletonGroup.debugLiveControllers++;
    }
  }

  @override
  void didUpdateWidget(covariant SkeletonGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final breath = _breath;
    if (breath != null && oldWidget.duration != widget.duration) {
      breath
        ..duration = widget.duration
        ..repeat(reverse: true);
    }
  }

  void _stop() {
    if (_breath == null) return;
    _breath!.dispose();
    _breath = null;
    SkeletonGroup.debugLiveControllers--;
  }

  @override
  void dispose() {
    _delay?.cancel();
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final breath = _breath;
    final opacity = breath == null
        ? kAlwaysCompleteAnimation
        : _WallClockBreath(breath, widget.duration);
    return _SkeletonScope(
      opacity: opacity,
      child: Opacity(opacity: _shown ? 1 : 0, child: widget.child),
    );
  }
}

/// The breath's opacity read from the wall clock, so groups started at
/// different times (one per decrypting bubble) still breathe together. The
/// controller only supplies the frames.
class _WallClockBreath extends Animation<double>
    with AnimationWithParentMixin<double> {
  _WallClockBreath(this.parent, this.period);

  @override
  final Animation<double> parent;
  final Duration period;

  @override
  double get value {
    final ms = period.inMilliseconds;
    final t = (DateTime.now().millisecondsSinceEpoch % (2 * ms)) / ms;
    final x = t <= 1 ? t : 2 - t; // there and back
    return 1.0 - 0.45 * Curves.easeInOut.transform(x); // motion-allow: Chat calm placeholder, kept
  }
}

/// R11: [child] (e.g. a whole chat bubble standing in for its text) is
/// the placeholder: it appears after 300 ms and breathes with every other
/// placeholder on screen.
class SkeletonBreath extends StatelessWidget {
  const SkeletonBreath({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SkeletonGroup(
    child: Builder(
      builder: (context) => FadeTransition(
        opacity: _SkeletonScope.maybeOf(context)!,
        child: child,
      ),
    ),
  );
}

class _SkeletonScope extends InheritedWidget {
  const _SkeletonScope({required this.opacity, required super.child});

  final Animation<double> opacity;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SkeletonScope>()?.opacity;

  @override
  bool updateShouldNotify(_SkeletonScope old) => opacity != old.opacity;
}

/// Loading placeholder block (registry R11): a flat block that breathes on
/// its [SkeletonGroup]'s clock. Two shapes:
/// * the default block draws [height] × [width];
/// * [Skeleton.fill] takes the size its parent hands it.
/// [color] defaults to surface2; chat placeholders pass `bubbleMine` for the
/// own side and [borderRadius] for B1 corners.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.height = 16,
    this.width,
    this.radius = 8,
    this.borderRadius,
    this.color,
    this.duration = kSkeletonBreath,
  }) : fill = false;

  const Skeleton.fill({
    super.key,
    this.radius = 8,
    this.borderRadius,
    this.color,
    this.duration = kSkeletonBreath,
  }) : height = 0,
       width = null,
       fill = true;

  final double height;
  final double? width;
  final double radius;
  final BorderRadius? borderRadius;
  final Color? color;

  /// The breath length when this block makes its own group.
  final Duration duration;

  /// True when this block sizes itself to the incoming constraints instead
  /// of drawing [height] × [width].
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final opacity = _SkeletonScope.maybeOf(context);
    final box = _box(context);
    if (opacity == null) {
      return SkeletonGroup(
        duration: duration,
        child: Builder(
          builder: (context) => FadeTransition(
            opacity: _SkeletonScope.maybeOf(context)!,
            child: box,
          ),
        ),
      );
    }
    return FadeTransition(opacity: opacity, child: box);
  }

  Widget _box(BuildContext context) {
    final decoration = BoxDecoration(
      color: color ?? context.t.surface2,
      borderRadius: borderRadius ?? BorderRadius.circular(radius),
    );
    if (fill) {
      return LayoutBuilder(
        builder: (context, box) => Container(
          width: box.hasBoundedWidth ? box.maxWidth : null,
          height: box.hasBoundedHeight ? box.maxHeight : null,
          decoration: decoration,
        ),
      );
    }
    return Container(width: width, height: height, decoration: decoration);
  }
}
