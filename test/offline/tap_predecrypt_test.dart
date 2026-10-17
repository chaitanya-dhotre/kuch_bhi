/// #74 tap-down predecrypt (Astra recs §Loading UX): pressing a
/// conversation row kicks [MessageRepository.predecryptConversation] —
/// the last ~30 BODY-RENDERING rows decrypt locally while the ~250ms
/// open transition runs, so bubbles resolve from `bodyCache` on first
/// build (tap→text ≤100ms p95 target).
///
/// Contract pinned here:
/// A. text/voice/system rows within the newest-[limit] window land in
///    `bodyCache` (voice duration + system line included — both render
///    through MessageBodyText);
/// B. rows OUTSIDE the window stay lazy (decrypt-on-appear still owns
///    the tail — predecrypt never becomes a full-history pass);
/// C. media rows (image/video/document/poll) are never prefetched —
///    their widgets do not render a body;
/// D. offline is fine: the pass is local-only (key memory, spec C).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:drift/drift.dart' show Value;
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';

import 'char_harness.dart';

Future<void> _seedMsg(
  AppDatabase db, {
  required String localId,
  required dynamic cipher,
  required DateTime createdAt,
  String conv = 'g1',
  String type = 'text',
  String state = 'key_missing',
}) =>
    db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: localId,
      conversationId: conv,
      senderId: 'u_peer',
      type: type,
      encryptedBody: cipher.ciphertext,
      iv: cipher.iv,
      serverId: Value('srv_$localId'),
      decryptState: Value(state),
      createdAt: createdAt,
      updatedAt: createdAt,
    ));

CharHarness _offlineHarness() => charHarness(
    clientFactory: () =>
        MockClient((_) async => throw http.ClientException('offline')));

void main() {
  setUp(bodyCache.clear);

  test(
      'tap-predecrypt: newest `limit` body rows (text/voice/system) warm '
      'bodyCache; older rows stay lazy; media never fetched', () async {
    final pre = charHarness(); // throwaway: encrypt with the fixture key
    addTearDown(pre.close);
    final cipherText = await pre.encryption
        .encryptMessage('tap text', fixtureGroupKey);
    final cipherVoice =
        await pre.encryption.encryptMessage('0:12', fixtureGroupKey);
    final cipherSys = await pre.encryption
        .encryptMessage('Alice joined', fixtureGroupKey);
    final cipherImg = await pre.encryption
        .encryptMessage('img-iv-and-cipher', fixtureGroupKey);

    final h = _offlineHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h); // g1 + group_key_g1 (disk)
    final at = DateTime.utc(2026, 1, 1);

    // 32 text rows — only the newest 30 of ALL body-types may warm.
    for (var i = 0; i < 32; i++) {
      await _seedMsg(h.db,
        localId: 't${i.toString().padLeft(3, '0')}',
        cipher: cipherText,
        createdAt: at.add(Duration(minutes: i)));
    }
    await _seedMsg(h.db,
        localId: 'm_voice',
        cipher: cipherVoice,
        createdAt: at.add(const Duration(minutes: 40)),
        type: 'voice');
    await _seedMsg(h.db,
        localId: 'm_sys',
        cipher: cipherSys,
        createdAt: at.add(const Duration(minutes: 41)),
        type: 'system');
    // Newest row overall, but a MEDIA type — must never be prefetched.
    await _seedMsg(h.db,
        localId: 'm_img',
        cipher: cipherImg,
        createdAt: at.add(const Duration(minutes: 42)),
        type: 'image');

    await buildRepo(h).predecryptConversation('g1');

    // A: in-window body rows warmed.
    expect(bodyCache.get('m_sys'), 'Alice joined',
        reason: 'system lines render through MessageBodyText');
    expect(bodyCache.get('m_voice'), '0:12',
        reason: 'voice duration text renders through MessageBodyText');
    expect(bodyCache.get('t031'), 'tap text');
    expect(bodyCache.get('t004'), 'tap text',
        reason: 'the window is the newest 30 body rows '
            '(t004..t031 + voice + system = 30)');

    // B: outside the window stays lazy (decrypt-on-appear owns the tail).
    expect(bodyCache.get('t003'), isNull,
        reason: 'B: predecrypt is bounded by `limit` — never history');
    expect(bodyCache.get('t000'), isNull, reason: 'B');

    // C: media rows are never fetched.
    expect(bodyCache.get('m_img'), isNull,
        reason: 'C: media widgets render no body — no wasted decrypt');

    // D: offline harness (client always throws) — reaching here proves
    // the pass never touched the network.
  });

  test(
      'tap-predecrypt: warm cache is a no-op (second call changes '
      'nothing, never throws)', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final cipher = await pre.encryption
        .encryptMessage('already warm', fixtureGroupKey);

    final h = _offlineHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final at = DateTime.utc(2026, 1, 1);
    await _seedMsg(h.db, localId: 'm_w', cipher: cipher, createdAt: at);

    final repo = buildRepo(h);
    await repo.predecryptConversation('g1');
    expect(bodyCache.get('m_w'), 'already warm');

    await repo.predecryptConversation('g1'); // cache hits → ids empty
    expect(bodyCache.get('m_w'), 'already warm');
    final row = (await h.db.messagesDao.getMessageByLocalId('m_w'))!;
    expect(row.decryptState, 'ready');
  });
}
