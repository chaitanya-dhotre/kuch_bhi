import 'dart:async';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart' show ClientException;

import '../../data/local/database/app_database.dart';
import '../../data/local/database/daos/messages_dao.dart';
import '../../data/local/database/daos/outbox_dao.dart';
import '../../data/local/database/daos/settings_dao.dart';
import '../../data/local/database/tables/outbox_table.dart';

/// `nextAttempt` status for a LOCAL defer: no HTTP exchange happened
/// (key not ready, session not ready, …). Returns `null` → the op stays
/// `queued` with NO schedule change; it is retried on the next drain
/// trigger (connectivity, new send, resume).
const int deferStatus = -1;

/// settingsDao key holding the global outbox pause reason.
/// `'auth'` = paused by a 401 until re-auth (brief §Interfaces).
const String kOutboxPauseKey = 'outbox_pause';

/// Value written to [kOutboxPauseKey] on a 401; any NON-empty value pauses.
const String kOutboxPauseAuth = 'auth';

/// Spec §6 terminal class: {400, 403, 404, 413} → `failed_terminal`.
/// The caller (worker) sets `state=failedTerminal` + `errorClass`.
class TerminalOpError implements Exception {
  const TerminalOpError(this.statusCode);
  final int statusCode;

  @override
  String toString() => 'TerminalOpError(HTTP $statusCode)';
}

/// Spec §6: HTTP 401 pauses the ENTIRE outbox until re-auth — never
/// terminal, never drops queued work.
class PauseAllOpError implements Exception {
  const PauseAllOpError();

  @override
  String toString() => 'PauseAllOpError(HTTP 401)';
}

/// Sender-raised HTTP failure that carries what PocketBase's SDK drops:
/// the `Retry-After` header (the pocketbase client discards response
/// headers, so the production sender cannot supply this — see handoff).
class OpSendException implements Exception {
  const OpSendException(this.statusCode, {this.retryAfterHeader});
  final int statusCode;
  final String? retryAfterHeader;

  @override
  String toString() =>
      'OpSendException(HTTP $statusCode, retry-after: $retryAfterHeader)';
}

/// Kind-sender outcome (see `MessageRepositoryImpl.sendOutboxOp`).
enum OpSendOutcome {
  /// Send succeeded and the sender acked (message row + outbox `sent`).
  sent,

  /// Local defer: the sender could not/need not send now. The worker
  /// re-queues the op with NO schedule change — unless the sender already
  /// moved the row itself (terminal verdicts), which is left untouched.
  deferred,
}

/// The worker's single kind-sender hook. Dispatches on `op.kind` inside
/// the repository; HTTP failures are thrown ([ClientException] /
/// [OpSendException]) for `nextAttempt` classification.
typedef OpSender = Future<OpSendOutcome> Function(OutboxTableData op);

/// Spec §6 terminal error-class labels (column comment in outbox_table.dart).
String terminalErrorClass(int statusCode) => switch (statusCode) {
      400 => 'bad_request',
      403 => 'forbidden',
      404 => 'dead_link',
      413 => 'payload_too_large',
      _ => 'http_$statusCode',
    };

/// Spec §6 error classes as a pure function (unit-testable).
///
/// Returns null = stay queued with no schedule change; else nextAttemptAt.
/// - `{400, 403, 404, 413}` → throw [TerminalOpError] (caller sets failedTerminal)
/// - `401` → throw [PauseAllOpError] (caller pauses the whole outbox)
/// - [deferStatus] (`-1`) → `null` (local defer, no schedule change)
/// - `429` → `now + Retry-After` when the header parses, else backoff
/// - everything transient → `now + min(300s, 5s·2^attempts)·(1 + rand·0.25)`
///
/// [now] is the scheduling clock (fake-clock friendly). [clock] is accepted
/// for brief-signature fidelity; scheduling uses [now].
DateTime? nextAttempt({
  required int httpStatus,
  required String? retryAfterHeader,
  required int attempts,
  required DateTime now,
  required DateTime Function() clock,
  required Random random,
}) {
  switch (httpStatus) {
    case 400:
    case 403:
    case 404:
    case 413:
      throw TerminalOpError(httpStatus);
    case 401:
      throw const PauseAllOpError();
    case deferStatus:
      return null;
    case 429:
      final secs = int.tryParse((retryAfterHeader ?? '').trim());
      if (secs != null && secs >= 0) {
        return now.add(Duration(seconds: secs));
      }
      break; // unparseable/absent Retry-After → exponential backoff
  }
  // backoff = min(300s, 5s * 2^attempts) * (1 + random.nextDouble()*0.25)
  final baseSec = min(300.0, 5.0 * pow(2, attempts));
  final delayUs = (baseSec * (1 + random.nextDouble() * 0.25) * 1000000).round();
  return now.add(Duration(microseconds: delayUs));
}

