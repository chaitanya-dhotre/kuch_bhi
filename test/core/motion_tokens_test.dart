// Motion spec gate 1: the tokens in §A exist, and chat + core widgets read
// durations and curves only from them (L8). A line that must keep a raw
// value (recorder, video, the Chat calm placeholders, timers) says
// `motion-allow` with its reason.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';

void main() {
  test('the eleven §A tokens hold the spec values', () {
    expect(WarmPopTokens.motionPress, const Duration(milliseconds: 120));
    expect(WarmPopTokens.motionFast, const Duration(milliseconds: 150));
    expect(WarmPopTokens.motionEnter, const Duration(milliseconds: 200));
    expect(WarmPopTokens.motionBase, const Duration(milliseconds: 250));
    expect(WarmPopTokens.motionPage, const Duration(milliseconds: 320));
    expect(WarmPopTokens.motionSlow, const Duration(milliseconds: 400));
    expect(WarmPopTokens.curveEnter, const Cubic(0.32, 0.72, 0, 1));
    expect(WarmPopTokens.curveExit, const Cubic(0.55, 0, 1, 0.45));
    expect(WarmPopTokens.curveMove, const Cubic(0.77, 0, 0.175, 1));
    // Damping ratio = damping / (2 * sqrt(mass * stiffness)).
    double ratio(SpringDescription s) =>
        s.damping / (2 * math.sqrt(s.mass * s.stiffness));
    expect(ratio(WarmPopTokens.springSoft), closeTo(0.8, 1e-9));
    expect(ratio(WarmPopTokens.springDrag), closeTo(1.0, 1e-9));
  });

  test('L8: chat and core widgets take motion from the tokens', () {
    final files = [
      ...Directory('lib/features/chat').listSync(recursive: true),
      ...Directory('lib/core/widgets').listSync(recursive: true),
    ].whereType<File>().where((f) => f.path.endsWith('.dart'));
    final allowFile = RegExp(r'voice_recorder_panel|video_');
    final raw = RegExp(r'Duration\(milliseconds|Curves\.|Cubic\(');
    final timer = RegExp(r'Timer(\.periodic)?\(|delayed\(|timeout\(');
    final hits = <String>[];
    for (final f in files) {
      if (allowFile.hasMatch(f.path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (!raw.hasMatch(l) || timer.hasMatch(l)) continue;
        if (l.contains('motion-allow')) continue;
        hits.add('${f.path}:${i + 1}: ${l.trim()}');
      }
    }
    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
