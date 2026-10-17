import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter/foundation.dart';

import '../utils/chunk_ids.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/app_settings_table.dart';
import '../../services/encryption_service.dart';
import 'body_cache.dart';
import 'device_key_store.dart';

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
    DeviceKeyStore? deviceKeys,
  }) : _db = db,
       _enc = enc,
       _epoch = epoch,
       _deviceKeys = deviceKeys {
    // Local-first decrypt (loading-issue fix): the encryption service
    // revalidates group keys in the background after answering from the
    // cache; when that hydration lands NEW versions, re-run exactly the
    // rows this pass could not open (rotation-while-closed edge).
    _enc.onGroupKeysRefreshed = _onGroupKeysRefreshed;
  }

  final AppDatabase _db;
  final EncryptionService _enc;
  final int Function() _epoch;

  /// P8: the device-local key that wraps keyless-enqueue bodies. Null in
  /// unit tests that build a bare [DecryptPass] — a `device_sealed` row
  /// then stays unresolvable and the placeholder law covers it (the row is
  /// never blank, and the op still drains: the drain unwraps through the
  /// repository's own [DeviceKeyStore]).
  final DeviceKeyStore? _deviceKeys;

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

  /// Rows a past [runFor] could NOT open, per conversation — the re-run
  /// set for a background key hydration that lands new versions
  /// ([_onGroupKeysRefreshed]). Entries are dropped as soon as any later
  /// run resolves them.
  final Map<String, Set<String>> _unresolvedByConv = {};

  /// Conversations whose `grew=true` hydration arrived while no unresolved
  /// record existed yet (fast refresh beating the apply step) — consumed
  /// at the end of the next [runFor] that records unresolved rows there.
  final Set<String> _grewNoticed = {};

  /// Server-side group-key hydration landed MORE versions than the local
  /// first answer held — re-queue rows the stale set could not open and
  /// run them again. `failed` verdicts made under an incomplete key set are
  /// unsound, so they are re-queued (scoped to exactly these ids; the
  /// spec-§8 terminal rule for genuinely corrupt rows still holds: the
  /// re-run re-derives `failed` under the FULL key set).
  Future<void> _rerunAfterKeyGrowth(String convId, Set<String> ids) async {
    try {
      await (_db.update(_db.messagesTable)..where(
            (t) =>
                t.localId.isIn(ids.toList()) & t.decryptState.equals('failed'),
          ))
          .write(
            const MessagesTableCompanion(decryptState: Value('key_missing')),
          );
      debugPrint('[Decrypt] key growth re-run conv=$convId ids=${ids.length}');
      await runFor(ids.toList());
    } catch (e) {
      debugPrint('[Decrypt] post-refresh re-run failed: $e');
    }
  }

  void _onGroupKeysRefreshed(String convId, bool grew) {
    if (!grew) return;
    final ids = _unresolvedByConv.remove(convId);
    if (ids == null || ids.isEmpty) {
      _grewNoticed.add(convId); // apply still running — consumed at its end
      return;
    }
    unawaited(_rerunAfterKeyGrowth(convId, ids));
  }

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
    // C3/B (review #72): a paused purge landing mid-pass must not be
    // repopulated by this pass's completion — put is suppressed when the
    // cache generation moved; the DB verdict still lands (metadata).
    final purgeGenAtSchedule = bodyCache.generation;

    // 1. Load the requested rows (chunked — SQLite bind cap, chunkIds I3).
    final rows = <MessagesTableData>[];
    for (final chunk in chunkIds(messageIds.toSet().toList(), 500)) {
      rows.addAll(
        await (_db.select(
          _db.messagesTable,
        )..where((t) => t.localId.isIn(chunk))).get(),
      );
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
    //
    // P8: device-sealed rows never need the conversation key at all — the
    // body is wrapped with the device-local key, so they resolve their own
    // group (and stay grouped by conversation for the apply step's
    // no-op-write bookkeeping).
    final keyless = <MessagesTableData>[];
    final groups = <_KeyGroup>[];
    final sealed = <MessagesTableData>[];
    final pendingKeys = <MapEntry<String, List<MessagesTableData>>>[];
    for (final entry in byConv.entries) {
      final (convRows, sealedRows) = _splitSealed(entry.value);
      sealed.addAll(sealedRows);
      if (convRows.isEmpty) continue;
      pendingKeys.add(MapEntry(entry.key, convRows));
    }

    // C (2026-10-14): resolve every conversation's keys CONCURRENTLY —
    // the sequential per-conv awaits serialized N platform-channel/storage
    // hops into the ~2s chat-open lock (30s warm prefetch on M52). The
    // account id is read ONCE per pass instead of once per conversation,
    // and EncryptionService's process-lifetime key memory (single-flight
    // load) keeps concurrent first touches on ONE storage scan.
    final myId =
        (await _db.settingsDao.getSetting(AppSettingsKeys.currentUserId)) ??
        '';
    final resolved = await Future.wait([
      for (final entry in pendingKeys) _resolveKeys(entry.key, myId),
    ]);
    for (var i = 0; i < pendingKeys.length; i++) {
      final keys = resolved[i];
      if (keys.isEmpty) {
        keyless.addAll(pendingKeys[i].value);
        continue;
      }
      groups.add(
        _KeyGroup(
          keys: keys,
          fingerprints: [
            for (final key in keys) DecryptPass.fingerprintOf(key),
          ],
          rows: pendingKeys[i].value,
        ),
      );
    }
    if (sealed.isNotEmpty) {
      // One resolve serves every sealed row (same device key each time).
      final key = await _deviceKey();
      for (final row in sealed) {
        if (key == null || key.length != 32) {
          keyless.add(row);
          continue;
        }
        groups.add(
          _KeyGroup(
            keys: [key],
            fingerprints: [DecryptPass.fingerprintOf(key)],
            rows: [row],
          ),
        );
      }
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
        final keys = g.keys;
        final fingerprints = g.fingerprints;
        outcomes.addAll(
          await Isolate.run(() => _decryptBatch(items, keys, fingerprints)),
        );
      } else {
        inlineCalls++;
        outcomes.addAll(await _decryptBatch(items, g.keys, g.fingerprints));
      }
    }

    // 5. Test seam — "result about to land" (brief test 2's async gap).
    if (beforeApply != null) await beforeApply!();

    // 6. Apply — epoch re-checked before EVERY db write and the cache put
    //    (spec §11, T5 guard style: silent drop + debugPrint).
    final applied = <String>[];
    for (final row in keyless) {
      if (row.decryptState == 'key_missing') continue; // already correct
      if (row.decryptState == kDeviceSealedState) continue; // P8: stay sealed
      if (!_stillValid(epochAtSchedule, 'key_missing write')) return;
      await (_db.update(
        _db.messagesTable,
      )..where((t) => t.localId.equals(row.localId))).write(
        const MessagesTableCompanion(decryptState: Value('key_missing')),
      );
    }
    for (final o in outcomes) {
      final id = o['id'] as String;
      final state = o['state'] as String;
      final plain = o['plain'] as String?;
      final fp = o['fingerprint'] as String;

      // P8: a device-sealed row unwraps to the CACHE only. Its at-rest
      // state must stay `device_sealed` — the ciphertext is still under the
      // device key (the drain promotes it to group-key `ready` at send
      // time), so flipping to `ready` here would lie about which key opens
      // the row and would let the group-visibility gate promise a body the
      // group key cannot produce.
      if (state == 'ready' && prevStates[id] == kDeviceSealedState) {
        if (!_stillValid(epochAtSchedule, 'cache put $id')) return;
        if (bodyCache.generation == purgeGenAtSchedule) {
          bodyCache.put(id, plain!);
        } else {
          debugPrint('[Msg] cache put $id suppressed — purge mid-pass');
        }
        applied.add(id);
        continue;
      }

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
                decryptState: const Value('ready'),
                keyId: Value(fp),
              )
            : MessagesTableCompanion(decryptState: Value(state));
        await (_db.update(
          _db.messagesTable,
        )..where((t) => t.localId.equals(id))).write(companion);
      }
      if (state == 'ready') {
        if (!_stillValid(epochAtSchedule, 'cache put $id')) return;
        if (bodyCache.generation == purgeGenAtSchedule) {
          bodyCache.put(id, plain!);
        } else {
          debugPrint('[Msg] cache put $id suppressed — purge mid-pass');
        }
        applied.add(id);
      }
    }
    if (applied.isNotEmpty) onApplied?.call(applied);

    // Bookkeeping for the background key-refresh retry: drop rows a later
    // run resolved, add this run's unresolved rows (media/pending rows
    // excluded — nothing to decrypt), then consume any `grew` notice that
    // arrived while THIS run was still applying.
    final appliedIds = applied.toSet();
    _unresolvedByConv
      ..updateAll((_, ids) => ids.difference(appliedIds))
      ..removeWhere((_, ids) => ids.isEmpty);
    for (final r in rows) {
      if (r.encryptedBody.isEmpty || r.encryptedBody == '__pending__') {
        continue;
      }
      if (appliedIds.contains(r.localId)) continue;
      _unresolvedByConv.putIfAbsent(r.conversationId, () => {}).add(r.localId);
    }
    final grewConvs = [
      for (final c in _unresolvedByConv.keys)
        if (_grewNoticed.contains(c)) c,
    ];
    for (final c in grewConvs) {
      _grewNoticed.remove(c);
      final ids = _unresolvedByConv.remove(c);
      if (ids != null && ids.isNotEmpty) {
        unawaited(_rerunAfterKeyGrowth(c, ids));
      }
    }
  }

  /// T5 `_stillValid` style: the session that captured [epochAtStart] is
  /// still current — false ⇒ caller ABORTS (no throw, spec §11).
  bool _stillValid(int epochAtStart, String what) {
    if (epochAtStart == _epoch()) return true;
    debugPrint('[Decrypt] $what dropped — session epoch changed');
    return false;
  }

  /// P8: splits a conversation's rows into (conversation-key rows,
  /// device-sealed rows). A sealed row's ciphertext is under the device key,
  /// so it must never be handed the conversation key — that swap would read
  /// as a MAC failure and mark the row terminal.
  (List<MessagesTableData>, List<MessagesTableData>) _splitSealed(
    List<MessagesTableData> rows,
  ) {
    final convRows = <MessagesTableData>[];
    final sealedRows = <MessagesTableData>[];
    for (final r in rows) {
      if (r.decryptState == kDeviceSealedState) {
        sealedRows.add(r);
      } else {
        convRows.add(r);
      }
    }
    return (convRows, sealedRows);
  }

  /// P8: the device-local key, or null when the store is not wired (bare
  /// test [DecryptPass]) or secure storage holds nothing usable.
  Future<List<int>?> _deviceKey() async {
    final store = _deviceKeys;
    if (store == null) return null;
    try {
      return await store.resolve();
    } catch (e) {
      debugPrint('[Decrypt] P8 device key unavailable: $e');
      return null;
    }
  }

  /// Conversation key for [convId] without leaving the main isolate's
  /// storage access: groups read the process-memory key cache (storage
  /// scan once per process — C 2026-10-14), DMs derive from the db-cached
  /// peer public key. Any failure ⇒ empty ⇒ rows stay/mark `key_missing`.
  /// [myId] is resolved once per runFor pass (C) — callers run these
  /// concurrently via Future.wait.
  Future<List<List<int>>> _resolveKeys(String convId, String myId) async {
    try {
      final conv = await _db.conversationsDao.getConversationById(convId);
      if (conv == null) return const [];
      if (conv.type == 'group') {
        return await _enc.getOrFetchGroupKeyCandidates(convId, myId);
      }
      if (myId.isEmpty) return const [];
      final otherUserId = await _otherMemberId(convId, myId);
      if (otherUserId == null) return const [];
      final user = await _db.usersDao.getUserById(otherUserId);
      final pub = user?.publicKey;
      if (pub == null || pub.isEmpty) return const [];
      return [await _enc.getOrDeriveConversationKey(convId, pub)];
    } catch (_) {
      return const []; // MissingKeyException / offline / bad peer key
    }
  }

  Future<String?> _otherMemberId(String convId, String myId) async {
    final members = await _db.conversationsDao.getMembersForConversation(
      convId,
    );
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
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// One conversation's key + rows in a [runFor] batch.
class _KeyGroup {
  _KeyGroup({
    required this.keys,
    required this.fingerprints,
    required this.rows,
  });

  final List<List<int>> keys;
  final List<String> fingerprints;
  final List<MessagesTableData> rows;
}

/// Crypto worker — runs INLINE on main for ≤50-row batches and inside
/// `Isolate.run` for ≥51 (spec §8). Takes only plain sendable data,
/// returns the spec's `(messageId, plaintext, newState)` tuples as maps
/// (isolate messages are JSON-ish values, not Dart records).
Future<List<Map<String, Object?>>> _decryptBatch(
  List<Map<String, Object?>> items,
  List<List<int>> keys,
  List<String> fingerprints,
) async {
  final out = <Map<String, Object?>>[];
  final aes = AesGcm.with256bits();
  final secretKeys = <SecretKey?>[];
  for (final key in keys) {
    try {
      secretKeys.add(await aes.newSecretKeyFromBytes(key));
    } catch (_) {
      // Preserve per-candidate failure handling from the decrypt loop.
      secretKeys.add(null);
    }
  }
  for (final item in items) {
    final id = item['id'] as String;
    String? plain;
    var matchedFingerprint = fingerprints.first;
    for (var i = 0; i < keys.length && plain == null; i++) {
      final secretKey = secretKeys[i];
      if (secretKey == null) continue;
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
        matchedFingerprint = fingerprints[i];
      } catch (_) {
        // Try the next retained historical key.
      }
    }
    final prevKeyId = item['keyId'] as String?;
    final String state;
    if (plain != null) {
      state = 'ready';
    } else if (keys.length > 1 ||
        (prevKeyId != null && prevKeyId != matchedFingerprint)) {
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
      'fingerprint': matchedFingerprint,
    });
  }
  return out;
}
