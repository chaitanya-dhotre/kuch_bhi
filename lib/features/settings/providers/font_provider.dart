import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../data/local/database/app_database.dart';

/// P11: system font default; Plus Jakarta Sans optional.
enum AppFont { system, jakarta }

const _kFontKey = 'app_font';

extension AppFontX on AppFont {
  String get storageValue => name;

  static AppFont fromStorage(String? v) {
    return AppFont.values.firstWhere(
      (e) => e.name == v,
      orElse: () => AppFont.system,
    );
  }

  String get label => switch (this) {
        AppFont.system  => kSystemDefaultLabel,
        AppFont.jakarta => 'Plus Jakarta Sans',
      };

  /// `ThemeData.fontFamily`; null = the platform font.
  String? get fontFamily => switch (this) {
        AppFont.system  => null,
        AppFont.jakarta => 'PlusJakartaSans',
      };
}

/// Reactive font choice, persisted in Drift (AppSettingsTable).
final fontFamilyProvider = StreamProvider<AppFont>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.settingsDao.watchSetting(_kFontKey).map(AppFontX.fromStorage);
});

final fontControllerProvider = Provider<FontController>((ref) {
  return FontController(ref.read(appDatabaseProvider));
});

class FontController {
  FontController(this._db);
  final AppDatabase _db;

  Future<void> setFont(AppFont font) =>
      _db.settingsDao.setSetting(_kFontKey, font.storageValue);
}
