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

/// Calm-rest D2 / D5: a column that keeps a row on screen once more after
/// it left [items], so it can fade while its height closes over `motionExit`
/// on `curveExit` and the rows below move up with it. With [fadeIn], a row
/// added after the first build fades in over `motionEnter`. Under reduced
/// motion rows come and go at once. The exit is drawn from the list alone:
/// it never delays a pop and never repeats the action that removed the row.
class LeavingColumn<T> extends StatefulWidget {
  const LeavingColumn({
    super.key,
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    this.separator,
    this.fadeIn = false,
  });

  final List<T> items;
  final String Function(T item) idOf;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Drawn above every row but the first; it leaves with its row.
  final Widget? separator;
  final bool fadeIn;

  @override
  State<LeavingColumn<T>> createState() => _LeavingColumnState<T>();
}

class _LeavingEntry<T> {
  _LeavingEntry(this.id, this.item, {this.enter = false});
  final String id;
  final T item;
  final bool enter;
  bool leaving = false;
}

class _LeavingColumnState<T> extends State<LeavingColumn<T>> {
  late List<_LeavingEntry<T>> _rows = [
    for (final item in widget.items) _LeavingEntry(widget.idOf(item), item),
  ];

  @override
  void didUpdateWidget(LeavingColumn<T> old) {
    super.didUpdateWidget(old);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final before = {for (final r in _rows) r.id};
    final next = [
      for (final item in widget.items)
        _LeavingEntry(
          widget.idOf(item),
          item,
          enter: widget.fadeIn && !reduced && !before.contains(widget.idOf(item)),
        ),
    ];
    if (!reduced) {
      final ids = {for (final r in next) r.id};
      String? above; // the row that sat just above, so a leaver keeps its place
      for (final r in _rows) {
        if (!ids.contains(r.id)) {
          r.leaving = true;
          final at = above == null
              ? 0
              : next.indexWhere((n) => n.id == above) + 1;
          next.insert(at, r);
        }
        above = r.id;
      }
    }
    _rows = next;
  }

  void _gone(_LeavingEntry<T> row) {
    if (mounted && _rows.contains(row)) setState(() => _rows.remove(row));
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, r) in _rows.indexed)
        _LeavingRow(
          key: ValueKey(r.id),
          leaving: r.leaving,
          enter: r.enter,
          onGone: () => _gone(r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (i > 0 && widget.separator != null) widget.separator!,
              // Keyed, so the row keeps its state when the separator goes.
              KeyedSubtree(
                key: const ValueKey('row'),
                child: widget.itemBuilder(context, r.item),
              ),
            ],
          ),
        ),
    ],
  );
}

class _LeavingRow extends StatefulWidget {
  const _LeavingRow({
    super.key,
    required this.leaving,
    required this.enter,
    required this.onGone,
    required this.child,
  });

  final bool leaving;
  final bool enter;
  final VoidCallback onGone;
  final Widget child;

  @override
  State<_LeavingRow> createState() => _LeavingRowState();
}

class _LeavingRowState extends State<_LeavingRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: WarmPopTokens.motionEnter,
    reverseDuration: WarmPopTokens.motionExit,
    value: widget.enter ? 0 : 1,
  );
  late final CurvedAnimation _a = CurvedAnimation(
    parent: _c,
    curve: WarmPopTokens.curveEnter,
    reverseCurve: WarmPopTokens.curveExit.flipped,
  );

  @override
  void initState() {
    super.initState();
    if (widget.enter) _c.forward();
  }

  @override
  void didUpdateWidget(_LeavingRow old) {
    super.didUpdateWidget(old);
    if (widget.leaving && !old.leaving) {
      // A cancelled run (the row came back, or was disposed) never completes.
      _c.reverse().then((_) => widget.onGone());
    } else if (!widget.leaving && old.leaving) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leaving = widget.leaving;
    return IgnorePointer(
      ignoring: leaving,
      child: ExcludeSemantics(
        excluding: leaving,
        child: AnimatedBuilder(
          animation: _a,
          child: FadeTransition(opacity: _a, child: widget.child),
          // One tree shape always; it clips only while the height closes,
          // so a resting card keeps its shadow.
          builder: (context, child) => ClipRect(
            clipBehavior: leaving ? Clip.hardEdge : Clip.none,
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: leaving ? _a.value.clamp(0.0, 1.0) : 1,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
