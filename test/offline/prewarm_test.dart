/// #71 Prewarm (2026-10-14): the home list's VISIBLE previews decrypt
/// FIRST — newest conversations first — before backfill and background key
/// refreshes. Pins:
/// 1. the newest non-deleted TEXT row per conversation lands in bodyCache
///    (the exact row conversationLastMessageProvider renders);
/// 2. older text rows are NOT touched — only the preview row;
/// 3. a newest row that is media/system is skipped (constant label at the
///    widget layer, never decrypted — spec §3/P7);
/// 4. limit + recency order: only the newest conversation's preview is
///    decrypted when limit=1;
/// 5. newest row deleted-for-me is invisible — the older live text row is
///    the preview;
/// 6. concurrent calls are single-flight — one decryptPass.runFor;
/// 7. light path: warm cache keeps prewarm skipped, purged cache runs it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/services/encryption_service.dart';

import 'char_harness.dart';

Future<void> _seedMsg(
  AppDatabase db, {
  required String localId,
  required EncryptResult cipher,
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
      'prewarm: newest text row of a conversation lands in bodyCache; '
      'older rows untouched', () async {
    final pre = charHarness(); // throwaway: encrypt with the fixture key
    addTearDown(pre.close);
    final cipherOld = await pre.encryption
        .encryptMessage('older text', fixtureGroupKey);
    final cipherNew = await pre.encryption
        .encryptMessage('newest preview', fixtureGroupKey);

    final h = _offlineHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h); // g1 + group_key_g1 (disk)
    final at = DateTime.utc(2026, 1, 1);
    await _seedMsg(h.db,
        localId: 'm_old', cipher: cipherOld, createdAt: at);
    await _seedMsg(h.db,
        localId: 'm_new',
        cipher: cipherNew,
        createdAt: at.add(const Duration(minutes: 5)));

    await buildRepo(h).prewarmHomePreviews();

    expect(bodyCache.get('m_new'), 'newest preview',
        reason: 'the preview row is decrypted ahead of any UI read');
    expect(bodyCache.get('m_old'), isNull,
        reason: 'only the newest row per conversation — older rows stay '
            'lazy');
    final row = (await h.db.messagesDao.getMessageByLocalId('m_new'))!;
    expect(row.decryptState, 'ready');
  });

  test(
      'prewarm: media/system newest row is skipped — nothing decrypted, '
      'older text stays lazy (widget layer shows a constant label)', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final cipherText = await pre.encryption
        .encryptMessage('older text', fixtureGroupKey);

    final h = _offlineHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final at = DateTime.utc(2026, 1, 1);
    await _seedMsg(h.db,
        localId: 'm_text', cipher: cipherText, createdAt: at);
    // Newest row is a media bubble: its preview is a type label, never a
    // decrypted body.
    await _seedMsg(h.db,
        localId: 'm_media',
        cipher: cipherText,
        createdAt: at.add(const Duration(minutes: 5)),
        type: 'image');

    await buildRepo(h).prewarmHomePreviews();

    expect(bodyCache.length, 0,
        reason: 'media/system previews never decrypt (spec §3/P7)');
    final textRow = (await h.db.messagesDao.getMessageByLocalId('m_text'))!;
    expect(textRow.decryptState, 'key_missing',
        reason: 'the older text row is NOT the preview — stays lazy');
  });

  test(
      'prewarm: recency order + limit — only the newest conversation is '
      'decrypted when limit=1', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final cipherA = await pre.encryption
        .encryptMessage('g1 preview', fixtureGroupKey);
    final cipherB = await pre.encryption
        .encryptMessage('g2 preview', fixtureGroupKey);

    final h = _offlineHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h); // g1
    h.storage.put('group_key_g2', base64.encode(fixtureGroupKey));
    final at = DateTime.utc(2026, 1, 1);
    await h.db.conversationsDao.upsertConversation(
      ConversationsTableCompanion.insert(
        id: 'g2',
        type: 'group',
        createdById: 'u_test',
        createdAt: at,
        updatedAt: at,
        lastMessageAt: Value(at.add(const Duration(hours: 1))),
      ),
    );
    await h.db.conversationsDao.upsertMember(
      ConversationMembersTableCompanion.insert(
        id: 'm2',
        conversationId: 'g2',
        userId: 'u_test',
        joinedAt: at,
      ),
    );
    await _seedMsg(h.db,
        localId: 'p_g1', cipher: cipherA, createdAt: at);
    await _seedMsg(h.db,
        localId: 'p_g2',
        cipher: cipherB,
        createdAt: at.add(const Duration(hours: 1)),
        conv: 'g2');

    await buildRepo(h).prewarmHomePreviews(limit: 1);

    expect(bodyCache.get('p_g2'), 'g2 preview',
        reason: 'g2 is the newest conversation — its preview wins the slot');
    expect(bodyCache.get('p_g1'), isNull,
        reason: 'limit=1 — the older conversation stays lazy');
  });

  test(
      'prewarm: newest row deleted-for-me → the older live text row is '
      'the preview', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final cipherOld = await pre.encryption
        .encryptMessage('live preview', fixtureGroupKey);
    final cipherNew = await pre.encryption
        .encryptMessage('deleted preview', fixtureGroupKey);

    final h = _offlineHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final at = DateTime.utc(2026, 1, 1);
    await _seedMsg(h.db,
        localId: 'm_live', cipher: cipherOld, createdAt: at);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm_gone',
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: cipherNew.ciphertext,
      iv: cipherNew.iv,
      serverId: Value('srv_m_gone'),
      decryptState: Value('key_missing'),
      createdAt: at.add(const Duration(minutes: 5)),
      updatedAt: at.add(const Duration(minutes: 5)),
      isDeletedForMe: Value(true),
    ));

    await buildRepo(h).prewarmHomePreviews();

    expect(bodyCache.get('m_live'), 'live preview',
        reason: 'the deleted-for-me row is invisible — live row is preview');
    expect(bodyCache.get('m_gone'), isNull,
        reason: 'deleted rows are never previews');
  });

  test('prewarm: overlapping calls are single-flight — one runFor',
      () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final cipher =
        await pre.encryption.encryptMessage('flight', fixtureGroupKey);

    final h = _offlineHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final at = DateTime.utc(2026, 1, 1);
    await _seedMsg(h.db,
        localId: 'm_f', cipher: cipher, createdAt: at);
    final repo = buildRepo(h);

    // Hold the first prewarm inside its apply step; the second call must
    // coalesce instead of starting a second decrypt batch.
    final gate = Completer<void>();
    final reached = Completer<void>();
    repo.decryptPass.beforeApply = () {
      if (!reached.isCompleted) reached.complete();
      return gate.future;
    };
    final first = repo.prewarmHomePreviews();
    await reached.future;
    await repo.prewarmHomePreviews(); // must return while first is held
    int laneCalls() =>
        repo.decryptPass.inlineCalls + repo.decryptPass.isolateCalls;
    expect(laneCalls(), 1,
        reason: 'second call coalesces — no second batch starts');
    expect(bodyCache.get('m_f'), isNull,
        reason: 'first apply still held at the gate');

    gate.complete();
    await first;
    repo.decryptPass.beforeApply = null;
    expect(laneCalls(), 1, reason: 'exactly one batch ran total');
    expect(bodyCache.get('m_f'), 'flight');
  });

  test(
      'prewarm: inline lane serves small preview batches (≤50 → '
      'inlineCalls=1, isolateCalls=0)', () async {
    final pre = charHarness();
    addTearDown(pre.close);
    final cipher =
        await pre.encryption.encryptMessage('lane', fixtureGroupKey);

    final h = _offlineHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final at = DateTime.utc(2026, 1, 1);
    await _seedMsg(h.db,
        localId: 'm_lane', cipher: cipher, createdAt: at);
    final repo = buildRepo(h);

    await repo.prewarmHomePreviews();

    // ≤50 rows take the inline lane (decrypt_pass_test pins the ≥51
    // isolate lane); the repo's live pass exposes both counters.
    expect(repo.decryptPass.inlineCalls, 1,
        reason: 'small prewarm batch decrypts inline, no isolate hop');
    expect(repo.decryptPass.isolateCalls, 0,
        reason: 'a ≤50-row prewarm never takes the isolate lane');
  });

  test(
      'prewarm call-site: light path skips when cache warm, fires when '
      'purged (paused → quick return)', () async {
    // The call-site predicate (`bodyCache.length == 0`) lives inline in
    // _resyncRun; this test pins the observable contract both branches
    // key off.
    final pre = charHarness();
    addTearDown(pre.close);
    final cipher =
        await pre.encryption.encryptMessage('warm', fixtureGroupKey);

    final h = _offlineHarness();
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final at = DateTime.utc(2026, 1, 1);
    await _seedMsg(h.db,
        localId: 'm_w', cipher: cipher, createdAt: at);
    final repo = buildRepo(h);

    // Light + warm cache → prewarm must be a no-op (row untouched).
    bodyCache.put('m_w', 'sentinel');
    final before =
        repo.decryptPass.inlineCalls + repo.decryptPass.isolateCalls;
    final rowBefore =
        (await h.db.messagesDao.getMessageByLocalId('m_w'))!;
    expect(rowBefore.decryptState, 'key_missing',
        reason: 'sentinel is cache-only — DB still cold');
    expect(before, 0, reason: 'no decrypt ran yet');
    // Warm cache ⇒ the _resyncRun predicate skips prewarm entirely, so
    // the row stays cold until a real UI read coalesces it.
    expect(bodyCache.get('m_w'), 'sentinel',
        reason: 'shade pull keeps B cache — no prewarm rerun needed');

    // Light + purged cache (paused → quick return) → prewarm runs.
    bodyCache.clear();
    await repo.prewarmHomePreviews();
    expect(bodyCache.get('m_w'), 'warm',
        reason: 'post-pause light resume rewarms the visible preview');
    final after = repo.decryptPass.inlineCalls + repo.decryptPass.isolateCalls;
    expect(after, greaterThan(before),
        reason: 'purged cache ⇒ prewarm actually ran the pass');
  });
}
