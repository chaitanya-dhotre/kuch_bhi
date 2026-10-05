import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/migrations/dedup_sql.dart';

MessagesTableCompanion _row(String localId, {String? serverId}) =>
    MessagesTableCompanion.insert(
      localId: localId,
      serverId: Value(serverId),
      conversationId: 'c1',
      senderId: 'u1',
      type: 'text',
      encryptedBody: 'enc',
      iv: 'iv',
      createdAt: DateTime(2026, 10, 4),
      updatedAt: DateTime(2026, 10, 4),
    );

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.test());
  tearDown(() => db.close());

  test('pending rows with null serverId coexist under the unique index',
      () async {
    await db.messagesDao.upsertMessage(_row('a'));
    await db.messagesDao.upsertMessage(_row('b'));
    final rows = await db.select(db.messagesTable).get();
    expect(rows.length, 2); // both null-serverId pendings kept
  });

  test('bg placeholder upsert updates the existing row (no duplicate)',
      () async {
    await db.messagesDao.upsertMessage(_row('main-uuid', serverId: 's1'));
    await db.messagesDao.upsertMessageByServerId(
        _row('s1', serverId: 's1')); // FCM bg isolate shape
    final rows = await db.select(db.messagesTable).get();
    expect(rows.length, 1);
    expect(rows.single.localId, 'main-uuid');
  });

  test('dedupe SQL keeps the oldest row per serverId', () async {
    // Migration sequence: dupes can only exist BEFORE the index exists.
    await db.customStatement('DROP INDEX IF EXISTS idx_messages_server_id');
    await db.customStatement(
        "INSERT INTO messages_table (local_id, server_id, conversation_id, "
        "sender_id, type, encrypted_body, iv, status, created_at, updated_at) "
        "VALUES ('main-uuid', 's1', 'c1', 'u1', 'text', 'e', 'i', 'sent', "
        "1791088200000, 1791088200000)");
    await db.customStatement(
        "INSERT INTO messages_table (local_id, server_id, conversation_id, "
        "sender_id, type, encrypted_body, iv, status, created_at, updated_at) "
        "VALUES ('s1', 's1', 'c1', 'u1', 'text', 'e', 'i', 'delivered', "
        "1791088201000, 1791088201000)");
    await db.customStatement(DedupBeforeUniqueIndex.sql);
    // The migration's index creation now succeeds (would throw if dupes
    // survived the dedupe).
    await db.customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_server_id '
        'ON messages_table (server_id) WHERE server_id IS NOT NULL');
    final rows = await db.select(db.messagesTable).get();
    expect(rows.length, 1);
    expect(rows.single.localId, 'main-uuid'); // oldest rowid wins
  });

  test('deleteByServerIdExcept clears the placeholder so the stamp lands',
      () async {
    // Real upload race: optimistic row pending (null serverId) + FCM bg
    // placeholder already holds the id. Without the guard the stamp throws
    // a unique violation.
    await db.messagesDao.upsertMessage(_row('main-uuid'));
    await db.messagesDao.upsertMessageByServerId(_row('s1', serverId: 's1'));
    await db.messagesDao.deleteByServerIdExcept('s1', 'main-uuid');
    await db.messagesDao.upsertMessage(_row('main-uuid', serverId: 's1'));
    final rows = await db.select(db.messagesTable).get();
    expect(rows.length, 1);
    expect(rows.single.localId, 'main-uuid');
  });
}
