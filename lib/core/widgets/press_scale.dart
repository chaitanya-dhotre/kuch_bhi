import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Motion B1: a press scales [child] to 0.96 over `motionPress` from the
/// touch's own frame (L2), and back on release. For buttons, chips and
/// small actions; rows wider than 200 dp only change colour.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: widget.enabled ? (_) => _set(true) : null,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && widget.enabled ? 0.96 : 1,
        duration: motionOf(context, WarmPopTokens.motionPress),
        curve: WarmPopTokens.curveEnter,
        child: widget.child,
      ),
    );
  }
}
