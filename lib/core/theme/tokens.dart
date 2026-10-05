import 'package:flutter/material.dart';

/// Warm Pop token system — the single source of truth (spec).
/// Components read tokens; screens read components. Never hardcode colors
/// in lib/core/widgets or lib/features/mascot (grep gate in tasks 4/5/6).
class WarmPopTokens {
  WarmPopTokens._();

  // Brand
  static const accent = Color(0xFFEFA00B);
  static const accentPressed = Color(0xFFD98F08);
  static const onAccentLight = Color(0xFF2A2520);
  static const onAccentDark = Color(0xFF21260F);

  // Light
  static const bg = Color(0xFFFAF7F1);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF1ECE3);
  static const ink = Color(0xFF2A2520);
  static const inkSoft = Color(0xFF6E655A);
  static const inkFaint = Color(0xFF9C9284);
  static const line = Color(0xFFE4DDD1);
  static const accentSoftLight = Color(0xFFFFF3DC);

  // Dark
  static const bgDark = Color(0xFF171512);
  static const surfaceDark = Color(0xFF211E1A);
  static const surface2Dark = Color(0xFF2B2823);
  static const inkDark = Color(0xFFF3EDE3);
  static const inkSoftDark = Color(0xFF9C9284);
  static const lineDark = Color(0xFF3B362F);
  static const accentSoftDark = Color(0xFF3A2E14);

  // Semantic
  static const success = Color(0xFF0E9F6E);
  static const error = Color(0xFFE5484D);
  static const info = Color(0xFF4A6FA5);

  // Mascot (constant across themes)
  static const mascotBody = Color(0xFFC6894F);
  static const mascotShade = Color(0xFFB27A42);
  static const mascotSnout = Color(0xFF8B5E3E);
  static const mascotNostril = Color(0xFF5C3B28);
  static const mascotFace = Color(0xFF3A2E22);
  static const keyGold = Color(0xFFE8A21D);

  // Space (4-base grid)
  static const space = [4, 8, 12, 16, 20, 24, 32, 40, 48];

  // Radius
  static const radiusSm = 10.0;
  static const radiusMd = 16.0;
  static const radiusLg = 20.0;
  static const radiusXl = 24.0;
  static const radiusBubble = 18.0;
  static const radiusBubbleTail = 6.0;

  // Motion
  static const motionFast = Duration(milliseconds: 150);
  static const motionBase = Duration(milliseconds: 250);
  static const motionSlow = Duration(milliseconds: 400);
  static const mascotBreathe = Duration(milliseconds: 3400);
  static const mascotBlink = Duration(milliseconds: 4600);
}

/// Theme-scoped colors. Components consume `context.t`.
class ColorTokens extends ThemeExtension<ColorTokens> {
  const ColorTokens({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.line,
    required this.accent,
    required this.accentPressed,
    required this.accentSoft,
    required this.onAccent,
    required this.success,
    required this.error,
    required this.info,
  });

  final Color bg, surface, surface2, ink, inkSoft, inkFaint, line, accent,
      accentPressed, accentSoft, onAccent, success, error, info;

  static const light = ColorTokens(
    bg: WarmPopTokens.bg,
    surface: WarmPopTokens.surface,
    surface2: WarmPopTokens.surface2,
    ink: WarmPopTokens.ink,
    inkSoft: WarmPopTokens.inkSoft,
    inkFaint: WarmPopTokens.inkFaint,
    line: WarmPopTokens.line,
    accent: WarmPopTokens.accent,
    accentPressed: WarmPopTokens.accentPressed,
    accentSoft: WarmPopTokens.accentSoftLight,
    onAccent: WarmPopTokens.onAccentLight,
    success: WarmPopTokens.success,
    error: WarmPopTokens.error,
    info: WarmPopTokens.info,
  );

  static const dark = ColorTokens(
    bg: WarmPopTokens.bgDark,
    surface: WarmPopTokens.surfaceDark,
    surface2: WarmPopTokens.surface2Dark,
    ink: WarmPopTokens.inkDark,
    inkSoft: WarmPopTokens.inkSoftDark,
    inkFaint: WarmPopTokens.inkSoftDark,
    line: WarmPopTokens.lineDark,
    accent: WarmPopTokens.accent,
    accentPressed: WarmPopTokens.accentPressed,
    accentSoft: WarmPopTokens.accentSoftDark,
    onAccent: WarmPopTokens.onAccentDark,
    success: WarmPopTokens.success,
    error: WarmPopTokens.error,
    info: WarmPopTokens.info,
  );

  @override
  ColorTokens copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    Color? line,
    Color? accent,
    Color? accentPressed,
    Color? accentSoft,
    Color? onAccent,
    Color? success,
    Color? error,
    Color? info,
  }) =>
      ColorTokens(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        ink: ink ?? this.ink,
        inkSoft: inkSoft ?? this.inkSoft,
        inkFaint: inkFaint ?? this.inkFaint,
        line: line ?? this.line,
        accent: accent ?? this.accent,
        accentPressed: accentPressed ?? this.accentPressed,
        accentSoft: accentSoft ?? this.accentSoft,
        onAccent: onAccent ?? this.onAccent,
        success: success ?? this.success,
        error: error ?? this.error,
        info: info ?? this.info,
      );

  @override
  ColorTokens lerp(ThemeExtension<ColorTokens>? other, double t) {
    if (other is! ColorTokens) return this;
    return ColorTokens(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      line: Color.lerp(line, other.line, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentPressed: Color.lerp(accentPressed, other.accentPressed, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

extension ThemeX on BuildContext {
  ColorTokens get t => Theme.of(this).extension<ColorTokens>()!;
}
