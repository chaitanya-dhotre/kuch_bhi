import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/outbox_table.dart';
import 'package:kuch_bhi/infrastructure/ingest/ingest_batch.dart';
import 'package:kuch_bhi/infrastructure/ingest/ingest_boundary.dart';

import 'char_harness.dart';

/// Task 6 acceptance tests (brief Step 1) — IngestBoundary:
/// 1. same batch committed twice (SSE echo + fetch) → one row set,
///    cursor monotonic (no skip / no double-apply);
/// 2. tombstone in batch → row marked deleted; re-commit idempotent;
/// 3. epoch bumped mid-commit via injected hook → nothing written;
/// 4. drainAck: outbox.state + messages.status in the SAME transaction
///    (failure at the status-write stage → op stays queued);
/// 5. regression: test/offline/send_fetch_char_test.dart runs verbatim
///    (the 3 char tests) — executed with the suite, reported separately.
///
/// Test 3/4 drive `IngestBoundary.onBeforeWrite` — the injected hook the
/// brief places "between entry-check and write".

MessagesTableCompanion _row({
  String localId = 'l1',
  String serverId = 'srv1',
  String conversationId = 'g1',
  String senderId = 'u_peer',
}) =>
    MessagesTableCompanion.insert(
      localId: localId,
      serverId: Value(serverId),
      conversationId: conversationId,
      senderId: senderId,
      type: 'text',
      encryptedBody: 'ct',
      iv: 'iv',
      decryptedBody: Value('plain'),
      replyToId: const Value(null),
      replyPreview: const Value(null),
      expiresAt: const Value(null),
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 2),
    );

IngestBoundary _boundary(
  AppDatabase db, {
  int Function()? epoch,
  bool Function()? authValid,
}) =>
    IngestBoundary(
      db: db,
      epoch: epoch ?? (() => 0),
      authValid: authValid ?? (() => true),
    );

