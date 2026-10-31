import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../data/local/database/app_database.dart';

/// App theme options. AMOLED is a true-black dark variant.
enum AppThemeMode { system, light, dark, amoled }

const _kThemeKey = 'app_theme_mode';

extension AppThemeModeX on AppThemeMode {
  String get storageValue => name;

  static AppThemeMode fromStorage(String? v) {
    return AppThemeMode.values.firstWhere(
      (e) => e.name == v,
      orElse: () => AppThemeMode.system,
    );
  }

  String get label => switch (this) {
        AppThemeMode.system => kSystemDefaultLabel,
        AppThemeMode.light  => 'Light',
        AppThemeMode.dark   => 'Dark',
        AppThemeMode.amoled => 'AMOLED (true black)',
      };

  IconData get icon => switch (this) {
        AppThemeMode.system => Icons.brightness_auto_outlined,
        AppThemeMode.light  => Icons.light_mode_outlined,
        AppThemeMode.dark   => Icons.dark_mode_outlined,
        AppThemeMode.amoled => Icons.contrast,
      };
}

/// Reactive theme mode, persisted in Drift (AppSettingsTable).
final themeModeProvider =
    StreamProvider<AppThemeMode>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.settingsDao
      .watchSetting(_kThemeKey)
      .map(AppThemeModeX.fromStorage);
});

/// Controller to change + persist the theme.
final themeControllerProvider = Provider<ThemeController>((ref) {
  return ThemeController(ref.read(appDatabaseProvider));
});

class ThemeController {
  ThemeController(this._db);
  final AppDatabase _db;

  Future<void> setTheme(AppThemeMode mode) =>
      _db.settingsDao.setSetting(_kThemeKey, mode.storageValue);

  Future<AppThemeMode> current() async {
    final v = await _db.settingsDao.getSetting(_kThemeKey);
    return AppThemeModeX.fromStorage(v);
  }
}
