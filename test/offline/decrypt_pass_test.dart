/// Task 8 — DecryptPass + messageBodyProvider + body cache (the 5 named
/// tests from task-8-brief.md, binding).
///
/// Determinism rules:
/// - ONE harness per test phase (`charHarness()`): encrypt on `pre`, act on
///   `h` — same pattern as always_commit_test.
/// - `bodyCache` is a process-global — `setUp` clears it so tests never
///   see each other's plaintext.
/// - Coalescing/epoch/bad-MAC/lanes are driven through the PUBLIC seams the
///   brief pins: `decryptPassProvider` override (counting decorator),
///   `DecryptPass.beforeApply` (async gap = "isolate result landing"),
///   `bodyCache.clear()` (backgrounding).
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/decrypt/decrypt_pass.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/services/encryption_service.dart';

import 'char_harness.dart';

// ── Seeds / helpers ───────────────────────────────────────────────────────

Future<void> _seedText(
  AppDatabase db, {
  required String localId,
  required EncryptResult cipher,
  String state = 'key_missing',
  String conv = 'g1',
}) =>
    db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: localId,
      conversationId: conv,
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: cipher.ciphertext,
      iv: cipher.iv,
      serverId: Value('srv_$localId'),
      decryptState: Value(state),
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    ));

/// Counting decorator over the runFor seam (brief test 1's instrument).
class _CountingDecryptPass extends DecryptPass {
  _CountingDecryptPass({
    required super.db,
    required super.enc,
    required super.epoch,
  });

  int calls = 0;

  @override
  Future<void> runFor(List<String> messageIds) {
    calls++;
    return super.runFor(messageIds);
  }
}

