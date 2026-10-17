import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/decrypt/decrypt_pass.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';

import 'char_harness.dart';

/// Fixed cold-display workload: the same 40 text rows a chat/home preview
/// read can request after the process resumes and bodyCache was cleared.
/// Run with --reporter expanded; the printed timings are the comparison data.
void main() {
  test('cold decrypt benchmark: 40 cached group messages', () async {
    final h = charHarness();
    addTearDown(h.close);
    await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
    await seedConversationAndKey(h);

    final ids = <String>[];
    for (var i = 0; i < 40; i++) {
      final id = 'perf_$i';
      final encrypted = await h.encryption.encryptMessage(
        'cold-start message $i',
        fixtureGroupKey,
      );
      ids.add(id);
      await h.db.messagesDao.upsertMessage(
        MessagesTableCompanion.insert(
          localId: id,
          conversationId: 'g1',
          senderId: 'u_peer',
          type: 'text',
          encryptedBody: encrypted.ciphertext,
          iv: encrypted.iv,
          serverId: Value('server_$i'),
          createdAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)),
          updatedAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)),
        ),
      );
    }

    bodyCache.clear();
    final pass = DecryptPass(db: h.db, enc: h.encryption, epoch: () => 0);
    final watch = Stopwatch()..start();
    await pass.runFor(ids);
    watch.stop();

    expect(bodyCache.length, 40);
    // Machine-readable output for before/after comparison.
    // ignore: avoid_print
    print('PERF cold_decrypt_40_ms=${watch.elapsedMilliseconds}');
  });
}
