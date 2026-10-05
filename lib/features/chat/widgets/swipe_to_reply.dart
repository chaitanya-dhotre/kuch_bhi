import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/tokens.dart';

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

  late final AnimationController _snapCtrl;
  late       Animation<double>   _snapAnim;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 180),
    )..addListener(() => setState(() => _offset = _snapAnim.value));
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails d) {
    // Only allow rightward swipe.
    final next = (_offset + d.delta.dx).clamp(0.0, _maxDrag);
    setState(() {
      _offset = next;
      if (_offset >= _threshold && !_triggered) {
        _triggered = true;
        HapticFeedback.mediumImpact();
        widget.onReply();
      }
    });
  }

  void _onEnd(DragEndDetails _) {
    _triggered = false;
    _snapAnim = Tween<double>(begin: _offset, end: 0).animate(
      CurvedAnimation(parent: _snapCtrl, curve: Curves.elasticOut),
    );
    _snapCtrl.forward(from: 0);
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
