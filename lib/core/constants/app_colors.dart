import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // --- Brand ---
  static const Color primary = Color(0xFF5E6AD2);
  static const Color primaryVariant = Color(0xFF4A55C0);
  static const Color primaryLight = Color(0xFFEEF0FB);

  // --- Chat Bubbles ---
  static const Color sentBubble = Color(0xFF5E6AD2);
  static const Color receivedBubbleLight = Color(0xFFFFFFFF);
  static const Color receivedBubbleDark = Color(0xFF1E2030);

  // --- Read Receipts ---
  static const Color tickSent = Color(0xFF9CA3AF);
  static const Color tickDelivered = Color(0xFF9CA3AF);
  static const Color tickRead = Color(0xFF5E6AD2);

  // --- Semantic ---
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);

  static ThemeData lightTheme() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: const ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        secondary: primaryVariant,
        surface: Color(0xFFFFFFFF),
        surfaceContainerHighest: Color(0xFFEEEEF3),
        error: error,
        onSurface: Color(0xFF1A1A2E),
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F5F7),
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        foregroundColor: Color(0xFF1A1A2E),
      ),
    );
  }

  static ThemeData darkTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: Colors.white,
        secondary: primaryVariant,
        surface: Color(0xFF1A1A2E),
        surfaceContainerHighest: Color(0xFF252840),
        error: error,
        onSurface: Color(0xFFF1F1F5),
      ),
      scaffoldBackgroundColor: const Color(0xFF12121F),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: const Color(0xFFF1F1F5),
        displayColor: const Color(0xFFF1F1F5),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A2E),
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        foregroundColor: Color(0xFFF1F1F5),
      ),
    );
  }

  static ThemeData amoledTheme() {
    final base = darkTheme();
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        surface: const Color(0xFF000000),
        surfaceContainerHighest: const Color(0xFF0D0D0D),
      ),
      scaffoldBackgroundColor: const Color(0xFF000000),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: const Color(0xFF000000),
      ),
    );
  }
}
