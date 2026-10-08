/// Task 3 — OutboxWorker: drain, backoff, error classes, FIFO, stale recovery.
///
/// Every test pins the brief's cases 1–8 + the two controller carry-ins
/// (C1 lingering-queued completion, C2 clearRetry null-clear) against
/// `lib/infrastructure/offline/outbox_worker.dart`.
///
/// Determinism rules: fake `now` (constant [fakeNow]) drives every schedule;
/// seeded `Random` drives jitter; senders are either recorders (FSM tests)
/// or the REAL repo sender behind a scripted MockClient (HTTP-class tests).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/outbox_table.dart';
import 'package:kuch_bhi/infrastructure/offline/outbox_worker.dart';

import 'char_harness.dart';

const _jsonHeaders = {'content-type': 'application/json'};

/// The fake clock every schedule in this file is measured against.
final DateTime fakeNow = DateTime.utc(2026, 6, 1, 12);

http.Response _err(int status) => http.Response(
      jsonEncode({'message': 'scripted $status', 'status': status}),
      status,
      headers: _jsonHeaders,
    );

Map<String, dynamic> _recordJson(String id) => {
      'id': id,
      'collectionId': 'messages',
      'collectionName': 'messages',
      'created': '2026-10-07T10:00:00.000Z',
      'updated': '2026-10-07T10:00:00.000Z',
      'fields': <String, dynamic>{},
      'conversation_id': 'g1',
      'sender_id': 'u_test',
      'type': 'text',
      'encrypted_body': '',
      'iv': '',
      'reply_to_id': '',
      'reply_preview': '',
      'is_deleted_for_everyone': false,
      'is_deleted_for_me': false,
      'is_pinned': false,
      'is_starred': false,
      'status': 'sent',
      'media_id': '',
    };

/// Seeds one message row (optional) + its outbox op in ONE transaction —
/// the local state a completed `sendMessage` enqueue produces.
Future<void> _seed(
  CharHarness h, {
  required String localId,
  required String opId,
  required int seq,
  String conv = 'g1',
  String kind = 'text_send',
  String? dependsOn,
  int attempts = 0,
  DateTime? nextAttemptAt,
  OutboxState state = OutboxState.queued,
  String msgStatus = 'pending',
  String? serverId,
  bool withMsg = true,
}) =>
    h.db.transaction(() async {
      if (withMsg) {
        await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
          localId: localId,
          conversationId: conv,
          senderId: 'u_test',
          type: 'text',
          encryptedBody: 'x',
          iv: '',
          status: Value(msgStatus),
          serverId: Value(serverId),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        // T9: the real sender reads plaintext from the session cache (the
        // column it used to read is gone) — seed it exactly like the old
        // decryptedBody column value did.
        bodyCache.put(localId, 'seeded $localId');
      }
      await h.db.outboxDao.enqueue(OutboxTableCompanion.insert(
        opId: opId,
        kind: kind,
        ref: localId,
        conversationId: conv,
        seq: seq,
        state: Value(state),
        attempts: Value(attempts),
        nextAttemptAt: Value(nextAttemptAt),
        dependsOn: Value(dependsOn),
        createdAt: DateTime.now(),
      ));
    });

Future<void> _seedConversation(CharHarness h, String id) =>
    h.db.conversationsDao.upsertConversation(ConversationsTableCompanion.insert(
          id: id,
          type: 'group',
          createdById: 'u_test',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ));

/// Scripted sender: records every invocation; per-op script entry decides —
/// an [OpSendOutcome] is returned, any other Object is thrown.
class _Recorder {
  final List<String> calls = [];
  final Map<String, Object> script = {};

  Future<OpSendOutcome> call(OutboxTableData op) async {
    calls.add(op.opId);
    final s = script[op.opId];
    if (s == null) return OpSendOutcome.sent;
    if (s is OpSendOutcome) return s;
    throw s;
  }
}

