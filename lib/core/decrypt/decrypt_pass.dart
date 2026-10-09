import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../utils/chunk_ids.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/app_settings_table.dart';
import '../../services/encryption_service.dart';
import 'body_cache.dart';

/// Batch decrypt orchestrator (spec §8, Task 8) — the SOLE DecryptPass
/// writer of `decrypt_state`/`key_id` verdicts beyond ingest (spec §4
/// reader/repair concern).
///
/// Isolate model (spec §8, isolates share no memory):
/// - Key material is resolved on the MAIN isolate (secure storage lives
///   there) and passed to the crypto worker as plain data only.
/// - Crypto runs inline for ≤50 rows (no hop overhead for the common
///   interactive case) and inside [Isolate.run] for ≥51 rows (search-scale
///   batches); both lanes run the same top-level [_decryptBatch] worker.
/// - ONLY the main isolate applies results: DB state writes + body-cache
///   population + provider notification ([onApplied]). The worker never
///   touches Drift or the cache.
///
/// Session-epoch guard (spec §11, T5/T6 pattern): the epoch is captured at
/// [runFor] entry and re-checked before EVERY db write and the cache put —
/// results landing after logout/account-switch are dropped, never applied.
///
/// `key_id` population (Task 7 left it null): a successful decrypt writes
/// the sha256 fingerprint of the key bytes used — the spec §5.1 "key/epoch
/// reference" — so a later rotation (fingerprint mismatch on a MAC failure)
/// re-queues the row as `key_missing` instead of terminal `failed`.
class DecryptPass {
  DecryptPass({
    required AppDatabase db,
    required EncryptionService enc,
    required int Function() epoch,
  })  : _db = db,
        _enc = enc,
        _epoch = epoch;

  final AppDatabase _db;
  final EncryptionService _enc;
  final int Function() _epoch;

  /// Test seam: awaited after crypto, before the epoch-checked apply —
  /// models the isolate result landing (brief test 2 injects its async
  /// gap here, before the session bump).
  @visibleForTesting
  Future<void> Function()? beforeApply;

  /// Provider invalidation hook — wired by `decryptPassProvider`
  /// (spec §8 apply step: DB updates + bodyCache.put + provider
  /// notification). Applied ids are the rows whose bodies just landed.
  void Function(List<String> appliedIds)? onApplied;

  /// Lane counters (spec §8: ≤50 inline on main, ≥51 via Isolate.run) —
  /// brief test 5 pins both.
  @visibleForTesting
  int inlineCalls = 0;

  @visibleForTesting
  int isolateCalls = 0;

  static const int _inlineLaneMax = 50;

