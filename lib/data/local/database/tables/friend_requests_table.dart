import 'package:drift/drift.dart';

class FriendRequestsTable extends Table {
  TextColumn get id => text()();
  TextColumn get fromUserId => text()();
  TextColumn get toUserId => text()();

  /// 'pending' | 'accepted' | 'declined'
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
