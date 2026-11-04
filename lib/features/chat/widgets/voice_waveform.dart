import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

double waveLevel(double dbfs) {
  if (!dbfs.isFinite) return 0.06;
  return ((dbfs + 50) / 50).clamp(0.06, 1.0).toDouble();
}

List<double> bucketLevels(List<double> levels, int bars) {
  if (bars <= 0) return <double>[];
  if (levels.length < bars) return List<double>.from(levels);
  return [
    for (var i = 0; i < bars; i++)
      levels
          .sublist(i * levels.length ~/ bars, (i + 1) * levels.length ~/ bars)
          .reduce(math.max),
  ];
}

class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    super.key,
    required this.levels,
    this.progress,
    this.live = false,
  });

  final List<double> levels;
  final double? progress;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return RepaintBoundary(
      child: ExcludeSemantics(
        child: CustomPaint(
          painter: _VoiceWaveformPainter(
            levels: List<double>.from(levels),
            progress: progress?.clamp(0.0, 1.0),
            live: live,
            ink: t.ink,
            faint: t.inkFaint,
          ),
          size: const Size(double.infinity, 48),
        ),
      ),
    );
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  const _VoiceWaveformPainter({
    required this.levels,
    required this.progress,
    required this.live,
    required this.ink,
    required this.faint,
  });

  final List<double> levels;
  final double? progress;
  final bool live;
  final Color ink;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    final count = (size.width + 2) ~/ 5;
    if (count <= 0) return;
    final values = live
        ? levels.skip(math.max(0, levels.length - count)).toList()
        : bucketLevels(levels, count);
    if (values.isEmpty) return;
    final barWidth = 3.0;
    final gap = 2.0;
    final first = live && values.length < count ? count - values.length : 0;
    final spread = !live && values.length < count;
    for (var i = 0; i < values.length; i++) {
      final level = values[i].clamp(0.06, 1.0).toDouble();
      final barHeight = math.max(3.0, level * size.height);
      final x = spread
          ? values.length == 1
                ? (size.width - barWidth) / 2
                : i * (size.width - barWidth) / (values.length - 1)
          : (first + i) * (barWidth + gap);
      final top = (size.height - barHeight) / 2;
      final played =
          progress == null || (x + barWidth / 2) / size.width <= progress!;
      final paint = Paint()..color = played ? ink : faint;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, barWidth, barHeight),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) =>
      oldDelegate.levels != levels ||
      oldDelegate.levels.length != levels.length ||
      oldDelegate.progress != progress ||
      oldDelegate.live != live ||
      oldDelegate.ink != ink ||
      oldDelegate.faint != faint;
}
