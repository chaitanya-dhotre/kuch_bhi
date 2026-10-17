import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:kuch_bhi/services/encryption_service.dart';

import 'char_harness.dart'; // buildRepo + seedConversationAndKey live here

/// Task 7 — cache-policy flip (the :2484 fix, spec §7).
///
/// Fetch with a MISSING key must still commit: rows land with
/// `decrypt_state='key_missing'` and the sync cursor advances WITH the
/// batch. A later re-fetch (key now present) upserts the same server-id
/// row again — no duplicates, state flips to `ready` with the plaintext.
///
/// Canned client: one `messages` list record for `g1` (same envelope the
/// char harness uses), answered on every `messages/records` request so the
/// warm re-fetch sees the same record regardless of its cursor filter.
MockClient alwaysCommitClient({
  EncryptResult? enc,
  required String conversationId,
  // Fix R1 mutation hook: when it returns true, `messages/records` answers
  // a valid EMPTY PocketBase list envelope (200) instead of the record —
  // used to prove the phase-2 predicate is load-bearing on the re-fetch
  // path (the parallel repair pass alone must NOT satisfy it: repair
  // writes body+state but never bumps `updatedAt`).
  bool Function()? refuseRecords,
}) =>
    MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future; // SSE hangs, never 404s
      }
      if (!req.url.path.contains('/collections/messages/records')) {
        return http.Response('{"message":"unhandled"}', 404);
      }
      if (refuseRecords?.call() ?? false) {
        return http.Response(
          jsonEncode({
            'page': 1, 'perPage': 40, 'totalItems': 0, 'totalPages': 1,
            'items': <dynamic>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'page': 1, 'perPage': 40, 'totalItems': 1, 'totalPages': 1,
          'items': [{
            'id': 'srv1',
            'collectionId': 'messages', 'collectionName': 'messages',
            'created': '2026-10-07T10:00:00.000Z',
            'updated': '2026-10-07T10:00:00.000Z',
            'fields': {},
            'conversation_id': conversationId, 'sender_id': 'u_peer',
            'type': 'text', 'encrypted_body': enc?.ciphertext ?? '',
            'iv': enc?.iv ?? '',
            'reply_to_id': '', 'reply_preview': '',
            'is_deleted_for_everyone': false, 'is_deleted_for_me': false,
            'is_pinned': false, 'is_starred': false,
            'status': 'sent', 'media_id': '',
          }],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

void main() {
  test(
      'always-commit: fetch with NO key lands rows (key_missing) + cursor; '
      're-fetch after key arrival upserts without duplicates', () async {
    final pre = charHarness(); // throwaway: encrypt with the fixture key
    addTearDown(pre.close);
    final enc =
        await pre.encryption.encryptMessage('always commit', fixtureGroupKey);

    // Fix-R1 mutation (`refuseRecords`): armed true only for the RED run,
    // after the phase-1 asserts — see task-7-report fix R1. GREEN keeps it
    // false (client always returns the record).
    final neuterReFetch = false;
    final h = charHarness(
        clientFactory: () => alwaysCommitClient(
            enc: enc,
            conversationId: 'g1',
            refuseRecords: () => neuterReFetch));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: false); // group_key_g1 absent
    final repo = buildRepo(h);

    // ── Phase 1 — key MISSING: rows MUST land anyway (was: skip cache).
    // The repo stream is the production cold-fetch trigger; its output
    // stays empty for now — isGroupRowVisible still hides undecryptable
    // group rows (read path = Task 9's domain). The CACHE is the contract.
    final repoRows = await repo.watchMessages('g1').first; // cold path awaits fetch
    expect(repoRows, isEmpty,
        reason: 'read path unchanged at Task 7 — Task 9 flips this surface');

    final cached = await h.db.messagesDao.watchMessages('g1').first;
    expect(cached, hasLength(1),
        reason: 'always-commit: ciphertext lands without the key (:2484 fix)');
    expect(cached.first.decryptState, 'key_missing',
        reason: 'spec §5.1/§7 — attempted, key unavailable');
    expect(bodyCache.get(cached.first.localId), isNull,
        reason: 'no key → no plaintext; ciphertext preserved verbatim');
    expect(cached.first.encryptedBody, enc.ciphertext);

    final cursor = await h.db.settingsDao.getSetting('sync_cursor_g1');
    expect(cursor, isNotNull,
        reason: 'cursor advances WITH the batch when the key is missing');
    expect(DateTime.parse(cursor!), DateTime.utc(2026, 10, 7, 10),
        reason: 'cursor = newest server stamp in the committed batch');

    // Fix R1: baseline for the phase-2 predicate. Only the fetch companion
    // bumps `updatedAt` (`DateTime.now()` in message_repository_impl.dart
    // `_companionFromRecord`); the parallel `_repairUndecrypted` pass
    // writes body+state only (cacheDecryptedBody) — never updatedAt.
    final phase1Done = DateTime.now();
    // Fix R1 caveat: drift persists DateTime as unix SECONDS (drift-2.28.2
    // mapping.dart — `millisecondsSinceEpoch ~/ 1000`), so a fetch bump in
    // the SAME wall-clock second as phase1Done compares equal under `>`.
    // Cross the second boundary before the warm kick so the GREEN re-fetch
    // writes a strictly-greater updatedAt; RED (no re-fetch write — repair
    // never touches updatedAt) stays <= baseline either way.
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // ── Phase 2 — key arrives: the next fetch re-upserts the SAME row.
    // C: key arrives AFTER the cold fetch already loaded the key memory —
    // raw storage.put would be invisible to reads; saveGroupKey is the
    // write-through API (disk + memory).
    await h.encryption.saveGroupKey('g1', fixtureGroupKey);
    unawaited(repo.watchMessages('g1').first); // warm kick → background re-fetch
    // Phase-2 proof must ride the re-fetch (updatedAt bump), never repair.
    final healed = await h.db.messagesDao
        .watchMessages('g1')
        .firstWhere((rows) =>
            rows.isNotEmpty &&
            rows.every((r) =>
                r.decryptState == 'ready' &&
                bodyCache.get(r.localId) != null &&
                r.updatedAt.millisecondsSinceEpoch >
                    phase1Done.millisecondsSinceEpoch));
    expect(healed, hasLength(1),
        reason: 'id-based upsert — same server id, no duplicate row');
    expect(bodyCache.get(healed.first.localId), 'always commit');
    expect(healed.first.serverId, 'srv1');
  });
}
