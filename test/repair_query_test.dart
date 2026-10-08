import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';

// T9: the plaintext column is gone — `decrypted` now maps to the row's
// decrypt_state (null ⇒ stuck 'key_missing' = repair target, body ⇒
// 'ready' = skipped). Same five-row matrix as before.
MessagesTableCompanion _row(String localId, {String? serverId,
    String type = 'text', String enc = 'enc', String? decrypted}) =>
    MessagesTableCompanion.insert(
      localId: localId,
      serverId: Value(serverId),
      conversationId: 'c1',
      senderId: 'u1',
      type: type,
      encryptedBody: enc,
      iv: 'iv',
      decryptState: Value(decrypted == null ? 'key_missing' : 'ready'),
      createdAt: DateTime(2026, 10, 5),
      updatedAt: DateTime(2026, 10, 5),
    );

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.test());
  tearDown(() => db.close());

  test('repair query finds only stuck non-media rows', () async {
    await db.messagesDao.upsertMessage(_row('a', serverId: 's1',
        decrypted: null)); // stuck text → repair target
    await db.messagesDao.upsertMessage(_row('b', serverId: 's2',
        decrypted: 'ok')); // fine → not targeted
    await db.messagesDao.upsertMessage(_row('c', serverId: 's3',
        type: 'image', decrypted: null)); // media (body optional) → skip
    await db.messagesDao.upsertMessage(_row('d')); // pending, no serverId → skip
    await db.messagesDao.upsertMessage(_row('e', serverId: 's5',
        enc: '__pending__', decrypted: null)); // optimistic marker → skip

    final rows = await db.messagesDao
        .getUndecryptableRows('c1', limit: 40);
    expect(rows.map((r) => r.localId), ['a']);
  });
}
