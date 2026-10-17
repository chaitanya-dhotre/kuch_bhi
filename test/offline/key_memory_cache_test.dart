import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'char_harness.dart';

/// C (2026-10-14, biggest lever for R1/R2/R3): group-key candidates are
/// read from FlutterSecureStorage PER conversation PER decrypt resolve —
/// on Samsung M52 a warm 18-conv prefetch measured ~30s and every focus
/// return paid the platform channel again. Spec §3 governs AT REST; the
/// decrypted body cache already keeps strictly more sensitive plaintext in
/// memory, so a process-lifetime key memory is inside the threat model.
///
/// Contract pinned here:
/// C1. the FIRST group-key read performs exactly ONE secure-storage scan;
///     every later read (any conversation) is served from memory — zero
///     additional scans;
/// C2. `saveGroupKey` is write-through: a saved key is visible to reads
///     without another storage scan (external writers — create-group,
///     rotation — must go through it);
/// C3. `clearAllGroupKeyCache` evicts the memory map: the next read
///     rescans storage (session epoch bump / logout must call it, or the
///     next account reads the previous account's keys from RAM);
/// C4. versioned rotation slots saved via saveGroupKey join the candidate
///     set from memory (multi-key decrypt keeps working).

MockClient _hangClient() => MockClient((_) => Completer<http.Response>().future);

void main() {
  test('C1: one storage scan per process — later reads serve from memory',
      () async {
    final h = charHarness(clientFactory: _hangClient);
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);

    expect(await h.encryption.hasLocalGroupKey('g1'), isTrue);
    expect(h.storage.readAllCalls, 1,
        reason: 'first read loads the memory map with ONE scan');

    await h.encryption.hasLocalGroupKey('g1');
    await h.encryption.getOrFetchGroupKeyCandidates('g1', 'u_test')
        .timeout(const Duration(seconds: 1));
    await h.encryption.getOrFetchGroupKeyCandidates('g1', 'u_test')
        .timeout(const Duration(seconds: 1));

    expect(h.storage.readAllCalls, 1,
        reason: 'every subsequent group-key read must be memory-only — '
            'the per-conv platform-channel cost is the whole point of C');
  });

  test('C2: saveGroupKey is write-through — visible without a rescan',
      () async {
    final h = charHarness(clientFactory: _hangClient);
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: false);

    expect(await h.encryption.hasLocalGroupKey('g1'), isFalse);
    expect(h.storage.readAllCalls, 1, reason: 'load happened on the miss');

    await h.encryption.saveGroupKey('g1', fixtureGroupKey);

    expect(await h.encryption.hasLocalGroupKey('g1'), isTrue,
        reason: 'write-through: disk AND memory updated together');
    expect(h.storage.readAllCalls, 1,
        reason: 'the write must not force a reload');
  });

  test('C3: clearAllGroupKeyCache evicts — next read rescans storage',
      () async {
    final h = charHarness(clientFactory: _hangClient);
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);

    expect(await h.encryption.hasLocalGroupKey('g1'), isTrue);
    expect(h.storage.readAllCalls, 1);

    h.encryption.clearAllGroupKeyCache();

    expect(await h.encryption.hasLocalGroupKey('g1'), isTrue,
        reason: 'disk still holds the key — it must come back');
    expect(h.storage.readAllCalls, 2,
        reason: 'eviction proven only by a fresh storage scan');
  });

  test('C4: versioned slots saved via saveGroupKey join candidates from '
      'memory (multi-key decrypt intact)', () async {
    final h = charHarness(clientFactory: _hangClient);
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    final historical = List<int>.generate(32, (i) => 200 + i);

    // Memory already loaded by the seed touch below (hasLocalGroupKey).
    await h.encryption.hasLocalGroupKey('g1');
    await h.encryption.saveGroupKey('g1', historical, version: 1);

    final cands = await h.encryption
        .getOrFetchGroupKeyCandidates('g1', 'u_test')
        .timeout(const Duration(seconds: 1));

    expect(cands, hasLength(2),
        reason: 'base + v1 both served from the memory map');
    expect(cands.map((k) => base64.encode(k)),
        containsAll([base64.encode(fixtureGroupKey), base64.encode(historical)]));
    expect(h.storage.readAllCalls, 1, reason: 'no rescan to see the new slot');
  });
}
