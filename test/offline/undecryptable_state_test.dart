import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kuch_bhi/services/encryption_service.dart';

import 'char_harness.dart';

/// BACKLOG §170 fix (b): a group whose history cannot be decrypted must not
/// render the brand-new-conversation empty state.
///
/// Today `_rowsToMessages` drops every `pending`/`key_missing` row (spec D1 —
/// ciphertext must never reach a bubble), so a conversation with 8 undecryptable
/// rows and 0 visible ones produces `[]` — indistinguishable, at the screen,
/// from a genuinely empty chat ("Say hello 👋").
///
/// The fix keeps the read path unchanged and adds a COUNT the screen can read:
/// "history exists but cannot be decrypted".
void main() {
  test(
      'the give-up budget stops the retries (backlog §170 c)', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final enc = await pre.encryption.encryptMessage('hello', fixtureGroupKey);

    final h = charHarness(clientFactory: () => _messagesClient(enc));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: false);
    final repo = buildRepo(h);

    // One open to settle the fetch, then count only what further OPENS cause.
    // The repo also runs the pass from its SSE-down poll fallback — a
    // different path the budget is not about.
    await repo.watchMessages('g1').first;
    await Future<void>.delayed(Duration.zero);
    repo.debugRepairRuns.clear();

    for (var open = 1; open <= 4; open++) {
      await repo.watchMessages('g1').first;
      await Future<void>.delayed(Duration.zero);
    }

    // 4 opens with a budget of 2 fruitless passes → at most 2 more runs.
    // Before the cap every open ran it, forever, on a row this device had
    // already proven it cannot heal.
    expect(repo.debugRepairRuns['g1'] ?? 0, lessThanOrEqualTo(2),
        reason: 'an unrecoverable row must stop being retried every open');

    // And the cap must never hide or reveal anything to get that saving.
    expect(await repo.watchMessages('g1').first, isEmpty,
        reason: 'spec D1 — ciphertext never reaches a bubble');
    expect(await repo.countUndecryptable('g1'), 1,
        reason: 'the count survives — it drives the empty-state copy');
  });

  test(
      'a group whose rows are all key_missing reports the hidden count, not an '
      'indistinguishable empty list', () async {
    final pre = charHarness(); // throwaway: encrypt with the fixture key
    addTearDown(pre.close);
    final enc =
        await pre.encryption.encryptMessage('hello', fixtureGroupKey);

    final h = charHarness(clientFactory: () => _messagesClient(enc));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: false); // group_key_g1 absent
    final repo = buildRepo(h);

    // The read path is UNCHANGED — ciphertext never reaches a bubble.
    final repoRows = await repo.watchMessages('g1').first;
    expect(repoRows, isEmpty,
        reason: 'spec D1 — undecryptable rows stay hidden from the chat');

    // The ciphertext DID land in the cache (always-commit, :2484).
    final cached = await h.db.messagesDao.watchMessages('g1').first;
    expect(cached, hasLength(1));
    expect(cached.first.decryptState, 'key_missing');

    // And the screen can now tell "nothing pending" from "history exists but
    // cannot be decrypted".
    final hidden = await repo.countUndecryptable('g1');
    expect(hidden, greaterThan(0),
        reason: 'fix (b): the hidden count is what the empty state branches on');
  });
}

/// A PocketBase that answers the group-messages fetch with one row encrypted
/// under the fixture key — which this test deliberately does NOT install, so
/// the row lands as `key_missing`.
MockClient _messagesClient(EncryptResult enc) => MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future; // SSE hangs, never 404s
      }
      if (!req.url.path.contains('/collections/messages/records')) {
        return http.Response('{"message":"unhandled"}', 404);
      }
      return http.Response(
        jsonEncode({
          'page': 1,
          'perPage': 200,
          'totalItems': 1,
          'totalPages': 1,
          'items': [
            {
              'id': 'r1',
              'collectionId': 'messages',
              'collectionName': 'messages',
              'created': '2026-10-07T10:00:00.000Z',
              'updated': '2026-10-07T10:00:00.000Z',
              'fields': {},
              'conversation_id': 'g1',
              'sender_id': 'u_peer',
              'type': 'text',
              'encrypted_body': enc.ciphertext,
              'iv': enc.iv,
              'reply_to_id': '',
              'reply_preview': '',
              'is_deleted_for_everyone': false,
              'is_deleted_for_me': false,
              'is_pinned': false,
              'is_starred': false,
              'status': 'sent',
              'media_id': '',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