  /// Decrypts [messageIds] and applies the results.
  ///
  /// Row contract:
  /// - `decrypt_state='failed'` → skipped at load (terminal, never retried);
  /// - empty / `__pending__` ciphertext → skipped (nothing decryptable —
  ///   media captions and optimistic rows);
  /// - key resolves + decrypt ok → `ready` + `key_id` + bodyCache.put;
  /// - key resolves + bad MAC (keyId matches or is unset) → `failed`;
  /// - key resolves + bad MAC + keyId mismatch → `key_missing` (rotation —
  ///   await the right key, spec §8);
  /// - key unresolvable → row (re)marked `key_missing`.
  ///
  /// Decrypted plaintext goes ONLY into [bodyCache] — never back into
  /// `decrypted_body` (spec §3: no plaintext at rest; the column is
  /// dropped in Task 9).
  Future<void> runFor(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    final epochAtSchedule = _epoch(); // spec §11: captured at schedule

    // 1. Load the requested rows (chunked — SQLite bind cap, chunkIds I3).
    final rows = <MessagesTableData>[];
    for (final chunk in chunkIds(messageIds.toSet().toList(), 500)) {
      rows.addAll(await (_db.select(_db.messagesTable)
            ..where((t) => t.localId.isIn(chunk)))
          .get());
    }

    // 2. Filter + group by conversation; remember load-time states so the
    //    apply step can skip no-op writes (drift stream churn on re-reads).
    final byConv = <String, List<MessagesTableData>>{};
    final prevStates = <String, String>{};
    final prevKeyIds = <String, String?>{};
    for (final row in rows) {
      if (row.decryptState == 'failed') continue; // terminal — spec §8
      if (row.encryptedBody.isEmpty || row.encryptedBody == '__pending__') {
        continue; // nothing decryptable (media / optimistic pending row)
      }
      byConv.putIfAbsent(row.conversationId, () => []).add(row);
      prevStates[row.localId] = row.decryptState;
      prevKeyIds[row.localId] = row.keyId;
    }
    if (byConv.isEmpty) return;

    // 3. Keys resolved MAIN-SIDE (secure storage / db-cached peer keys) —
    //    passed to the worker as plain data only (spec §8 isolate model).
    final keyless = <MessagesTableData>[];
    final groups = <_KeyGroup>[];
    for (final entry in byConv.entries) {
      final key = await _resolveKey(entry.key);
      if (key == null || key.length != 32) {
        keyless.addAll(entry.value);
        continue;
      }
      groups.add(_KeyGroup(
        key: key,
        fingerprint: DecryptPass.fingerprintOf(key),
        rows: entry.value,
      ));
    }

    // 4. Crypto lane: ≤50 items inline on main, ≥51 via Isolate.run.
    final totalItems = groups.fold<int>(0, (n, g) => n + g.rows.length);
    final useIsolate = totalItems > _inlineLaneMax;
    final outcomes = <Map<String, Object?>>[];
    for (final g in groups) {
      final items = <Map<String, Object?>>[
        for (final r in g.rows)
          {
            'id': r.localId,
            'ciphertext': r.encryptedBody,
            'iv': r.iv,
            'keyId': r.keyId,
          },
      ];
      if (useIsolate) {
        isolateCalls++;
        final key = g.key;
        final fp = g.fingerprint;
        outcomes.addAll(await Isolate.run(() => _decryptBatch(items, key, fp)));
      } else {
        inlineCalls++;
        outcomes.addAll(await _decryptBatch(items, g.key, g.fingerprint));
      }
    }

    // 5. Test seam — "result about to land" (brief test 2's async gap).
    if (beforeApply != null) await beforeApply!();

    // 6. Apply — epoch re-checked before EVERY db write and the cache put
    //    (spec §11, T5 guard style: silent drop + debugPrint).
    final applied = <String>[];
    for (final row in keyless) {
      if (row.decryptState == 'key_missing') continue; // already correct
      if (!_stillValid(epochAtSchedule, 'key_missing write')) return;
      await (_db.update(_db.messagesTable)
            ..where((t) => t.localId.equals(row.localId)))
          .write(const MessagesTableCompanion(
              decryptState: Value('key_missing')));
    }
    for (final o in outcomes) {
      final id = o['id'] as String;
      final state = o['state'] as String;
      final plain = o['plain'] as String?;
      final fp = o['fingerprint'] as String;

      // Skip no-op verdict writes: a `ready` row already carrying this
      // fingerprint, or a row already `key_missing`, needs no UPDATE —
      // re-reads must not churn the drift stream.
      final needsWrite = state == 'failed'
          ? true
          : state == 'ready'
              ? !(prevStates[id] == 'ready' && prevKeyIds[id] == fp)
              : prevStates[id] != 'key_missing';
      if (needsWrite) {
        if (!_stillValid(epochAtSchedule, 'apply $id')) return;
        final companion = state == 'ready'
            ? MessagesTableCompanion(
                decryptState: const Value('ready'), keyId: Value(fp))
            : MessagesTableCompanion(decryptState: Value(state));
        await (_db.update(_db.messagesTable)
              ..where((t) => t.localId.equals(id)))
            .write(companion);
      }
      if (state == 'ready') {
        if (!_stillValid(epochAtSchedule, 'cache put $id')) return;
        bodyCache.put(id, plain!);
        applied.add(id);
      }
    }
    if (applied.isNotEmpty) onApplied?.call(applied);
  }

  /// T5 `_stillValid` style: the session that captured [epochAtStart] is
  /// still current — false ⇒ caller ABORTS (no throw, spec §11).
  bool _stillValid(int epochAtStart, String what) {
    if (epochAtStart == _epoch()) return true;
    debugPrint('[Decrypt] $what dropped — session epoch changed');
    return false;
  }

