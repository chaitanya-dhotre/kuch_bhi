import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/decrypt/body_cache.dart';
import '../../core/utils/session_epoch.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/outbox_table.dart';
import 'ingest_batch.dart';

/// Session epoch moved between a commit's entry check and its write gate —
/// thrown INSIDE the commit transaction so every prior write in it rolls
/// back, then caught by [IngestBoundary.commit], logged and swallowed
/// (spec §7 abort semantics: silent, never surfaced to the caller).
class _EpochAbort implements Exception {
  const _EpochAbort(this.what);
  final String what;
  @override
  String toString() => 'IngestEpochAbort($what)';
}

/// IngestBoundary — SOLE writer of network-sourced message records
/// (spec §4/§7). Every SSE, pull-fetch and drain-ack record write funnels
/// through [commit]:
///
/// * **ONE transaction per batch** carrying the message upserts (by server
///   id), tombstone flag flips, the per-conversation sync-cursor advance
///   and the drain-ack `outbox.state` + `messages.status` dual-truth flip —
///   atomically, so an SSE gap plus a pull fetch can neither skip nor
///   double-apply.
/// * **Session-epoch guard** (spec §7/§11, MediaBlobStore's pattern):
///   epoch captured at entry, re-checked immediately before the write; an
///   invalid epoch aborts the WHOLE commit (silent, logged) — a logout
///   mid-commit never repopulates the wiped store.
/// * **Always-commit (Task 7, spec §7):** commit never consults keys —
///   a batch whose companions carry `decryptState='key_missing'` rows
///   lands exactly like any other, cursor included. Key resolution is a
///   reader/repair concern (DecryptPass, Task 8), never a commit gate.
///
/// The repo keeps fetch/SSE orchestration (network, decrypt, flag
/// preservation) and hands the boundary fully-built companions — the
/// boundary never parses records, never touches keys, never advances a
/// cursor outside [IngestBatch.cursorAdvance].
class IngestBoundary {
  IngestBoundary({
    required AppDatabase db,
    required int Function() epoch,
    required bool Function() authValid,
    Future<void> Function(String serverId)? forgetMedia,
  })  : _db = db,
        _epoch = epoch,
        _authValid = authValid,
        _forgetMedia = forgetMedia;

  final AppDatabase _db;

  /// delete-everyone-leftovers B2: drops a newly deleted message's local
  /// media (`MediaBlobStore.forgetLocal` in production). Runs after the
  /// transaction; a kill before it is caught by the repo's start-up sweep.
  final Future<void> Function(String serverId)? _forgetMedia;

  /// Session-epoch seam (spec §11): the repo's live `_sessionEpoch`
  /// counter, bumped on logout/account switch. Tests inject a mutable
  /// holder (same seam shape as MediaBlobStore's `epoch:`).
  final int Function() _epoch;

  /// `pb.authStore.isValid` in production — completes the
  /// `sessionStillValid` triple (Review C1).
  final bool Function() _authValid;

  /// Test seam (Task 6 brief tests 3 + 4): invoked INSIDE the commit
  /// transaction, after the entry epoch check and immediately before the
  /// message-row/cursor writes. For a drain-ack batch it fires after the
  /// in-txn `outbox.setState(sent)` flip — so a failure injected here must
  /// roll that flip back (the same-transaction coupling proof). Null in
  /// production.
  @visibleForTesting
  void Function()? onBeforeWrite;

  bool _stillValid(int epochAtStart, String what) {
    if (sessionStillValid(
      epochAtStart: epochAtStart,
      currentEpoch: _epoch(),
      authValid: _authValid(),
    )) {
      return true;
    }
    debugPrint('[Ingest] $what dropped — session ended (spec §7 epoch guard)');
    return false;
  }

