// Run: dart run tool/export_tokens.dart
// Writes design_tokens.json + design_tokens.css from WarmPopCore (pure Dart).
// token_export_test.dart proves WarmPopCore == WarmPopTokens (app colors),
// so the export is always in lockstep with the app's runtime tokens.
import 'dart:convert';
import 'dart:io';

import 'tokens_core.dart';

void main() {
  final json = {
    'colors': {
      'accent': WarmPopCore.accent,
      'accentPressed': WarmPopCore.accentPressed,
      'bg': WarmPopCore.bg,
      'surface': WarmPopCore.surface,
      'surface2': WarmPopCore.surface2,
      'ink': WarmPopCore.ink,
      'inkSoft': WarmPopCore.inkSoft,
      'inkFaint': WarmPopCore.inkFaint,
      'line': WarmPopCore.line,
      'accentSoft': WarmPopCore.accentSoftLight,
      'success': WarmPopCore.success,
      'error': WarmPopCore.error,
      'info': WarmPopCore.info,
      'dark': {
        'bg': WarmPopCore.bgDark,
        'surface': WarmPopCore.surfaceDark,
        'surface2': WarmPopCore.surface2Dark,
        'ink': WarmPopCore.inkDark,
        'inkSoft': WarmPopCore.inkSoftDark,
        'line': WarmPopCore.lineDark,
        'accentSoft': WarmPopCore.accentSoftDark,
        'onAccent': WarmPopCore.onAccentDark,
      },
      'mascot': {
        'body': WarmPopCore.mascotBody,
        'shade': WarmPopCore.mascotShade,
        'snout': WarmPopCore.mascotSnout,
        'nostril': WarmPopCore.mascotNostril,
        'face': WarmPopCore.mascotFace,
        'key': WarmPopCore.keyGold,
      },
    },
    'radius': WarmPopCore.radius,
    'space': WarmPopCore.space,
    'motion': WarmPopCore.motion,
  };
  File('design_tokens.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));

  final css = StringBuffer()
    ..writeln(':root {')
    ..writeln('  --accent: ${WarmPopCore.accent};')
    ..writeln('  --bg: ${WarmPopCore.bg};')
    ..writeln('  --surface: ${WarmPopCore.surface};')
    ..writeln('  --ink: ${WarmPopCore.ink};')
    ..writeln('  --line: ${WarmPopCore.line};')
    ..writeln('  --radius-lg: ${WarmPopCore.radius['lg']}px;')
    ..writeln('  --motion-base: ${WarmPopCore.motion['baseMs']}ms;')
    ..writeln('}');
  File('design_tokens.css').writeAsStringSync(css.toString());
  stdout.writeln('wrote design_tokens.json, design_tokens.css');
}
