import 'package:flutter/material.dart';
import 'tokens.dart';

ThemeData warmPopLight({String? fontFamily}) =>
    _build(ColorTokens.light, Brightness.light, fontFamily);

/// AMOLED: Warm Pop on a pure-black ground (preserves the app's existing
/// theme-mode option — matches the legacy AMOLED palette's black surfaces).
ThemeData warmPopDark({bool amoled = false, String? fontFamily}) =>
    _build(amoled ? const ColorTokens(
      bg: Colors.black,
      // A raised card needs a surface that differs from the page ground.
      // With bg == surface == pure black the card was invisible (and a
      // black shadow on black gives no elevation cue either) — the card
      // now sits on a near-black surface with a faint light edge.
      surface: Color(0xFF0A0908),
      surface2: Color(0xFF0D0D0D),
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
      shadow: WarmPopTokens.shadowAmoled,
      bubbleMine: WarmPopTokens.primary900,
      accentText: WarmPopTokens.primary300,
    ) : ColorTokens.dark, Brightness.dark, fontFamily);

ThemeData _build(ColorTokens c, Brightness brightness, String? fontFamily) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.error,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.ink,
    surfaceContainerHighest: c.surface2,
    outline: c.line,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    extensions: [c],
    // P11: null = system font (default); 'PlusJakartaSans' when chosen (L2).
    fontFamily: fontFamily,
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -.02,
          height: 1.25),
      titleMedium:
          TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.35),
      bodyMedium: TextStyle(fontSize: 15, height: 1.45),
      bodySmall: TextStyle(fontSize: 13, height: 1.38),
      labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.27,
          letterSpacing: .06),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(color: c.bg, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusXl)),
      titleTextStyle: TextStyle(
          fontSize: 20,
          height: 26 / 20,
          fontWeight: FontWeight.w700,
          color: c.ink),
      contentTextStyle: TextStyle(fontSize: 15, height: 22 / 15, color: c.ink),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(WarmPopTokens.radiusLg))),
    ),
    dividerColor: c.line,
  );
}