/// Worker under test: fake clock + seeded Random + harness daos.
/// [send] is the kind-sender callback (recorder, or the REAL repo sender).
OutboxWorker _worker(
  CharHarness h,
  Future<OpSendOutcome> Function(OutboxTableData op) send, {
  int seed = 42,
}) {
  final w = OutboxWorker(
    outbox: h.db.outboxDao,
    messages: h.db.messagesDao,
    settings: h.db.settingsDao,
    send: send,
    now: () => fakeNow,
    random: Random(seed),
  );
  addTearDown(w.dispose);
  return w;
}

/// Scripted MockClient factory for the REAL sender path: SSE hangs (Task 1
/// rule), message creates are scripted by [onCreate], everything else 404s.
/// The create counter lives in the FACTORY closure — pocketbase calls
/// `httpClientFactory` once per request, so a counter inside the client
/// itself would reset on every call.
http.Client Function() _clientFactory(
    http.Response Function(http.Request req, int nthCreate) onCreate) {
  var creates = 0;
  return () => MockClient((req) async {
        if (req.url.path.startsWith('/api/realtime')) {
          return Completer<http.Response>().future; // SSE hangs, never 404s
        }
        if (req.method == 'POST' &&
            req.url.path.contains('/collections/messages/records')) {
          creates++;
          return onCreate(req, creates);
        }
        return _err(404);
      });
}

