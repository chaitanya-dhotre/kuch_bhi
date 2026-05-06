import 'package:drift/drift.dart';

/// Key-value store for all local app preferences.
/// Keys are defined as constants in AppSettingsKeys.
class AppSettingsTable extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// All valid keys for AppSettingsTable.
class AppSettingsKeys {
  AppSettingsKeys._();
  static const String theme = 'theme'; // 'light' | 'dark' | 'amoled'
  static const String appLockEnabled = 'app_lock_enabled';
  static const String currentUserId = 'current_user_id';
  static const String notificationsEnabled = 'notifications_enabled';
  static const String defaultMediaQuality = 'default_media_quality';
  static const String lastSyncAt = 'last_sync_at';
}