  /// Single entry for network-sourced record writes (spec §7): one Drift
  /// transaction per batch, in three phases —
  ///   1. drain-ack writes + cursor advance,
  ///   2. [onBeforeWrite] hook + the single epoch re-check,
  ///   3. message upserts + tombstones.
  /// Epoch is checked at entry (outside the txn) and re-checked in phase 2.
  /// Phase-1 writes sit BEFORE that check deliberately (fix round 1/I2):
  /// all three dual-truth concerns — `outbox.state`, `messages.status`,
  /// sync cursor — are then covered by ONE abort: an invalid epoch or a
  /// hook failure rolls the whole txn back, so none of them can survive
  /// alone. A commit whose epoch went stale writes NOTHING and returns
  /// silently; real write errors propagate to the caller's existing catch
  /// handling.
  Future<void> commit(IngestBatch batch, IngestSource source) async {
    final epochAtStart = _epoch();
    if (!_stillValid(epochAtStart, 'commit($source) at entry')) return;
    // B1/B2: rows this commit leaves deleted for everyone. Their bodies are
    // dropped from the cache; media only for rows not already deleted.
    final deletedLocalIds = <String>{};
    final newlyDeleted = <String>{};
    try {
      await _db.transaction(() async {
        // ── Phase 1a — drain ack (Task 2 semantics, carry-in 1): the op
        // read joins the txn; state flip → message stamp (T2's
        // message-first order swapped — LEDGERED seam: only observable
        // under injected failure, where the swap is what makes the
        // rollback proof non-vacuous; the pair still lands or aborts
        // together, which is all spec §5.1/§7 requires).
        final ack = batch.ack;
        // final ⇒ null-check promotion stays valid inside the nested
        // `..where((t) => ...)` closure below.
        final OutboxTableData? op =
            ack == null ? null : await _db.outboxDao.byId(ack.opId);
        // F-b: a text deleted meanwhile keeps its tombstone and its op stays
        // unsent, so its sender (or restart recovery) still marks the server.
        final cancelled = op != null &&
            (await _db.messagesDao.getMessageByLocalId(op.ref))?.status ==
                'cancelled';
        if (ack != null && !cancelled) {
          await _db.outboxDao.setState(ack.opId, OutboxState.sent);
        }
        // ── Phase 1b — Drain-ack message stamp — byte-identical WHERE/SET
        // to Task 2's interim body (localId=op.ref guarded by
        // sender+conversation).
        if (ack != null && op != null && !cancelled) {
          await (_db.update(_db.messagesTable)
                ..where((t) =>
                    t.localId.equals(op.ref) &
                    t.senderId.equals(ack.senderId) &
                    t.conversationId.equals(ack.conversationId)))
              .write(MessagesTableCompanion(
            serverId: Value(ack.serverId),
            status: const Value('sent'),
            updatedAt: Value(DateTime.now()),
          ));
        }
        // ── Phase 1c — cursor advance in the SAME txn as the batch
        // (spec §7), before the re-check so the abort covers it too.
        await _advanceCursor(batch.cursorAdvance);

        // ── Phase 2 — injected hook + the single epoch re-check (spec §7).
        // Everything written above rolls back if this aborts; the writes
        // below never run — one check guards the whole atomic unit.
        onBeforeWrite?.call();
        if (!_stillValid(epochAtStart, 'commit($source) before write')) {
          throw const _EpochAbort('epoch moved between entry and write');
        }

        // ── Phase 3a — Message upserts (by server id). Delete-then-insert
        // mechanics moved verbatim from `_cacheMessagesBatch`: clearing
        // prior cache rows + FCM placeholders first means ONE collision
        // cannot abort the whole batch; companions carry preserved flags
        // and a stable localId, so re-committing the same batch is an
        // idempotent upsert (SSE echo + fetch converge on one row set).
        if (batch.upserts.isNotEmpty) {
          final serverIds = <String>[
            for (final u in batch.upserts)
              if (u.row.serverId.present && u.row.serverId.value != null)
                u.row.serverId.value!,
          ];
          // A media send cancelled locally (status `cancelled`, the server
          // copy not marked yet) stays cancelled, even when the cancel landed
          // after the caller read the rows its companions were built from.
          final cancelled = await _db.messagesDao.cancelledSendIds(serverIds);
          final wasDeleted = await _deletedServerIds(serverIds);
          await _db.messagesDao.deleteByServerIds(serverIds);
          await _db.batch((b) {
            for (final u in batch.upserts) {
              var row = cancelled.contains(u.row.serverId.value)
                  ? u.row.copyWith(
                      isDeletedForEveryone: const Value(true),
                      status: const Value('cancelled'),
                    )
                  : u.row;
              if (row.isDeletedForEveryone.present &&
                  row.isDeletedForEveryone.value) {
                // B1: a deleted message keeps no ciphertext on the phone.
                row = row.copyWith(
                  encryptedBody: const Value(''),
                  iv: const Value(''),
                );
                deletedLocalIds.add(row.localId.value);
                final sid = row.serverId.value;
                if (sid != null && !wasDeleted.contains(sid)) {
                  newlyDeleted.add(sid);
                }
              }
              b.insert(_db.messagesTable, row,
                  onConflict: DoUpdate((_) => row,
                      target: [_db.messagesTable.localId]));
            }
          });
        }

        // ── Phase 3b — Tombstones (spec §7): idempotent flag upsert by
        // server id — a repeat (SSE echo of the same delete) rewrites the
        // same values; an unknown id is a no-op.
        if (batch.tombstones.isNotEmpty) {
          final rows = await (_db.select(_db.messagesTable)
                ..where((t) => t.serverId.isIn(batch.tombstones)))
              .get();
          for (final r in rows) {
            deletedLocalIds.add(r.localId);
            if (!r.isDeletedForEveryone) newlyDeleted.add(r.serverId!);
          }
        }
        for (final id in batch.tombstones) {
          await (_db.update(_db.messagesTable)
                ..where((t) => t.serverId.equals(id)))
              .write(MessagesTableCompanion(
            isDeletedForEveryone: const Value(true),
            encryptedBody: const Value(''), // B1
            iv: const Value(''),
            updatedAt: Value(DateTime.now()),
          ));
        }
      });
    } on _EpochAbort catch (e) {
      debugPrint('[Ingest] commit($source) aborted — $e');
      return;
    }
    for (final id in deletedLocalIds) {
      bodyCache.remove(id);
    }
    for (final sid in newlyDeleted) {
      try {
        await _forgetMedia?.call(sid);
      } catch (e) {
        debugPrint('[Ingest] forget media $sid: $e'); // start-up sweep retries
      }
    }
  }

  /// Server ids among [ids] whose local row is already deleted for everyone.
  Future<Set<String>> _deletedServerIds(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final rows = await (_db.select(_db.messagesTable)
          ..where((t) =>
              t.serverId.isIn(ids) & t.isDeletedForEveryone.equals(true)))
        .get();
    return {for (final r in rows) r.serverId!};
  }

  /// Monotonic cursor advance: equal = no-op, older = never rewinds (a
  /// stale batch cannot move the cursor back; only data-backed advances
  /// move it forward — no skip by construction). Writes the same
  /// `sync_cursor_<conv>` key `_writeCursor` used to (UTC ISO).
  Future<void> _advanceCursor(CursorDelta? delta) async {
    if (delta == null) return;
    final key = 'sync_cursor_${delta.conversationId}';
    final raw = await _db.settingsDao.getSetting(key);
    final current =
        raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
    if (current == null || delta.to.isAfter(current)) {
      await _db.settingsDao
          .setSetting(key, delta.to.toUtc().toIso8601String());
    }
  }
}