void main() {
  // ── nextAttempt: pure FSM mapping (spec §6 / brief verbatim) ──────────
  test('nextAttempt maps error classes verbatim: terminal {400,403,404,413}, 401→pause, -1→null', () {
    for (final s in [400, 403, 404, 413]) {
      expect(
        () => nextAttempt(
          httpStatus: s,
          retryAfterHeader: null,
          attempts: 1,
          now: fakeNow,
          clock: () => fakeNow,
          random: Random(1),
        ),
        throwsA(isA<TerminalOpError>()
            .having((e) => e.statusCode, 'statusCode', s)),
        reason: 'HTTP $s is terminal (spec §6)',
      );
    }
    expect(
      () => nextAttempt(
        httpStatus: 401,
        retryAfterHeader: null,
        attempts: 1,
        now: fakeNow,
        clock: () => fakeNow,
        random: Random(1),
      ),
      throwsA(isA<PauseAllOpError>()),
      reason: '401 pauses the whole outbox — never terminal',
    );
    expect(
      nextAttempt(
        httpStatus: deferStatus,
        retryAfterHeader: null,
        attempts: 0,
        now: fakeNow,
        clock: () => fakeNow,
        random: Random(1),
      ),
      isNull,
      reason: 'local defer → stay queued with no schedule change',
    );
  });

  // ── Brief case 1 ──────────────────────────────────────────────────────
  test('404 on send → failedTerminal persists; NOT re-queued by later drains', () async {
    final h = charHarness(clientFactory: _clientFactory((req, nth) => _err(404)));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h); // REAL sender: repo.sendOutboxOp
    final w = _worker(h, repo.sendOutboxOp);

    await _seed(h, localId: 'l_404', opId: 'op404', seq: 1);

    await w.drain();
    final op = (await h.db.outboxDao.byId('op404'))!;
    expect(op.state, OutboxState.failedTerminal);
    expect(op.errorClass, 'dead_link', reason: 'HTTP 404 class name');
    expect(op.lastError, isNotNull);
    final msg = (await h.db.messagesDao.getMessageByLocalId('l_404'))!;
    expect(msg.status, 'failed', reason: 'terminal surfaces on the bubble');
    expect(msg.serverId, isNull, reason: 'never counted delivered');

    // Later drains must NOT re-queue or re-attempt it.
    await w.drain();
    await w.drain();
    final again = (await h.db.outboxDao.byId('op404'))!;
    expect(again.state, OutboxState.failedTerminal,
        reason: 'terminal persists across drains');
    expect(again.attempts, 0, reason: 'terminal never backoff-counts');
  });

  // ── Brief case 2 ──────────────────────────────────────────────────────
  test('401 on send → pause outbox_pause=auth, queue untouched; resume drains again', () async {
    final h = charHarness(clientFactory: _clientFactory((req, nth) {
      if (nth == 1) return _err(401);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode(_recordJson(body['id'] as String)), 200,
          headers: _jsonHeaders);
    }));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);
    final w = _worker(h, repo.sendOutboxOp);

    await _seed(h, localId: 'l_a', opId: 'op_a', seq: 1);
    await _seed(h, localId: 'l_b', opId: 'op_b', seq: 2);

    await w.drain();
    expect(await h.db.settingsDao.getSetting('outbox_pause'), 'auth',
        reason: 'brief: pause persisted under outbox_pause=auth');

    // Queue untouched: both still queued, no attempts, no schedule.
    for (final id in ['op_a', 'op_b']) {
      final row = (await h.db.outboxDao.byId(id))!;
      expect(row.state, OutboxState.queued, reason: '$id stays queued');
      expect(row.attempts, 0, reason: '$id attempts untouched');
      expect(row.nextAttemptAt, isNull, reason: '$id no schedule written');
      expect(row.errorClass, isNull, reason: '$id no error recorded');
    }
    final msgB = (await h.db.messagesDao.getMessageByLocalId('l_b'))!;
    expect(msgB.status, 'pending', reason: 'seq2 never attempted (pause stops the drain)');
    final pausedMsgA = (await h.db.messagesDao.getMessageByLocalId('l_a'))!;
    expect(pausedMsgA.status, 'pending', reason: '401 queue untouched — not failed');

    // Paused: a further drain sends nothing.
    await w.drain();
    expect(msgB.status, 'pending');

    // Resume → drains again (both ops now succeed).
    w.onAuthResumed();
    await w.drain();
    expect((await h.db.outboxDao.byId('op_a'))!.state, OutboxState.sent);
    expect((await h.db.outboxDao.byId('op_b'))!.state, OutboxState.sent);
    expect((await h.db.messagesDao.getMessageByLocalId('l_b'))!.serverId, isNotNull);
    final pauseAfter = await h.db.settingsDao.getSetting('outbox_pause');
    expect(pauseAfter == null || pauseAfter.isEmpty, isTrue,
        reason: 'resume clears the pause key');
  });

  // ── Brief case 3 ──────────────────────────────────────────────────────
  test('429 Retry-After: 7 → nextAttemptAt >= now+7s; no header → jittered backoff, cap 5 min', () async {
    // (a) Pure: Retry-After wins.
    final withHeader = nextAttempt(
      httpStatus: 429,
      retryAfterHeader: '7',
      attempts: 3,
      now: fakeNow,
      clock: () => fakeNow,
      random: Random(1),
    )!;
    expect(withHeader.isBefore(fakeNow.add(const Duration(seconds: 7))), isFalse,
        reason: 'brief: nextAttemptAt >= now+7s (fake clock)');

    // (b) Pure: no header → backoff within [base·2^n, base·2^n·1.25].
    for (var n = 0; n <= 5; n++) {
      final d = nextAttempt(
        httpStatus: 500,
        retryAfterHeader: null,
        attempts: n,
        now: fakeNow,
        clock: () => fakeNow,
        random: Random(3),
      )!;
      final us = d.difference(fakeNow).inMicroseconds;
      final baseUs = 5 * (1 << n) * 1000000;
      expect(us >= baseUs, isTrue,
          reason: 'n=$n: lower bound base·2^n = ${baseUs}us, got $us');
      expect(us <= (baseUs * 1.25).ceil(), isTrue,
          reason: 'n=$n: upper bound base·2^n·1.25, got $us');
    }

    // (c) Pure: cap — 5·2^10 would be 5120s; capped base is 300s → [300s, 375s].
    final capped = nextAttempt(
      httpStatus: 500,
      retryAfterHeader: null,
      attempts: 10,
      now: fakeNow,
      clock: () => fakeNow,
      random: Random(3),
    )!;
    final capUs = capped.difference(fakeNow).inMicroseconds;
    expect(capUs >= 300 * 1000000, isTrue, reason: 'cap floor 5 min, got $capUs');
    expect(capUs <= 375 * 1000000, isTrue, reason: 'cap·1.25 ceiling, got $capUs');

    // (d) Worker integration: 429 with Retry-After lands on the row.
    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final rec = _Recorder();
    rec.script['op_429'] = const OpSendException(429, retryAfterHeader: '7');
    final w = _worker(h, rec.call);
    await _seed(h, localId: 'l_429', opId: 'op_429', seq: 1);

    await w.drain();
    final row = (await h.db.outboxDao.byId('op_429'))!;
    expect(row.state, OutboxState.queued, reason: '429 is retryable');
    expect(row.attempts, 1);
    expect(row.errorClass, 'transient');
    expect(
      row.nextAttemptAt!.isBefore(fakeNow.add(const Duration(seconds: 7))),
      isFalse,
      reason: 'honors Retry-After: 7 on the stored row',
    );
    final msg = (await h.db.messagesDao.getMessageByLocalId('l_429'))!;
    expect(msg.status, 'pending',
        reason: 'transient failure is WAITING, not failed (spec §6)');
    expect(msg.serverId, isNull);

    // Not due until the schedule elapses.
    await w.drain();
    expect(rec.calls, ['op_429'], reason: 'backoff gate holds later drains');

    // (e) Worker integration: no header → jittered backoff on the row.
    final h2 = charHarness();
    addTearDown(h2.close);
    await seedConversationAndKey(h2);
    final rec3 = _Recorder();
    rec3.script['op_noheader'] = const OpSendException(429);
    final w3 = _worker(h2, rec3.call, seed: 7);
    await _seed(h2, localId: 'l_nh', opId: 'op_noheader', seq: 1);
    await w3.drain();
    final row3 = (await h2.db.outboxDao.byId('op_noheader'))!;
    final us3 = row3.nextAttemptAt!.difference(fakeNow).inMicroseconds;
    expect(us3 >= 10 * 1000000, isTrue,
        reason: 'attempts 0→1 ⇒ base 5·2^1 = 10s, got $us3');
    expect(us3 <= 12500000, isTrue, reason: '·1.25 ceiling, got $us3');
  });

  // ── Brief case 4 ──────────────────────────────────────────────────────
  test('connectivity restored → attempts reset to 0 and immediate drain (4-min backoff row sends now)', () async {
    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final rec = _Recorder();
    final w = _worker(h, rec.call);

    await _seed(
      h,
      localId: 'l_wait',
      opId: 'op_wait',
      seq: 1,
      attempts: 5,
      nextAttemptAt: fakeNow.add(const Duration(minutes: 4)),
    );

    // Before the event: not due, nothing sent.
    await w.drain();
    expect(rec.calls, isEmpty, reason: '4-min backoff gate holds the row');

    // Connectivity restored (moved listener hook).
    w.onConnectivityRestored();
    await w.drain();

    expect(rec.calls, ['op_wait'], reason: 'immediate drain after reset');
    final row = (await h.db.outboxDao.byId('op_wait'))!;
    expect(row.state, OutboxState.sent);
    expect(row.attempts, 0, reason: 'attempts reset to 0 on connectivity restore');
    expect(await h.db.messagesDao.getMessageByLocalId('l_wait'), isNotNull,
        reason: 'message row untouched by the FSM (sender stamps on success)');
  });

  // ── Brief case 5 ──────────────────────────────────────────────────────
  test('FIFO: failedTerminal head blocks conv; other conv drains; discardOp cascades via dependsOn', () async {
    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    await _seedConversation(h, 'g2');
    final rec = _Recorder();
    final w = _worker(h, rec.call);

    // g1: seq1 terminal head, seq2 queued behind it, seq3 dependent op.
    await _seed(h, localId: 'l1', opId: 'op1', seq: 1,
        state: OutboxState.failedTerminal, msgStatus: 'failed');
    await _seed(h, localId: 'l2', opId: 'op2', seq: 2);
    await _seed(h, localId: 'l3', opId: 'opx', seq: 3,
        kind: 'message_send', dependsOn: 'op1');
    // g2: independent conversation, must drain normally.
    await _seed(h, localId: 'l4', opId: 'opg', seq: 1, conv: 'g2');

    await w.drain();

    expect(rec.calls, ['opg'], reason: 'only the healthy conversation drains');
    expect((await h.db.outboxDao.byId('op2'))!.state, OutboxState.queued,
        reason: 'seq2 blocked behind failedTerminal head');
    expect((await h.db.outboxDao.byId('opx'))!.state, OutboxState.queued,
        reason: 'dependent op also behind the head');
    expect((await h.db.outboxDao.byId('opg'))!.state, OutboxState.sent);

    // Discard the terminal head → cascades to its dependent, unblocks seq2.
    await w.discardOp('op1');

    expect(await h.db.outboxDao.byId('op1'), isNull, reason: 'head removed');
    expect(await h.db.outboxDao.byId('opx'), isNull,
        reason: 'cascade: dependsOn=op1 removed');
    expect(await h.db.messagesDao.getMessageByLocalId('l1'), isNull,
        reason: 'discarded head message row deleted');
    expect(await h.db.messagesDao.getMessageByLocalId('l3'), isNull,
        reason: 'cascade: dependent message row deleted');
    expect(await h.db.messagesDao.getMessageByLocalId('l2'), isNotNull,
        reason: 'non-dependent message survives');
    final rows = await h.db.outboxDao.all();
    expect(rows.map((r) => r.opId).toSet(), {'op2', 'opg'},
        reason: 'only the two surviving ops remain');
    expect((await h.db.outboxDao.byId('op2'))!.state, OutboxState.sent,
        reason: 'discardOp drains: unblocked seq2 flows');
    expect(rec.calls, ['opg', 'op2']);
    expect(await h.db.messagesDao.countForConversation('g1'), 1);
  });

  // ── Brief case 6 ──────────────────────────────────────────────────────
  test('stale sending: rows in sending state at construction reset to queued (kill-mid-queue)', () async {
    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    await _seed(h, localId: 'l_stale', opId: 'op_stale', seq: 1,
        state: OutboxState.sending);

    final w = _worker(h, _Recorder().call);
    await w.ready; // construction-time recovery completes

    final row = (await h.db.outboxDao.byId('op_stale'))!;
    expect(row.state, OutboxState.queued,
        reason: 'kill mid-send → safe to re-run (idempotency key)');
    expect(row.attempts, 0);
  });

  // ── Brief case 7 ──────────────────────────────────────────────────────
  test('jitter uses injected Random — same seed → same delay (deterministic)', () {
    DateTime run(int seed) => nextAttempt(
          httpStatus: 503,
          retryAfterHeader: null,
          attempts: 4,
          now: fakeNow,
          clock: () => fakeNow,
          random: Random(seed),
        )!;

    final a1 = run(7);
    final a2 = run(7);
    expect(a1, a2, reason: 'same seed → identical delay across runs');
    final b = run(8);
    expect(b, isNot(a1), reason: 'different seed → different jitter draw');
    // Bounds still hold for the seeded draw (base 5·2^4 = 80s).
    final us = a1.difference(fakeNow).inMicroseconds;
    expect(us >= 80 * 1000000 && us <= 100 * 1000000, isTrue,
        reason: 'seeded draw stays inside [80s, 100s]');
  });

  // ── Brief case 8 ──────────────────────────────────────────────────────
  test('two-step media: message_send waits while media_upload is queued; drains after it is sent', () async {
    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final rec = _Recorder();
    final w = _worker(h, rec.call);

    // opA (upload) NOT due — scheduled 60s out; opB depends on it and IS due.
    await _seed(h, localId: 'blob1', opId: 'op_up', seq: 1,
        kind: 'media_upload', withMsg: false,
        nextAttemptAt: fakeNow.add(const Duration(seconds: 60)));
    await _seed(h, localId: 'l_send', opId: 'op_send', seq: 2,
        kind: 'message_send', dependsOn: 'op_up');

    await w.drain();
    expect(rec.calls, isEmpty,
        reason: 'dependent stays queued while its prerequisite is queued');
    expect((await h.db.outboxDao.byId('op_send'))!.state, OutboxState.queued);
    expect((await h.db.outboxDao.byId('op_up'))!.state, OutboxState.queued);

    // Prerequisite becomes due → single drain sends upload THEN dependent.
    await h.db.outboxDao.setState('op_up', OutboxState.queued,
        nextAttemptAt: fakeNow.subtract(const Duration(seconds: 1)));

    await w.drain();
    expect(rec.calls, ['op_up', 'op_send'],
        reason: 'spec §5.2: upload drains first, message_send only after sent');
    expect((await h.db.outboxDao.byId('op_up'))!.state, OutboxState.sent);
    expect((await h.db.outboxDao.byId('op_send'))!.state, OutboxState.sent);
  });

  // ── Controller carry-in 1 ─────────────────────────────────────────────
  test('carry-in: lingering queued op whose message already reached server completes idempotently — never re-created', () async {
    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final rec = _Recorder();
    final w = _worker(h, rec.call);

    // Task 2 interim drain sent WITHOUT opId: message stamped, op still queued.
    await _seed(h, localId: 'l_sent', opId: 'op_sent', seq: 1,
        msgStatus: 'sent', serverId: 'srv_sent');
    await _seed(h, localId: 'l_deliv', opId: 'op_deliv', seq: 2,
        msgStatus: 'delivered', serverId: 'srv_deliv');
    // A genuinely-new op behind them must still flow.
    await _seed(h, localId: 'l_new', opId: 'op_new', seq: 3);

    await w.drain();

    expect(rec.calls, ['op_new'],
        reason: 'acked ops never re-enter the sender (no duplicate server record)');
    expect((await h.db.outboxDao.byId('op_sent'))!.state, OutboxState.sent,
        reason: 'carry-in: sent message → op completed');
    expect((await h.db.outboxDao.byId('op_deliv'))!.state, OutboxState.sent,
        reason: 'carry-in: delivered message → op completed');
    expect((await h.db.outboxDao.byId('op_new'))!.state, OutboxState.sent);
    expect(await h.db.messagesDao.countForConversation('g1'), 3,
        reason: 'no message row duplicated');
    final sent = (await h.db.messagesDao.getMessageByLocalId('l_sent'))!;
    expect(sent.serverId, 'srv_sent');
    expect(sent.status, 'sent');
  });

  // ── Controller carry-in 2 ─────────────────────────────────────────────
  test('carry-in: retryOp clears retry metadata to NULL (clearRetry) and re-queues', () async {
    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final rec = _Recorder();
    final w = _worker(h, rec.call);

    // A terminal op carrying every error/retry field set.
    await _seed(
      h,
      localId: 'l_retry',
      opId: 'op_retry',
      seq: 1,
      state: OutboxState.failedTerminal,
      attempts: 3,
      nextAttemptAt: fakeNow.add(const Duration(minutes: 5)),
      msgStatus: 'failed',
    );
    await h.db.outboxDao.setState('op_retry', OutboxState.failedTerminal,
        attempts: 3,
        nextAttemptAt: fakeNow.add(const Duration(minutes: 5)),
        lastError: 'HTTP 404',
        errorClass: 'dead_link');

    await w.retryOp('op_retry');

    final row = (await h.db.outboxDao.byId('op_retry'))!;
    expect(row.state, OutboxState.sent,
        reason: 'retryOp re-queues then drains immediately');
    expect(row.attempts, 0, reason: 'attempts reset');
    expect(row.nextAttemptAt, isNull,
        reason: 'carry-in 2: clearRetry NULLs the schedule (setState cannot)');
    expect(row.lastError, isNull, reason: 'carry-in 2: lastError cleared');
    expect(row.errorClass, isNull, reason: 'carry-in 2: errorClass cleared');
    final msg = (await h.db.messagesDao.getMessageByLocalId('l_retry'))!;
    expect(msg.status, 'pending', reason: 'bubble leaves the failed state');
    expect(rec.calls, ['op_retry'], reason: 'retryOp drains immediately');
  });

  // ── Repo delegation (Task 4 banner entry points) ──────────────────────
  test('repo.retryOp / repo.discardOp delegate to the worker', () async {
    final h = charHarness(clientFactory: _clientFactory((req, nth) {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode(_recordJson(body['id'] as String)), 200,
          headers: _jsonHeaders);
    }));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    await _seedConversation(h, 'g2');
    final repo = buildRepo(h);

    await _seed(h, localId: 'l_r', opId: 'op_r', seq: 1,
        state: OutboxState.failedTerminal, msgStatus: 'failed');
    await _seed(h, localId: 'l_d', opId: 'op_d', seq: 1, conv: 'g2',
        state: OutboxState.failedTerminal, msgStatus: 'failed');

    await repo.retryOp('op_r');
    final retried = (await h.db.outboxDao.byId('op_r'))!;
    expect(retried.state, OutboxState.sent,
        reason: 'repo.retryOp routes through the worker drain');
    expect((await h.db.messagesDao.getMessageByLocalId('l_r'))!.status, 'sent');

    await repo.discardOp('op_d');
    expect(await h.db.outboxDao.byId('op_d'), isNull);
    expect(await h.db.messagesDao.getMessageByLocalId('l_d'), isNull);
  });

  // ── Fix R1: production unpause path (authStore seam) ───────────────────
  test('401 pause round-trips via authStore token save (production unpause path)', () async {
    final h = charHarness(clientFactory: _clientFactory((req, nth) {
      if (nth == 1) return _err(401);
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode(_recordJson(body['id'] as String)), 200,
          headers: _jsonHeaders);
    }));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);

    await _seed(h, localId: 'l_auth', opId: 'op_auth', seq: 1);

    // 1) Real 401-from-send → pause written by the production FSM path.
    await repo.outboxWorker.drain();
    expect(await h.db.settingsDao.getSetting('outbox_pause'), 'auth');
    expect((await h.db.outboxDao.byId('op_auth'))!.state, OutboxState.queued,
        reason: 'queue untouched, waiting for re-auth');
    expect((await h.db.messagesDao.getMessageByLocalId('l_auth'))!.status,
        'pending');

    // 2) Token save (login/refresh/rotation) → onChange listener →
    //    handleAuthStoreChange → onAuthResumed BEFORE the same-session
    //    early-return. Save a DIFFERENT but structurally valid JWT so
    //    sessionStillValid/authStore.isValid stay true for the re-send.
    h.pbClient.pb.authStore.save(_validJwt(4102444801), null);
    await Future<void>.delayed(const Duration(milliseconds: 20)); // stream + async listener
    await repo.outboxWorker.drain();

    expect(
      await h.db.settingsDao.getSetting('outbox_pause'),
      anyOf(isNull, isEmpty),
      reason: 'production seam cleared the 401 pause',
    );
    final row = (await h.db.outboxDao.byId('op_auth'))!;
    expect(row.state, OutboxState.sent,
        reason: 'queued op sends after re-auth');
    final msg = (await h.db.messagesDao.getMessageByLocalId('l_auth'))!;
    expect(msg.serverId, isNotNull);
    expect(msg.status, 'sent');
  });

  test('handleAuthStoreChange: empty token does NOT resume; non-empty does', () async {
    final h = charHarness(clientFactory: _clientFactory((req, nth) => _err(404)));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);

    await h.db.settingsDao.setSetting('outbox_pause', 'auth');

    // Logout/clear event (empty token) must NOT unpause via this seam —
    // the signOut wipe owns that path.
    repo.handleAuthStoreChange('');
    await Future<void>.delayed(Duration.zero);
    expect(await h.db.settingsDao.getSetting('outbox_pause'), 'auth',
        reason: 'empty token leaves the pause in place');

    // Any non-empty token save resumes (drain clears the key).
    repo.handleAuthStoreChange('any-session-token');
    await repo.outboxWorker.drain();
    expect(await h.db.settingsDao.getSetting('outbox_pause'),
        anyOf(isNull, isEmpty),
        reason: 'non-empty token releases the pause');
  });
}

/// Structurally valid JWT (3 parts, exp in the future) — same recipe as
/// char_harness's private `_fakeJwt`, with a distinct payload so a
/// rotation `save` carries a genuinely different token string.
String _validJwt(int expSeconds) {
  String enc(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m)));
  return '${enc(<String, Object>{'alg': 'HS256', 'typ': 'JWT'})}.'
      '${enc(<String, Object>{'exp': expSeconds})}.sig';
}