/// Outbox FSM driver (spec §5.2/§6): loads due ops FIFO by
/// `(conversationId, seq)`, gates them (pause / terminal head / backoff /
/// `dependsOn`), marks `sending`, runs the kind sender and maps failures
/// through [nextAttempt].
///
/// Lifecycle hooks (moved from `MessageRepositoryImpl._initConnectivityRetry`):
/// - construction → connectivity listener + stale-`sending` recovery ([ready]);
/// - [onConnectivityRestored] → attempts reset for all queued + immediate drain;
/// - [onAuthPaused] / [onAuthResumed] → global pause via settingsDao
///   [kOutboxPauseKey].
class OutboxWorker {
  OutboxWorker({
    required OutboxDao outbox,
    required MessagesDao messages,
    required SettingsDao settings,
    required OpSender send,
    DateTime Function()? now,
    Random? random,
  })  : _outbox = outbox,
        _messages = messages,
        _settings = settings,
        _send = send,
        _now = now ?? DateTime.now,
        _random = random ?? Random() {
    // Moved VERBATIM from MessageRepositoryImpl._initConnectivityRetry
    // (only the action inside the `if` changed per brief → worker hook).
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        debugPrint('[Outbox] Connectivity restored. Resetting attempts + drain.');
        onConnectivityRestored();
      }
    });
    // Spec §6 stale `sending`: a kill mid-send leaves rows in `sending`;
    // idempotency keys make re-send harmless, so reset them on startup.
    _ready = _recoverStaleSending();
  }

  final OutboxDao _outbox;
  final MessagesDao _messages;
  final SettingsDao _settings;
  final OpSender _send;
  final DateTime Function() _now;
  final Random _random;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  late final Future<void> _ready;
  bool _resetQueued = false;
  bool _resumeRequested = false;
  Future<void>? _draining;
  bool _rerun = false;

  /// Completes when construction-time stale-`sending` recovery finished.
  /// Tests await this before asserting recovery; [drain] awaits it anyway.
  Future<void> get ready => _ready;

  /// Cancels the connectivity listener (tests / repo teardown).
  void dispose() {
    _connSub?.cancel();
    _connSub = null;
  }

  // ── Hooks ──────────────────────────────────────────────────────────────

  /// Connectivity restored: attempts → 0 and schedule cleared for every
  /// queued op, then an immediate drain (spec §6 — a user who just
  /// reconnected must not wait out a 5-minute backoff).
  void onConnectivityRestored() {
    _resetQueued = true;
    kick();
  }

  /// External auth-state hook: [paused] true writes [kOutboxPauseAuth]
  /// under [kOutboxPauseKey]; false clears it (no drain — see
  /// [onAuthResumed] for the drain-on-reauth hook).
  void onAuthPaused(bool paused) {
    unawaited(_settings.setSetting(kOutboxPauseKey, paused ? kOutboxPauseAuth : ''));
  }

  /// Re-auth succeeded: clear the global pause, then drain.
  void onAuthResumed() {
    _resumeRequested = true;
    kick();
  }

  /// Fire-and-forget [drain] for hooks that cannot await (sendMessage kick,
  /// connectivity, auth resume). Errors are logged, never thrown.
  void kick() => unawaited(
      drain().catchError((Object e) => debugPrint('[Outbox] drain failed: $e')));

  // ── Drain loop ─────────────────────────────────────────────────────────

  /// Runs one full drain pass (serialized: concurrent callers coalesce onto
  /// the in-flight pass and get ONE extra pass afterwards, so
  /// `await drain()` always returns after a pass that observed your writes).
  Future<void> drain() {
    final inFlight = _draining;
    if (inFlight != null) {
      _rerun = true;
      return inFlight;
    }
    final run = _runLoop();
    _draining = run;
    return run;
  }

  Future<void> _runLoop() async {
    try {
      do {
        _rerun = false;
        await _pass();
      } while (_rerun);
    } finally {
      _draining = null;
    }
  }

  Future<void> _pass() async {
    await _ready;
    if (_resetQueued) {
      _resetQueued = false;
      await _outbox.clearRetryQueued();
    }
    if (_resumeRequested) {
      _resumeRequested = false;
      await _settings.setSetting(kOutboxPauseKey, '');
    }
    if (await _isPaused()) return;

    // Carry-in C1: Task 2's interim drain sent WITHOUT opId — complete
    // those ops idempotently BEFORE any send attempt (never re-create).
    await _completeAckedOps();

    final due = await _outbox.due(_now());
    if (due.isEmpty) return;
    final dueIds = {for (final o in due) o.opId};

    // due() is ordered (conversationId, seq); group first-seen.
    final convs = <String>[];
    for (final o in due) {
      if (!convs.contains(o.conversationId)) convs.add(o.conversationId);
    }

    for (final convId in convs) {
      if (await _isPaused()) return;
      final ops = await _outbox.forConversation(convId);
      for (final op in ops) {
        if (op.state == OutboxState.sent) continue;
        // Spec §6 ordering: a non-queued head (failedTerminal/sending) or a
        // not-yet-due head blocks every later op in this conversation.
        if (op.state != OutboxState.queued) break;
        if (!dueIds.contains(op.opId)) break;
        // Spec §5.2 two-step: dependsOn must be `sent` first.
        if (op.dependsOn != null) {
          final dep = await _outbox.byId(op.dependsOn!);
          if (dep == null || dep.state != OutboxState.sent) break;
        }

        await _processOne(op);

        final after = await _outbox.byId(op.opId);
        if (after == null) continue; // removed mid-flight → keep walking
        if (after.state != OutboxState.sent) break; // terminal/backoff/defer
        if (await _isPaused()) return;
      }
    }
  }

  /// Sends ONE op: `sending` → sender → map outcome/error via FSM.
  Future<void> _processOne(OutboxTableData op) async {
    await _outbox.setState(op.opId, OutboxState.sending);
    try {
      final outcome = await _send(op);
      final cur = await _outbox.byId(op.opId);
      if (cur == null) return; // discarded/removed by the sender
      if (cur.state != OutboxState.sending) return; // sender moved it itself
      if (outcome == OpSendOutcome.sent) {
        await _outbox.setState(op.opId, OutboxState.sent, attempts: 0);
      } else {
        await _outbox.setState(op.opId, OutboxState.queued);
      }
    } catch (e) {
      await _applyFailure(op, e);
    }
  }

  /// Classifies [error] through [nextAttempt] and writes the FSM transition.
  Future<void> _applyFailure(OutboxTableData op, Object error) async {
    final int status;
    final String? retryAfter;
    if (error is OpSendException) {
      status = error.statusCode;
      retryAfter = error.retryAfterHeader;
    } else if (error is ClientException) {
      status = error.statusCode;
      retryAfter = null;
    } else if (error is TerminalOpError) {
      status = error.statusCode;
      retryAfter = null;
    } else if (error is PauseAllOpError) {
      status = 401;
      retryAfter = null;
    } else {
      // Transport/local unknown (pocketbase maps network errors to
      // statusCode 0) → transient class → backoff.
      status = 0;
      retryAfter = null;
    }
    final err = '$error';
    final attempts = op.attempts + 1;

    DateTime? next;
    try {
      next = nextAttempt(
        httpStatus: status,
        retryAfterHeader: retryAfter,
        attempts: attempts,
        now: _now(),
        clock: _now,
        random: _random,
      );
    } on TerminalOpError {
      await _outbox.setState(
        op.opId,
        OutboxState.failedTerminal,
        lastError: err,
        errorClass: terminalErrorClass(status),
      );
      // Dual-truth: the bubble shows the failed state; queued→pending
      // stays the WAITING state (spec §6 — waiting ≠ needs-user-action).
      final msg = await _messages.getMessageByLocalId(op.ref);
      if (msg != null && msg.status == 'pending') {
        await _messages.updateMessageStatus(op.ref, 'failed');
      }
      return;
    } on PauseAllOpError {
      // Brief case 2: queue untouched (state restored, no attempts/schedule).
      await _outbox.setState(op.opId, OutboxState.queued);
      await _settings.setSetting(kOutboxPauseKey, kOutboxPauseAuth);
      return;
    }

    if (next == null) {
      // Local defer: stay queued, no schedule change.
      await _outbox.setState(op.opId, OutboxState.queued);
      return;
    }
    await _outbox.setState(
      op.opId,
      OutboxState.queued,
      attempts: attempts,
      nextAttemptAt: next,
      lastError: err,
      errorClass: 'transient',
    );
  }

  // ── Recovery / bookkeeping ─────────────────────────────────────────────

  /// Spec §6 stale `sending` on startup: `sending → queued` (kill mid-queue).
  Future<void> _recoverStaleSending() async {
    final rows = await _outbox.all();
    var recovered = 0;
    for (final r in rows) {
      if (r.state == OutboxState.sending) {
        await _outbox.setState(r.opId, OutboxState.queued);
        recovered++;
      }
    }
    if (recovered > 0) {
      debugPrint('[Outbox] Recovered $recovered stale sending op(s) → queued.');
    }
  }

  /// Carry-in C1: complete queued ops whose message row ALREADY reached the
  /// server (Task 2's interim drain sent without opId). Idempotent — never
  /// re-creates a server record.
  Future<void> _completeAckedOps() async {
    final ops = await _outbox.all();
    for (final op in ops) {
      if (op.state != OutboxState.queued) continue;
      final msg = await _messages.getMessageByLocalId(op.ref);
      if (msg == null) continue;
      final status = msg.status;
      if (msg.serverId != null &&
          msg.serverId!.isNotEmpty &&
          (status == 'sent' || status == 'delivered' || status == 'read')) {
        await _outbox.setState(op.opId, OutboxState.sent, attempts: 0);
      }
    }
  }

  Future<bool> _isPaused() async =>
      (await _settings.getSetting(kOutboxPauseKey))?.isNotEmpty ?? false;

  // ── Task 4 banner entry points ─────────────────────────────────────────

  /// Retry a (typically `failedTerminal`) op: clears retry metadata back
  /// to NULL/0 (carry-in C2 — [OutboxDao.setState] cannot NULL fields),
  /// re-queues, unsticks the bubble, drains.
  Future<void> retryOp(String opId) async {
    final op = await _outbox.byId(opId);
    if (op == null) return;
    await _outbox.clearRetry(opId);
    await _outbox.setState(opId, OutboxState.queued);
    final msg = await _messages.getMessageByLocalId(op.ref);
    if (msg != null && msg.status == 'failed') {
      await _messages.updateMessageStatus(op.ref, 'pending');
    }
    await drain();
  }

  /// Discard an op + EVERY op that (transitively) `dependsOn` it, together
  /// with their local message rows (spec §5.2 cascade), then drain — the
  /// next FIFO op in the conversation flows immediately.
  ///
  /// Delete order = messages first: a kill between the two deletes leaves
  /// orphan ops (harmless defers) rather than orphan messages that
  /// `retryPendingMessages` would re-enqueue.
  Future<void> discardOp(String opId) async {
    final all = await _outbox.all();
    final ids = <String>{};
    void collect(String id) {
      if (!ids.add(id)) return;
      for (final o in all.where((o) => o.dependsOn == id)) {
        collect(o.opId);
      }
    }

    collect(opId);
    for (final o in all) {
      if (ids.contains(o.opId)) {
        await _messages.deleteByLocalId(o.ref);
      }
    }
    for (final id in ids) {
      await _outbox.deleteOp(id);
    }
    await drain();
  }
}
