import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/app_settings_table.dart';
import '../tables/message_drafts_table.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [AppSettingsTable, MessageDraftsTable])
class SettingsDao extends DatabaseAccessor<AppDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.db);

  Future<String?> getSetting(String key) async {
    final row = await (select(appSettingsTable)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) =>
      into(appSettingsTable).insertOnConflictUpdate(
        AppSettingsTableCompanion(
          key: Value(key),
          value: Value(value),
        ),
      );

  /// Delete a single key (no-op when absent).
  Future<void> deleteSetting(String key) =>
      (delete(appSettingsTable)..where((t) => t.key.equals(key))).go();

  Stream<String?> watchSetting(String key) =>
      (select(appSettingsTable)..where((t) => t.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);

  // --- Drafts ---

  Future<void> saveDraft(
    String conversationId,
    String text, {
    String? replyToLocalId,
  }) =>
      into(messageDraftsTable).insertOnConflictUpdate(
        MessageDraftsTableCompanion(
          conversationId: Value(conversationId),
          draftText: Value(text),
          replyToLocalId: Value(replyToLocalId),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<MessageDraftsTableData?> getDraft(String conversationId) =>
      (select(messageDraftsTable)
            ..where((t) => t.conversationId.equals(conversationId)))
          .getSingleOrNull();

  Future<void> clearDraft(String conversationId) =>
      (delete(messageDraftsTable)
            ..where((t) => t.conversationId.equals(conversationId)))
          .go();
}