  /// Conversation key for [convId] without leaving the main isolate's
  /// storage access: groups read the secure-storage cache (network
  /// fallback mirrors `_getConvKey`), DMs derive from the db-cached peer
  /// public key. Any failure ⇒ null ⇒ rows stay/mark `key_missing`.
  Future<List<int>?> _resolveKey(String convId) async {
    try {
      final conv = await _db.conversationsDao.getConversationById(convId);
      if (conv == null) return null;
      final myId =
          (await _db.settingsDao.getSetting(AppSettingsKeys.currentUserId)) ??
              '';
      if (conv.type == 'group') {
        return await _enc.getOrFetchGroupKey(convId, myId);
      }
      if (myId.isEmpty) return null;
      final otherUserId = await _otherMemberId(convId, myId);
      if (otherUserId == null) return null;
      final user = await _db.usersDao.getUserById(otherUserId);
      final pub = user?.publicKey;
      if (pub == null || pub.isEmpty) return null;
      return await _enc.getOrDeriveConversationKey(convId, pub);
    } catch (_) {
      return null; // MissingKeyException / offline / bad peer key
    }
  }

  Future<String?> _otherMemberId(String convId, String myId) async {
    final members = await _db.conversationsDao.getMembersForConversation(convId);
    final other = members
        .where((m) => m.userId != myId)
        .map((m) => m.userId)
        .firstOrNull;
    return (other == null || other.isEmpty) ? null : other;
  }

  /// The spec §5.1 `key_id` "key reference": sha256(key) hex — changes
  /// exactly when the key rotates, so a mismatching row awaits the new key
  /// instead of being terminal-failed (spec §8 rotation rule).
  ///
  /// Deliberately PUBLIC (not `@visibleForTesting`): the C1
  /// encryption-at-enqueue path in the repository stamps the SAME `key_id`
  /// this class writes on a successful decrypt. Two different fingerprints
  /// for one key would make the rotation rule re-queue rows that never
  /// rotated, so the computation must be shared, not duplicated.
  static String fingerprintOf(List<int> key) {
    final digest = Sha256().toSync().hashSync(key);
    return digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

/// One conversation's key + rows in a [runFor] batch.
class _KeyGroup {
  _KeyGroup({
    required this.key,
    required this.fingerprint,
    required this.rows,
  });

  final List<int> key;
  final String fingerprint;
  final List<MessagesTableData> rows;
}

/// Crypto worker — runs INLINE on main for ≤50-row batches and inside
/// `Isolate.run` for ≥51 (spec §8). Takes only plain sendable data,
/// returns the spec's `(messageId, plaintext, newState)` tuples as maps
/// (isolate messages are JSON-ish values, not Dart records).
Future<List<Map<String, Object?>>> _decryptBatch(
  List<Map<String, Object?>> items,
  List<int> key,
  String fingerprint,
) async {
  final aes = AesGcm.with256bits();
  final secretKey = await aes.newSecretKeyFromBytes(key);
  final out = <Map<String, Object?>>[];
  for (final item in items) {
    final id = item['id'] as String;
    String? plain;
    try {
      final nonce = base64.decode(item['iv'] as String);
      final all = base64.decode(item['ciphertext'] as String);
      final ct = all.sublist(0, all.length - 16);
      final mac = Mac(all.sublist(all.length - 16));
      final clear = await aes.decrypt(
        SecretBox(ct, nonce: nonce, mac: mac),
        secretKey: secretKey,
      );
      plain = utf8.decode(clear);
    } catch (_) {
      plain = null; // bad MAC / parse — verdict below
    }
    final prevKeyId = item['keyId'] as String?;
    final String state;
    if (plain != null) {
      state = 'ready';
    } else if (prevKeyId != null && prevKeyId != fingerprint) {
      // Rotation: ciphertext belongs to another key — re-queue, never
      // terminal (spec §8 "key_id mismatch rows are re-queued").
      state = 'key_missing';
    } else {
      state = 'failed'; // correct key, corrupt/tampered ciphertext
    }
    out.add({
      'id': id,
      'plain': plain,
      'state': state,
      'fingerprint': fingerprint,
    });
  }
  return out;
}
