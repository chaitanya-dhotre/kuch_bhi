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

/// E3 / D-3 B: decorative bar heights from a message id, the same on both
/// phones. FNV-1a so the bars never change between runs.
List<double> generatedWaveLevels(String seed, {int bars = kVoiceBubbleBars}) {
  var h = 0x811c9dc5;
  for (final c in seed.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return [
    for (var i = 0; i < bars; i++)
      () {
        h = ((h ^ (i + 1)) * 0x01000193) & 0xffffffff;
        // A soft envelope keeps the ends lower, like speech.
        final env = 0.55 + 0.45 * math.sin(math.pi * (i + 0.5) / bars);
        return (0.18 + 0.82 * ((h >> 8) & 0xff) / 255) * env;
      }(),
  ];
}

/// E3: bars in a voice bubble.
const kVoiceBubbleBars = 36;

class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    super.key,
    required this.levels,
    this.progress,
    this.live = false,
    this.bars,
    this.height = 48,
    this.restAlpha,
  });

  final List<double> levels;
  final double? progress;
  final bool live;

  /// Set = exactly this many bars spread over the width (E3: 36).
  final int? bars;
  final double height;

  /// Set = unplayed bars are ink at this alpha (E3: 0.3) instead of inkFaint.
  final double? restAlpha;

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
            bars: bars,
            ink: t.ink,
            faint: restAlpha == null
                ? t.inkFaint
                : t.ink.withValues(alpha: restAlpha),
          ),
          size: Size(double.infinity, height),
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
    this.bars,
    required this.ink,
    required this.faint,
  });

  final List<double> levels;
  final double? progress;
  final bool live;
  final int? bars;
  final Color ink;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars != null) return _paintFixed(canvas, size, bars!);
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

  void _paintFixed(Canvas canvas, Size size, int count) {
    if (count <= 0 || levels.isEmpty || size.width <= 0) return;
    final values = levels.length == count
        ? levels
        : levels.length > count
        ? bucketLevels(levels, count)
        : [for (var i = 0; i < count; i++) levels[i * levels.length ~/ count]];
    final slot = size.width / count;
    final barWidth = math.max(1.5, slot * 0.6);
    for (var i = 0; i < count; i++) {
      final level = values[i].clamp(0.06, 1.0).toDouble();
      final barHeight = math.max(3.0, level * size.height);
      final x = i * slot + (slot - barWidth) / 2;
      final played =
          progress != null && (x + barWidth / 2) / size.width <= progress!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - barHeight) / 2, barWidth, barHeight),
          Radius.circular(barWidth / 2),
        ),
        Paint()..color = played ? ink : faint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) =>
      oldDelegate.levels != levels ||
      oldDelegate.levels.length != levels.length ||
      oldDelegate.progress != progress ||
      oldDelegate.live != live ||
      oldDelegate.bars != bars ||
      oldDelegate.ink != ink ||
      oldDelegate.faint != faint;
}
