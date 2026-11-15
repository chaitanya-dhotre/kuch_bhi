import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Warm Pop token system — the single source of truth (spec).
/// Components read tokens; screens read components. Never hardcode colors
/// in lib/core/widgets or lib/features/mascot (grep gate in tasks 4/5/6).
class WarmPopTokens {
  WarmPopTokens._();

  // Primary shade card (chat calm D1, seed = 500). The primitive layer
  // under the role names below; screens read `context.t.*`, never these.
  static const primary50 = Color(0xFFFEF5EA);
  static const primary100 = Color(0xFFFFE9CF);
  static const primary200 = Color(0xFFFFD59E);
  static const primary300 = Color(0xFFFEBF67);
  static const primary400 = Color(0xFFF9AC33);
  static const primary500 = Color(0xFFEFA00B);
  static const primary600 = Color(0xFFCC8808);
  static const primary700 = Color(0xFFA56D01);
  static const primary800 = Color(0xFF744C01);
  static const primary900 = Color(0xFF492F06);

  // Brand
  static const accent = primary500;
  static const accentPressed = primary600;
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

  // Elevation — foundation §4: warm-tinted soft shadow, max 2 layers.
  // The shadow COLOR is theme-dependent (never `ink`: ink is near-white in
  // dark, which renders a white halo around elevated cards). Light =
  // warm rgba(52,42,28) — matches the board's `0 2px 8px rgba(52,42,28,.10)`.
  // Dark = rgba(0,0,0,.35) per the board's dark `--cardShadow`.
  static const shadowLight = Color(0x1A342A1C); // rgba(52,42,28,.10)
  static const shadowDark = Color(0x59000000); // rgba(0,0,0,.35)

  /// AMOLED shadow — a faint LIGHT edge.
  ///
  /// The AMOLED theme paints its surfaces pure black, so a black shadow is
  /// invisible on them: a raised card would have no elevation cue at all
  /// (and the card surface itself is the same black as the page ground).
  /// A faint light edge keeps the card readable on pure black, which is the
  /// same cue the ink-derived shadow used to give.
  static const shadowAmoled = Color(0x0AF3EDE3); // rgba(243,237,227,.04)
  /// Motion B4 / C6: the scrim under sheets, dialogs and the bubble menu.
  static const scrim = Color(0x73000000); // black 45 %

  /// The single card shadow layer (foundation §4: max 2 shadow layers).
  ///
  /// Rendered with an explicit `BoxShadow`, NOT Material's `elevation`:
  /// Material routes its shadow through the engine's tonal path, which
  /// paints a shadow materially weaker than the token's literal alpha
  /// (measured ~7× weaker in a pixel probe) — a card built with
  /// `Material(elevation: 2, shadowColor: …)` does NOT match the board's
  /// `0 2px 8px rgba(52,42,28,.10)`. The explicit layer paints the token's
  /// alpha exactly.
  static List<BoxShadow> cardShadow(Color color) => [
        BoxShadow(
          color: color,
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

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
  static const radiusPill = 999.0;
  static const radiusBubble = 18.0;
  static const radiusBubbleTail = 6.0;

  // Motion (motion spec §A; foundation §5). The only source of durations
  // and curves for chat and core widgets (L8 grep gate).
  static const motionPress = Duration(milliseconds: 120);
  static const motionFast = Duration(milliseconds: 150);
  static const motionEnter = Duration(milliseconds: 200);
  static const motionBase = Duration(milliseconds: 250);
  static const motionPage = Duration(milliseconds: 320);
  static const motionSlow = Duration(milliseconds: 400);

  /// Derived from the tokens above (L3 exits at 75 %, C1 flight, C2 arrive).
  static const motionPagePop = Duration(milliseconds: 240);
  static const motionExit = Duration(milliseconds: 190);
  static const motionSend = Duration(milliseconds: 300);
  static const motionArrive = Duration(milliseconds: 180);
  static const motionShake = Duration(milliseconds: 360);

  static const curveEnter = Cubic(0.32, 0.72, 0, 1);
  static const curveExit = Cubic(0.55, 0, 1, 0.45);
  static const curveMove = Cubic(0.77, 0, 0.175, 1);

  /// Ratio 0.8: ~1.5 % overshoot, settles in ~300 ms.
  static final springSoft = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 400,
    ratio: 0.8,
  );

  /// Critically damped: a released drag never wobbles.
  static final springDrag = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 400,
    ratio: 1,
  );
}

/// L7: [d], or zero when the system asks for no animations.
Duration motionOf(BuildContext context, Duration d) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;

/// Runs [c] from 0 to 1 on [spring]; jumps there under reduced motion.
/// Ends exactly on 1 (the simulation stops within its tolerance).
void springTo(
  BuildContext context,
  AnimationController c,
  SpringDescription spring, {
  double from = 0,
}) {
  if (MediaQuery.disableAnimationsOf(context)) {
    c.value = 1;
    return;
  }
  c.animateWith(SpringSimulation(spring, from, 1, 0)).then((_) => c.value = 1);
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
    required this.shadow,
    required this.bubbleMine,
    required this.accentText,
  });

  /// D2: the own bubble's fill (a tint, never the solid accent). Text on it
  /// is [ink].
  final Color bubbleMine;

  /// D2: marigold text and links on surfaces (800 light, 300 dark).
  final Color accentText;

  final Color bg, surface, surface2, ink, inkSoft, inkFaint, line, accent,
      accentPressed, accentSoft, onAccent, success, error, info;

  /// Elevation shadow color (foundation §4). Never derive a shadow from
  /// [ink] — ink is near-white in dark, which halos elevated cards.
  final Color shadow;

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
    shadow: WarmPopTokens.shadowLight,
    bubbleMine: WarmPopTokens.primary100,
    accentText: WarmPopTokens.primary800,
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
    shadow: WarmPopTokens.shadowDark,
    bubbleMine: WarmPopTokens.primary900,
    accentText: WarmPopTokens.primary300,
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
    Color? shadow,
    Color? bubbleMine,
    Color? accentText,
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
        shadow: shadow ?? this.shadow,
        bubbleMine: bubbleMine ?? this.bubbleMine,
        accentText: accentText ?? this.accentText,
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
      shadow: Color.lerp(shadow, other.shadow, t)!,
      bubbleMine: Color.lerp(bubbleMine, other.bubbleMine, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
    );
  }
}

extension ThemeX on BuildContext {
  ColorTokens get t => Theme.of(this).extension<ColorTokens>()!;
}
