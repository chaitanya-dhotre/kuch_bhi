import 'package:drift/drift.dart';

class MessageMediaTable extends Table {
  TextColumn get id => text()();
  TextColumn get messageLocalId => text()();
  TextColumn get conversationId => text()();
  TextColumn get fileUrl => text().nullable()();
  TextColumn get localPath => text().nullable()();

  /// 'image' | 'video' | 'voice' | 'document'
  TextColumn get mediaType => text()();
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer().withDefault(const Constant(0))();
  IntColumn get durationSeconds => integer().nullable()();
  TextColumn get thumbnailUrl => text().nullable()();
  TextColumn get thumbnailLocalPath => text().nullable()();

  /// 'normal' | 'high'
  TextColumn get quality => text().withDefault(const Constant('normal'))();
  DateTimeColumn get expiresAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
