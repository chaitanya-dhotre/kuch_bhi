import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Motion C5 / C7 / D1: when [value] changes after the first paint, [child]
/// pops from [from] to 1 on `springSoft`. Never on first paint (L1).
class PopOnChange extends StatefulWidget {
  const PopOnChange({
    super.key,
    required this.value,
    required this.child,
    this.from = 0.7,
  });

  final Object? value;
  final Widget child;
  final double from;

  @override
  State<PopOnChange> createState() => _PopOnChangeState();
}

class _PopOnChangeState extends State<PopOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: 1,
  );

  @override
  void didUpdateWidget(PopOnChange old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      springTo(context, _c, WarmPopTokens.springSoft);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _c.drive(Tween(begin: widget.from, end: 1.0)),
    child: widget.child,
  );
}

/// Motion D1: [builder] gets 1 the moment [trigger] changes after the first
/// paint, easing back to 0 over `motionSlow`.
class FlashOnChange extends StatefulWidget {
  const FlashOnChange({
    super.key,
    required this.trigger,
    required this.builder,
  });

  final Object? trigger;
  final Widget Function(BuildContext context, double flash) builder;

  @override
  State<FlashOnChange> createState() => _FlashOnChangeState();
}

class _FlashOnChangeState extends State<FlashOnChange>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: WarmPopTokens.motionSlow,
  );

  @override
  void didUpdateWidget(FlashOnChange old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger &&
        !MediaQuery.disableAnimationsOf(context)) {
      _c
        ..value = 1
        ..animateTo(0, curve: WarmPopTokens.curveEnter);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => widget.builder(context, _c.value),
  );
}

/// Motion D2 (M-3): a row whose [slot] changed in a new [generation] slides
/// from its old place over `motionBase` on `curveMove`; one that had a slot
/// but no element (it was off screen) fades in instead. A new reorder
/// mid-slide retargets from where the row is now. Rows are one height.
/// The parent passes [previousSlot] only in the reorder's own frame.
class ReorderSlide extends StatefulWidget {
  const ReorderSlide({
    super.key,
    required this.slot,
    required this.previousSlot,
    required this.generation,
    required this.child,
  });

  final int slot;
  final int? previousSlot;
  final int generation;
  final Widget child;

  @override
  State<ReorderSlide> createState() => _ReorderSlideState();
}

class _ReorderSlideState extends State<ReorderSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: WarmPopTokens.motionBase,
    value: 1,
  );
  double _from = 0; // dy at the start of the slide
  bool _fade = false;
  late int _gen;

  double get _dy =>
      _from * (1 - WarmPopTokens.curveMove.transform(_c.value));

  bool get _moved =>
      widget.previousSlot != null && widget.previousSlot != widget.slot;

  @override
  void initState() {
    super.initState();
    _gen = widget.generation;
    // Built for the first time in the reorder's own frame: it came from
    // beyond the screen edge.
    _fade = _moved;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fade && _c.value == 1 && !_c.isAnimating) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _fade = false;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void didUpdateWidget(ReorderSlide old) {
    super.didUpdateWidget(old);
    if (widget.generation == _gen) return;
    _gen = widget.generation;
    if (!_moved || MediaQuery.disableAnimationsOf(context)) return;
    final box = context.findRenderObject() as RenderBox?;
    final h = box != null && box.hasSize ? box.size.height : 0.0;
    _from = _dy + (widget.previousSlot! - widget.slot) * h;
    _fade = false;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade ? _c : kAlwaysCompleteAnimation,
    child: AnimatedBuilder(
    animation: _c,
    child: widget.child,
    // One tree shape always, so the row's own state survives.
    builder: (context, child) =>
        Transform.translate(offset: Offset(0, _dy), child: child),
    ),
  );
}

/// Motion E1: each change of [trigger] after the first paint shakes [child]
/// once: x = 0, −10, 10, −6, 6, −3, 0 dp over 360 ms. Only for a wrong PIN
/// or recovery key; nothing else shakes.
class ShakeOnChange extends StatefulWidget {
  const ShakeOnChange({super.key, required this.trigger, required this.child});

  final Object? trigger;
  final Widget child;

  @override
  State<ShakeOnChange> createState() => _ShakeOnChangeState();
}

class _ShakeOnChangeState extends State<ShakeOnChange>
    with SingleTickerProviderStateMixin {
  static const _keys = [0.0, -10.0, 10.0, -6.0, 6.0, -3.0, 0.0];
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: WarmPopTokens.motionShake,
    value: 1,
  );

  static double xAt(double t) {
    final f = t.clamp(0.0, 1.0) * (_keys.length - 1);
    final i = f.floor().clamp(0, _keys.length - 2);
    return _keys[i] + (_keys[i + 1] - _keys[i]) * (f - i);
  }

  @override
  void didUpdateWidget(ShakeOnChange old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger &&
        !MediaQuery.disableAnimationsOf(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) =>
        Transform.translate(offset: Offset(xAt(_c.value), 0), child: child),
  );
}