Future<DateTime?> _cursor(AppDatabase db, String convId) async {
  final raw = await db.settingsDao.getSetting('sync_cursor_$convId');
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

void main() {
  test(
      'same batch committed twice (SSE echo + fetch) → one row set, '
      'cursor monotonic (no skip/double-apply)', () async {
    final h = charHarness();
    addTearDown(h.close);
    final b = _boundary(h.db);

    final newest = DateTime.utc(2026, 1, 3);
    final batch = IngestBatch(
      upserts: [MessageUpsert(_row())],
      cursorAdvance: CursorDelta(conversationId: 'g1', to: newest),
    );

    // Delivery path 1: the SSE echo of a record…
    await b.commit(batch, IngestSource.sse);
    // …then the pull fetch re-delivers the SAME batch (SSE gap recovery).
    await b.commit(batch, IngestSource.fetch);

    expect(
      await h.db.messagesDao.countForConversation('g1'),
      1,
      reason: 'SSE echo + fetch of one record = exactly one row (no double-apply)',
    );
    expect(
      await h.db.messagesDao.getMessageByServerId('srv1'),
      isNotNull,
      reason: 'row is keyed by server id',
    );
    final cursor1 = await _cursor(h.db, 'g1');
    expect(cursor1, isNotNull);
    expect(cursor1!.millisecondsSinceEpoch,
        newest.millisecondsSinceEpoch,
        reason: 'cursor advanced with the batch');

    // A STALE batch (older cursor delta) must not rewind the cursor —
    // rewinding would re-fetch a window; advancing past data never fetched
    // would skip. Monotonic = neither.
    await b.commit(
      IngestBatch(
        upserts: [MessageUpsert(_row())],
        cursorAdvance: CursorDelta(
          conversationId: 'g1',
          to: DateTime.utc(2025, 12, 31),
        ),
      ),
      IngestSource.fetch,
    );
    final cursor2 = await _cursor(h.db, 'g1');
    expect(cursor2!.millisecondsSinceEpoch, newest.millisecondsSinceEpoch,
        reason: 'cursor is monotonic — an older delta cannot rewind it');
    expect(await h.db.messagesDao.countForConversation('g1'), 1,
        reason: 're-commit of the same row set is still exactly one row');
  });

  test('tombstone in batch → row marked deleted; re-commit idempotent',
      () async {
    final h = charHarness();
    addTearDown(h.close);
    final b = _boundary(h.db);
    await h.db.messagesDao.upsertMessage(_row(localId: 'l_t', serverId: 'srvT'));

    await b.commit(const IngestBatch(tombstones: ['srvT']), IngestSource.fetch);
    var row = await h.db.messagesDao.getMessageByServerId('srvT');
    expect(row, isNotNull, reason: 'tombstone flags the row, never hard-deletes');
    expect(row!.isDeletedForEveryone, isTrue,
        reason: 'row marked deleted-for-everyone');

    // Re-commit (SSE echo of the same delete) must be a no-op, not a
    // duplicate row and not a crash.
    await b.commit(const IngestBatch(tombstones: ['srvT']), IngestSource.sse);
    row = await h.db.messagesDao.getMessageByServerId('srvT');
    expect(row, isNotNull);
    expect(row!.isDeletedForEveryone, isTrue);
    expect(await h.db.messagesDao.countForConversation('g1'), 1,
        reason: 're-commit idempotent — one row');
  });

  test(
      'epoch bumped mid-commit (hook between entry-check and write) → '
      'nothing written', () async {
    final h = charHarness();
    addTearDown(h.close);
    var epoch = 0;
    final b = _boundary(h.db, epoch: () => epoch);
    // Simulate logout/account-switch landing between the entry epoch check
    // and the write: the hook bumps the live counter.
    b.onBeforeWrite = () => epoch++;

    await b.commit(
      IngestBatch(
        upserts: [MessageUpsert(_row())],
        cursorAdvance: CursorDelta(
          conversationId: 'g1',
          to: DateTime.utc(2026, 1, 3),
        ),
      ),
      IngestSource.fetch,
    );

    expect(await h.db.messagesDao.countForConversation('g1'), 0,
        reason: 'stale-session commit must write NO rows');
    expect(await _cursor(h.db, 'g1'), isNull,
        reason: 'cursor must not advance for an aborted commit');
  });

  test(
      'drainAck: outbox.state + messages.status + cursor update in the SAME '
      'transaction (failure at status write → all rolled back)', () async {
    final h = charHarness();
    addTearDown(h.close);
    final b = _boundary(h.db);

    // Task 2 _seedOp shape: optimistic message row + queued outbox op.
    const opId = 'opack0000000001';
    await h.db.transaction(() async {
      await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId: 'l_ack',
        conversationId: 'g1',
        senderId: 'u_test',
        type: 'text',
        encryptedBody: 'x',
        iv: '',
        decryptedBody: Value('seeded'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      await h.db.outboxDao.enqueue(OutboxTableCompanion.insert(
        opId: opId,
        kind: 'text_send',
        ref: 'l_ack',
        conversationId: 'g1',
        seq: 1,
        createdAt: DateTime.now(),
      ));
    });

    final cursorTo = DateTime.utc(2026, 1, 5);
    final batch = IngestBatch(
      ack: OutboxAck(
        opId: opId,
        serverId: opId,
        senderId: 'u_test',
        conversationId: 'g1',
      ),
      cursorAdvance: CursorDelta(conversationId: 'g1', to: cursorTo),
    );

    // Fix round 1/I2: all three concerns (outbox state flip, message
    // status stamp, cursor advance) execute BEFORE the injected failure —
    // a sequential (non-txn) implementation would persist all three; the
    // rollback must leave every one of them unchanged.
    b.onBeforeWrite =
        () => throw StateError('injected status-write failure');
    await expectLater(
      b.commit(batch, IngestSource.drainAck),
      throwsStateError,
    );
    b.onBeforeWrite = null;

    var op = await h.db.outboxDao.byId(opId);
    expect(op!.state, OutboxState.queued,
        reason: 'setState(sent) executed in-txn then rolled back');
    var msg = await h.db.messagesDao.getMessageByLocalId('l_ack');
    expect(msg!.serverId, isNull,
        reason: 'message stamp executed in-txn then rolled back');
    expect(msg.status, 'pending');
    expect(await _cursor(h.db, 'g1'), isNull,
        reason: 'cursor advance executed in-txn then rolled back');

    // Control: identical batch without the injected failure lands ALL
    // THREE writes together (dual-truth rule — spec §5.1/§7).
    await b.commit(batch, IngestSource.drainAck);
    op = await h.db.outboxDao.byId(opId);
    expect(op!.state, OutboxState.sent);
    msg = await h.db.messagesDao.getMessageByLocalId('l_ack');
    expect(msg!.serverId, opId);
    expect(msg.status, 'sent');
    final cursor = await _cursor(h.db, 'g1');
    expect(cursor, isNotNull);
    expect(cursor!.millisecondsSinceEpoch, cursorTo.millisecondsSinceEpoch,
        reason: 'cursor advanced with the ack batch');
    expect(await h.db.messagesDao.countForConversation('g1'), 1,
        reason: 'ack stamps the existing row — never a second one');
  });

  test('I1: SSE pin/delete companion preserves expiresAt through the boundary',
      () async {
    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);

    // Disappearing-message row: expiresAt is load-bearing (row auto-hide).
    final expiresAt = DateTime.utc(2026, 2, 1);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'l_exp',
      serverId: Value('srvE'),
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: 'ct',
      iv: 'iv',
      decryptedBody: Value('plain'),
      expiresAt: Value(expiresAt),
      createdAt: DateTime.utc(2026, 1, 2),
      updatedAt: DateTime.utc(2026, 1, 2),
    ));
    final existing = (await h.db.messagesDao.getMessageByServerId('srvE'))!;
    expect(existing.expiresAt, isNotNull, reason: 'seeded expiry present');

    // SSE pin toggle → the PRODUCTION companion (repo seam) → boundary.
    await repo.ingestBoundary.commit(
      IngestBatch(upserts: [
        MessageUpsert(repo.ssePinDeleteCompanion(
          existing: existing,
          serverPinned: true,
          serverDeleted: false,
        )),
      ]),
      IngestSource.sse,
    );

    final after = (await h.db.messagesDao.getMessageByServerId('srvE'))!;
    expect(after.isPinned, isTrue, reason: 'server pin applied');
    expect(after.expiresAt, isNotNull,
        reason: 'I1: delete-then-insert rebuilds from the companion — a '
            'missing expiresAt column would reset it to NULL');
    expect(after.expiresAt!.millisecondsSinceEpoch,
        expiresAt.millisecondsSinceEpoch,
        reason: 'expiry preserved across the SSE pin upsert');
    expect(await h.db.messagesDao.countForConversation('g1'), 1,
        reason: 'still exactly one row');
  });
}
