import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import 'capybara_painter.dart';

export 'capybara_painter.dart';

/// Tier-1 mascot rig: idle breathe + blink, parks under reduced-motion
/// (spec). Tier-2 state performers come with their screens.
class Capybara extends StatefulWidget {
  const Capybara({
    super.key,
    this.mood = CapyMood.neutral,
    this.showKey = false,
    this.size = const Size(140, 118),
  });
  final CapyMood mood;
  final bool showKey;
  final Size size;

  @override
  State<Capybara> createState() => _CapybaraState();
}

class _CapybaraState extends State<Capybara>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
      vsync: this, duration: WarmPopTokens.mascotBreathe);
  double _blink = 0;
  Timer? _blinkTimer;
  int _blinkSeq = 0;

  @override
  void initState() {
    super.initState();
    _idle.repeat(reverse: true);
    _scheduleBlink();
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkSeq++;
    final seq = _blinkSeq;
    _blinkTimer = Timer(Duration(milliseconds: 3400 + (seq * 733) % 1600),
        () async {
      if (!mounted || seq != _blinkSeq) return;
      setState(() => _blink = 1);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || seq != _blinkSeq) return;
      setState(() => _blink = 0);
      _scheduleBlink();
    });
  }

  void _pause() {
    _idle.stop();
    _blinkTimer?.cancel();
    setState(() => _blink = 0);
  }

  void _resume() {
    _idle.repeat(reverse: true);
    _scheduleBlink();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      _pause();
    } else if (!_idle.isAnimating) {
      _resume();
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    _blinkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _idle,
        builder: (context, _) => CustomPaint(
          size: widget.size,
          painter: CapybaraPainter(
            mood: widget.mood,
            blink: _blink,
            breathe: _idle.value,
            showKey: widget.showKey,
          ),
        ),
      ),
    );
  }
}