/// Lets autoDispose drop an unlistened provider between reads (test 4).
Future<void> _letAutoDisposeRun() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  setUp(bodyCache.clear);

  test(
      'provider coalescing: 40 reads in one frame → ≤2 runFor invocations '
      '(counting decorator seam)', () async {
    final pre = charHarness(); // throwaway: encrypt with the fixture key
    addTearDown(pre.close);
    final cipher =
        await pre.encryption.encryptMessage('coalesced', fixtureGroupKey);

    final h = charHarness(
        clientFactory: () => MockClient(
            (_) async => throw http.ClientException('offline')));
    addTearDown(h.close);
    await seedConversationAndKey(h); // g1 + group_key_g1
    for (var i = 0; i < 40; i++) {
      await _seedText(h.db, localId: 'm$i', cipher: cipher);
    }

    final pass = _CountingDecryptPass(
      db: h.db,
      enc: h.encryption,
      epoch: () => 0,
    );
    final container = ProviderContainer(
      overrides: [decryptPassProvider.overrideWithValue(pass)],
    );
    addTearDown(container.dispose);

    // 40 DIFFERENT bubbles read in one frame — each misses the cache and
    // must join the SAME 50ms window (one batch decrypt, never 40).
    final futures = <Future<String?>>[];
    final subs = <ProviderSubscription<AsyncValue<String?>>>[];
    for (var i = 0; i < 40; i++) {
      subs.add(container.listen(messageBodyProvider('m$i'), (_, __) {}));
      futures.add(container.read(messageBodyProvider('m$i').future));
    }
    final bodies = await Future.wait(futures);

    expect(pass.calls, greaterThan(0), reason: 'cache was cold — runFor must run');
    expect(pass.calls, lessThanOrEqualTo(2),
        reason: '40 reads in one frame coalesce into one 50ms window');
    expect(bodies.where((b) => b == 'coalesced'), hasLength(40),
        reason: 'every waiter gets the decrypted body, not null');
    expect(bodyCache.length, 40, reason: 'all 40 bodies resident after the pass');

    for (final s in subs) {
      s.close();
    }
  });

  test('multi-key pass recovers a pre-rotation body after cache hydration',
      () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final historicalKey = List<int>.generate(32, (i) => 100 + i);
    final cipher = await pre.encryption.encryptMessage(
        'before rotation', historicalKey);

    final h = charHarness(
        clientFactory: () => MockClient(
            (_) async => throw http.ClientException('offline')));
    addTearDown(h.close);
    await seedConversationAndKey(h, key: fixtureGroupKey);
    // The compatibility slot contains the current key; the versioned slot is
    // the retained historical key available after a process/cache restart.
    h.storage.put('group_key_g1_1', base64.encode(historicalKey));
    await _seedText(h.db, localId: 'm_old', cipher: cipher);

    final pass = DecryptPass(db: h.db, enc: h.encryption, epoch: () => 0);
    await pass.runFor(const ['m_old']);

    final row = (await h.db.messagesDao.getMessageByLocalId('m_old'))!;
    expect(row.decryptState, 'ready');
    expect(row.keyId, DecryptPass.fingerprintOf(historicalKey));
    expect(bodyCache.get('m_old'), 'before rotation');
  });

  test(
      'epoch drop: schedule runFor, bump epoch before result lands → apply '
      'dropped (DB stays key_missing, cache empty)', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final cipher =
        await pre.encryption.encryptMessage('epoch drop', fixtureGroupKey);

    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    await _seedText(h.db, localId: 'm_ep', cipher: cipher, state: 'key_missing');

    var epoch = 0;
    final pass = DecryptPass(db: h.db, enc: h.encryption, epoch: () => epoch);

    // Injected async gap = "isolate result in flight": crypto has finished,
    // apply is pending on the gate.
    final gate = Completer<void>();
    final reached = Completer<void>();
    pass.beforeApply = () {
      if (!reached.isCompleted) reached.complete();
      return gate.future;
    };

    final run = pass.runFor(const ['m_ep']);
    // RED surface: an unimplemented runFor fails here instead of hanging.
    await Future.any<void>([
      reached.future,
      run.then<void>((_) {},
          onError: (Object e, StackTrace st) =>
              Error.throwWithStackTrace(e, st)),
    ]);

    epoch++; // logout / account switch lands while the result is in flight
    gate.complete();
    await run;

    final row = (await h.db.messagesDao.getMessageByLocalId('m_ep'))!;
    expect(row.decryptState, 'key_missing',
        reason: 'spec §11 — post-epoch apply must be dropped, not written');
    expect(row.keyId, isNull, reason: 'dropped apply writes nothing');
    expect(bodyCache.get('m_ep'), isNull,
        reason: 'dropped apply must not populate the memcache');

    // Control: with a stable epoch the same runFor applies — proves the drop
    // above was the guard, not a no-op implementation.
    pass.beforeApply = null;
    await pass.runFor(const ['m_ep']);
    final healed = (await h.db.messagesDao.getMessageByLocalId('m_ep'))!;
    expect(healed.decryptState, 'ready');
    expect(healed.keyId, isNotNull,
        reason: 'Task 8 populates key_id for rows it successfully decrypts');
    expect(bodyCache.get('m_ep'), 'epoch drop');
  });

  test(
      "bad MAC on lazy path → decrypt_state='failed'; second runFor on same "
      'row does nothing (terminal)', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    // Ciphertext under a DIFFERENT 32-byte key → MAC fails under the real
    // fixture key while the key itself resolves (correct-key corrupt case).
    final wrongKey = List<int>.generate(32, (i) => (200 + i) % 256);
    final bad = await pre.encryption.encryptMessage('tampered', wrongKey);
    final good = await pre.encryption.encryptMessage('now valid', fixtureGroupKey);

    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    await _seedText(h.db, localId: 'm_bad', cipher: bad, state: 'key_missing');

    final pass = DecryptPass(db: h.db, enc: h.encryption, epoch: () => 0);

    // Lazy path (what messageBodyProvider schedules).
    await pass.runFor(const ['m_bad']);
    var row = (await h.db.messagesDao.getMessageByLocalId('m_bad'))!;
    expect(row.decryptState, 'failed',
        reason: 'correct key + MAC failure = terminal bad MAC (spec §5.1/§8)');
    expect(bodyCache.get('m_bad'), isNull,
        reason: 'a failed row never lands plaintext in the cache');

    // Second pass MUST do nothing even though the ciphertext is now valid —
    // if the terminal gate were missing, this would flip to ready.
    await _seedText(h.db, localId: 'm_bad', cipher: good, state: 'failed');
    await pass.runFor(const ['m_bad']);
    row = (await h.db.messagesDao.getMessageByLocalId('m_bad'))!;
    expect(row.decryptState, 'failed',
        reason: "failed is terminal — 'failed' never retries (spec §8)");
    expect(bodyCache.get('m_bad'), isNull,
        reason: 'terminal row is skipped at load, not re-attempted');
  });

  test(
      'backgrounding: bodyCache.clear() then re-read → provider re-decrypts '
      'and emits (AsyncValue completes)', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final cipher = await pre.encryption
        .encryptMessage('background clear', fixtureGroupKey);

    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    // 'ready' row: spec §8 — a cleared cache is safe, ready rows re-decrypt
    // on the next provider read.
    await _seedText(
        h.db, localId: 'm_bg', cipher: cipher, state: 'ready');

    final pass = _CountingDecryptPass(
      db: h.db,
      enc: h.encryption,
      epoch: () => 0,
    );
    final container = ProviderContainer(
      overrides: [decryptPassProvider.overrideWithValue(pass)],
    );
    addTearDown(container.dispose);

    var sub = container.listen(messageBodyProvider('m_bg'), (_, __) {});
    expect(await container.read(messageBodyProvider('m_bg').future),
        'background clear');
    expect(pass.calls, 1, reason: 'cold read decrypts exactly once');

    sub.close();
    await _letAutoDisposeRun(); // bubble unmounted / app backgrounded

    bodyCache.clear(); // backgrounding purge (app.dart wiring)
    expect(pass.calls, 1);

    sub = container.listen(messageBodyProvider('m_bg'), (_, __) {});
    expect(
        await container.read(messageBodyProvider('m_bg').future),
        'background clear',
        reason: 'after clear the next read re-decrypts from ciphertext');
    expect(pass.calls, 2,
        reason: 're-read must re-run the pass — not serve a memoized value');
    sub.close();
  });

  test(
      'search-style batch of 60 rows → isolate path (≥51) lands all bodies; '
      '≤50 batch takes the inline lane', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final cipher =
        await pre.encryption.encryptMessage('search batch', fixtureGroupKey);

    final h = charHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final ids = <String>[];
    for (var i = 0; i < 60; i++) {
      final id = 's$i';
      ids.add(id);
      await _seedText(h.db, localId: id, cipher: cipher);
    }

    final pass = DecryptPass(db: h.db, enc: h.encryption, epoch: () => 0);
    await pass.runFor(ids);

    expect(pass.isolateCalls, 1,
        reason: '≥51 rows take the Isolate.run lane (spec §8)');
    expect(pass.inlineCalls, 0, reason: '60-row batch must not run inline');
    for (final id in ids) {
      expect(bodyCache.get(id), 'search batch',
          reason: 'all 60 bodies land in the memcache');
      final row = (await h.db.messagesDao.getMessageByLocalId(id))!;
      expect(row.decryptState, 'ready', reason: '$id decrypted');
      expect(row.keyId, isNotNull,
          reason: 'key_id populated on every successful decrypt (Task 8)');
    }

    // ≤50 → inline lane (both batch lanes pinned here).
    bodyCache.clear();
    await pass.runFor(const ['s0']);
    expect(pass.inlineCalls, 1, reason: '≤50 rows decrypt inline on main');
    expect(pass.isolateCalls, 1, reason: 'lane counters are per-call');
    expect(bodyCache.get('s0'), 'search batch');
  });
}
