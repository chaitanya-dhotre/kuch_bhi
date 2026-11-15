import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/app_haptic.dart';

class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    required this.isMine,
  });

  final Widget       child;
  final VoidCallback onReply;
  final bool         isMine;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  double _offset    = 0;
  bool   _triggered = false;

  static const _threshold = 72.0;
  static const _maxDrag   = 80.0;

  // Motion C8: the release runs on springDrag (critically damped, no wobble).
  late final AnimationController _snapCtrl = AnimationController.unbounded(
    vsync: this,
  )..addListener(() => setState(() => _offset = _snapCtrl.value.clamp(0, _maxDrag)));

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    _snapCtrl.stop();
    // Only allow rightward swipe.
    final next = (_offset + d.delta.dx).clamp(0.0, _maxDrag);
    setState(() {
      _offset = next;
      if (_offset >= _threshold && !_triggered) {
        _triggered = true;
        appHaptic(HapticsType.medium);
        widget.onReply();
      }
    });
  }

  void _onEnd(DragEndDetails d) {
    _triggered = false;
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _offset = 0);
      return;
    }
    _snapCtrl.value = _offset;
    _snapCtrl.animateWith(
      SpringSimulation(
        WarmPopTokens.springDrag,
        _offset,
        0,
        d.velocity.pixelsPerSecond.dx,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_offset / _threshold).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd:    _onEnd,
      child: Stack(
        children: [
          // Reply icon revealed as the bubble slides right
          Positioned(
            left:   16,
            top:    0,
            bottom: 0,
            child: Opacity(
              opacity: progress,
              child: Transform.scale(
                scale: 0.6 + 0.4 * progress,
                child: Icon(
                  Icons.reply_rounded,
                  color: context.t.accent,
                  size: 22,
                ),
              ),
            ),
          ),
          // Sliding content
          Transform.translate(
            offset: Offset(_offset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
