import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import '../tool/tokens_core.dart';

String hex(Color c) => '#${c.value
    .toRadixString(16)
    .padLeft(8, '0')
    .substring(2)
    .toUpperCase()}';

void main() {
  test('export stays in sync with tokens (run dart run tool/export_tokens.dart)',
      () {
    final f = File('design_tokens.json');
    expect(f.existsSync(), isTrue,
        reason: 'run: dart run tool/export_tokens.dart');
    final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final colors = map['colors'] as Map<String, dynamic>;
    expect(colors['accent'], '#EFA00B');
    expect(colors['bg'], '#FAF7F1');
    expect(map['radius']['lg'], 20);
    expect(map['space'], [4, 8, 12, 16, 20, 24, 32, 40, 48]);
    final dark = colors['dark'] as Map<String, dynamic>;
    expect(dark['bg'], '#171512');
    expect(dark['onAccent'], '#21260F');
  });

  test('bridge: WarmPopCore (export source) == WarmPopTokens (app colors)',
      () {
    // The chain that keeps website tokens honest:
    // tokens.dart == core == design_tokens.json.
    expect(hex(WarmPopTokens.accent), WarmPopCore.accent);
    expect(hex(WarmPopTokens.bg), WarmPopCore.bg);
    expect(hex(WarmPopTokens.mascotBody), WarmPopCore.mascotBody);
    expect(hex(WarmPopTokens.mascotSnout), WarmPopCore.mascotSnout);
    expect(hex(WarmPopTokens.bgDark), WarmPopCore.bgDark);
    expect(hex(WarmPopTokens.onAccentDark), WarmPopCore.onAccentDark);
    expect(WarmPopTokens.radiusLg, WarmPopCore.radius['lg']);
    expect(WarmPopTokens.space, WarmPopCore.space);
    expect(WarmPopTokens.motionBase.inMilliseconds,
        WarmPopCore.motion['baseMs']);
  });

  test('Jakarta font asset exists (optional font, P11)', () {
    expect(
        File('assets/fonts/PlusJakartaSans/PlusJakartaSans-VF.ttf')
            .existsSync(),
        isTrue,
        reason:
            'download from github.com/google/fonts ofl/plusjakartasans');
  });
}
