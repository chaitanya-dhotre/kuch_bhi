// P7 — SEALED PREVIEWS (user ruling: "plaintext previews at rest = merge
// blocker"; spec §3 "no plaintext message text anywhere durable").
//
// The offline-first plan dropped `decrypted_body` (schema v10) but TWO
// preview columns still hold plaintext at rest today:
//   * `conversations.last_message_preview` — written by the drain-ack
//     (≤50ch body substring) and by the ingest conversation bump
//     (decrypted body / media glyph);
//   * `messages.reply_preview` — written at enqueue, at the dual-truth
//     stamp, and at ingest (decrypted server reply preview).
//
// Brief (TDD, RED first):
//   1. send path  — real send → raw SQL over EVERY table never contains
//                   the body or the reply preview (RED today);
//   2. ingest path — cold fetch of a ciphertext record → same absence
//                   assertion (RED today);
//   3. read path  — seeded ciphertext-only DB: conversation tile derives
//                   the preview from `messageBodyProvider`; the reply
//                   quote derives the parent text from the same provider
//                   (quote arm RED today — it renders from the column);
//   4. placeholder — keyless/pending parent → tile AND quote render the
//                   keyed placeholder, never blank, never throws
//                   (quote arm RED today — no column ⇒ no quote at all);
//   5. migration  — fresh v11 + real v10→v11 onUpgrade leave NO preview
//                   column in `sqlite_master` and no preview field in
//                   `SELECT *` (RED today — both columns exist).
//
// Deviation note: nothing here prints raw ciphertext in a quote — the
// quote only ever renders provider-resolved text or the placeholder.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart'
    show reactionsProvider;
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/message_body_text.dart';
import 'package:kuch_bhi/features/chat/widgets/message_bubble.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart'
    show MessageRepositoryImpl, messageRepositoryProvider;
import 'package:kuch_bhi/services/encryption_service.dart' show EncryptResult;

import 'char_harness.dart';

/// The marker every "must not be at rest" assertion greps for.
const String kSecret = 'secret-phrase-xyz';
const String kSecretReply = 'secret-reply-xyz';

/// Dump EVERY text value in EVERY table (sqlite_master says which ones
/// exist at this schema version — no hard-coded table list, so a preview
/// column hiding anywhere is still caught).
Future<Set<String>> _allTextValues(AppDatabase db) async {
  final tables = await db
      .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
      .get();
  final out = <String>{};
  for (final t in tables) {
    final name = t.read<String>('name');
    final rows = await db.customSelect('SELECT * FROM "$name"').get();
    for (final r in rows) {
      for (final v in r.data.values) {
        if (v is String) out.add(v);
      }
    }
  }
  return out;
}

/// Send-path HTTP: SSE hangs (T1 widget rule), the messages create
/// succeeds, everything else 404s (mirrors T9.6's client).
Future<http.Response> _sendPathClient(http.Request req) async {
  if (req.url.path.startsWith('/api/realtime')) {
    return Completer<http.Response>().future;
  }
  if (req.method == 'POST' &&
      req.url.path.contains('/collections/messages/records')) {
    return http.Response(
      jsonEncode({
        'id': 'srv_p7send0000001',
        'collectionId': 'messages',
        'collectionName': 'messages',
        'created': '2026-10-07T10:00:00.000Z',
        'updated': '2026-10-07T10:00:00.000Z',
        'fields': <String, Object>{},
        'conversation_id': 'g1',
        'sender_id': 'u_test',
        'type': 'text',
        'encrypted_body': 'x',
        'iv': 'y',
        'reply_to_id': '',
        'reply_preview': '',
        'is_deleted_for_everyone': false,
        'is_deleted_for_me': false,
        'is_pinned': false,
        'is_starred': false,
        'status': 'sent',
        'media_id': '',
      }),
      201,
      headers: {'content-type': 'application/json'},
    );
  }
  return http.Response('{"message":"not found"}', 404);
}

/// Ingest-path HTTP: SSE hangs, the messages LIST carries an encrypted
/// body AND a LEGACY-PLAINTEXT `reply_preview` (both fields a real server
/// record has) — the absence assertion below covers both shapes.
MockClient _ingestListClient({required EncryptResult enc}) =>
    MockClient((req) async {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (!req.url.path.contains('/collections/messages/records')) {
        return http.Response('{"message":"unhandled"}', 404);
      }
      return http.Response(
        jsonEncode({
          'page': 1, 'perPage': 40, 'totalItems': 1, 'totalPages': 1,
          'items': [{
            'id': 'srv1',
            'collectionId': 'messages', 'collectionName': 'messages',
            'created': '2026-10-07T10:00:00.000Z',
            'updated': '2026-10-07T10:00:00.000Z',
            'fields': <String, Object>{},
            'conversation_id': 'g1', 'sender_id': 'u_peer',
            'type': 'text',
            'encrypted_body': enc.ciphertext, 'iv': enc.iv,
            'reply_to_id': '',
            // Legacy plaintext shape — must never be persisted.
            'reply_preview': kSecretReply,
            'is_deleted_for_everyone': false, 'is_deleted_for_me': false,
            'is_pinned': false, 'is_starred': false,
            'status': 'sent', 'media_id': '',
          }],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

/// Two-queue drain (see placeholder_ui_test._drain): fake pumps + real
/// yields until the under-test async walk settles.
Future<void> _drain(WidgetTester tester, {int cycles = 16}) async {
  for (var i = 0; i < cycles; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Seeds a conversation + a SINGLE ciphertext text row (no preview column
/// value anywhere) plus the fixture group key, so a provider read is the
/// only way to obtain the plaintext.
Future<MessageRepositoryImpl> _seedCiphertextConversation(
  CharHarness h, {
  required String localId,
  required String serverId,
  required String plaintext,
}) async {
  await seedConversationAndKey(h, withKey: true);
  final enc =
      await h.encryption.encryptMessage(plaintext, fixtureGroupKey);
  final at = DateTime.utc(2026, 10, 7, 10);
  await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
    localId: localId,
    serverId: Value(serverId),
    conversationId: 'g1',
    senderId: 'u_peer',
    type: 'text',
    encryptedBody: enc.ciphertext,
    iv: enc.iv,
    status: const Value('sent'),
    decryptState: const Value('ready'),
    createdAt: at,
    updatedAt: at,
  ));
  await h.db.conversationsDao.upsertConversation(
    ConversationsTableCompanion.insert(
      id: 'g1',
      type: 'group',
      createdById: 'u_test',
      lastMessageAt: Value(at),
      createdAt: at,
      updatedAt: at,
    ),
  );
  return buildRepo(h);
}

void main() {
  setUp(bodyCache.clear);

  // ── 1. Send path (RED today) ──────────────────────────────────────────
  test('P7.1 send path: raw SQL over every table never holds the sent body',
      () async {
    final h = charHarness(clientFactory: () => MockClient(_sendPathClient));
    addTearDown(h.close);
    await seedConversationAndKey(h);
    final repo = buildRepo(h);

    // A reply send too: the parent id is the ONLY reply-shaped datum the
    // repository gets (there is no replyPreview parameter anymore).
    final parentAt = DateTime.utc(2026, 10, 7, 9);
    await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'parent_secret00001',
      serverId: const Value('srv_parentsecret1'),
      conversationId: 'g1',
      senderId: 'u_peer',
      type: 'text',
      encryptedBody: 'ct-parent',
      iv: 'iv-parent',
      status: const Value('sent'),
      createdAt: parentAt,
      updatedAt: parentAt,
    ));

    await repo.sendMessage(
      conversationId: 'g1',
      plaintext: kSecret,
      replyToLocalId: 'parent_secret00001',
    );
    // Let the outbox drain land the row + the conversation preview bump.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final rows = await h.db.messagesDao.watchMessages('g1').first;
      if (rows.isNotEmpty && rows.first.status == 'sent') break;
    }

    final values = await _allTextValues(h.db);
    expect(
      values.where((v) => v.contains(kSecret)),
      isEmpty,
      reason: 'spec §3 — the SENT BODY must never appear in any Drift '
          'column (conversations.last_message_preview stores a ≤50ch '
          'substring of it today)',
    );
    expect(
      values.where((v) => v.contains(kSecretReply)),
      isEmpty,
      reason: 'spec §3 — no preview-shaped copy of a quoted parent body may '
          'land at rest either (messages.reply_preview persisted the '
          'composer-supplied preview at enqueue today)',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ── 2. Ingest path (RED today) ───────────────────────────────────────
  test('P7.2 ingest path: a cold-fetched record (encrypted body + '
      'legacy-plaintext reply_preview) leaves no plaintext in any table',
      () async {
    final pre = charHarness(); // throwaway — only encrypts the fixture
    addTearDown(pre.close);
    final enc = await pre.encryption.encryptMessage(kSecret, fixtureGroupKey);

    final h = charHarness(
        clientFactory: () => _ingestListClient(enc: enc));
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: true);
    final repo = buildRepo(h);

    await repo.watchMessages('g1').first; // cold path: fetch + cache + bump

    final values = await _allTextValues(h.db);
    expect(
      values.where((v) => v.contains(kSecret)),
      isEmpty,
      reason: 'spec §3 — the ingest conversation bump must not persist the '
          'decrypted body as conversations.last_message_preview',
    );
    expect(
      values.where((v) => v.contains(kSecretReply)),
      isEmpty,
      reason: 'spec §3 — the ingest path must not decrypt-and-store the '
          "record's `reply_preview` into messages.reply_preview "
          '(both the encrypted and the legacy-plaintext server shape)',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ── 3. Read path ─────────────────────────────────────────────────────
  testWidgets(
      'P7.3 read path: tile derives its preview from messageBodyProvider; '
      'reply quote derives the parent text (no stored preview string)',
      (tester) async {
    const parentLocal = 'parent00000000001';
    const parentServer = 'srv_parent00000001';
    const parentText = 'derived parent body that the quote must resolve';

    late final CharHarness h;
    late final MessageRepositoryImpl repo;
    await tester.runAsync(() async {
      h = charHarness();
      addTearDown(h.close);
      repo = await _seedCiphertextConversation(
        h,
        localId: parentLocal,
        serverId: parentServer,
        plaintext: parentText,
      );
    });

    // ── 3a. conversation tile ─────────────────────────────────────────
    // (the PARENT is the newest row here — the replying child is inserted
    //  after this block so the tile's "last message" pointer targets it)
    final convRow = await tester.runAsync(
        () => h.db.conversationsDao.getConversationById('g1'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(h.db),
        messageRepositoryProvider.overrideWithValue(repo),
        outboxStatusProvider
            .overrideWith((ref, convId) => Stream.value(const [])),
        reactionsProvider.overrideWith((ref, id) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: ConversationPreviewText(
            conversation: Conversation(
              id: convRow!.id,
              type: convRow.type,
              name: convRow.name,
              lastMessageAt: convRow.lastMessageAt,
            ),
            fallback: 'Tap to open chat',
          ),
        ),
      ),
    ));
    await _drain(tester);
    expect(tester.takeException(), isNull);
    expect(
      find.text(parentText),
      findsOneWidget,
      reason: 'the tile derives the preview by decrypting the last row '
          'through messageBodyProvider — never from a stored column',
    );

    // ── 3b. reply quote ──────────────────────────────────────────────
    // The replying CHILD row carries only the parent id — NO preview text
    // (the column is gone; nothing at rest to read). Inserted AFTER the
    // tile block so the tile's newest-row pointer still targets the parent.
    await tester.runAsync(() async {
      await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId: 'child000000000001',
        serverId: const Value('srv_child00000001'),
        conversationId: 'g1',
        senderId: 'u_test',
        type: 'text',
        encryptedBody: 'ct-child',
        iv: 'iv-child',
        replyToId: const Value(parentLocal),
        status: const Value('sent'),
        createdAt: DateTime.utc(2026, 10, 7, 11),
        updatedAt: DateTime.utc(2026, 10, 7, 11),
      ));
    });
    final child = Message(
      localId: 'child000000000001',
      serverId: 'srv_child00000001',
      conversationId: 'g1',
      senderId: 'u_test',
      type: 'text',
      replyToId: parentLocal,
      status: 'sent',
      createdAt: DateTime.utc(2026, 10, 7, 11),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(h.db),
        messageRepositoryProvider.overrideWithValue(repo),
        outboxStatusProvider
            .overrideWith((ref, convId) => Stream.value(const [])),
        reactionsProvider.overrideWith((ref, id) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: ListView(children: [
            MessageBubble(
              message: child,
              isMine: true,
              senderName: 'Me',
            ),
          ]),
        ),
      ),
    ));
    await _drain(tester);
    expect(tester.takeException(), isNull);
    expect(
      find.text(parentText),
      findsOneWidget,
      reason: 'the quote DERIVES the parent body through '
          'messageBodyProvider — it must not read messages.reply_preview '
          '(dropped) and must never print raw ciphertext',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ── 4. Placeholder law ───────────────────────────────────────────────
  testWidgets(
      'P7.4 placeholder: keyless parent renders the keyed placeholder in '
      'the tile AND the quote — never blank, never throws',
      (tester) async {
    const parentLocal = 'parent_keyless0001';
    const parentServer = 'srv_parentkeyless1';

    late final CharHarness h;
    late final MessageRepositoryImpl repo;
    await tester.runAsync(() async {
      h = charHarness();
      addTearDown(h.close);
      // Keyless + empty ciphertext ⇒ the provider can never resolve a body.
      await seedConversationAndKey(h, withKey: false);
      final at = DateTime.utc(2026, 10, 7, 10);
      await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId: parentLocal,
        serverId: Value(parentServer),
        conversationId: 'g1',
        senderId: 'u_peer',
        type: 'text',
        encryptedBody: '',
        iv: '',
        status: const Value('sent'),
        decryptState: const Value('key_missing'),
        createdAt: at,
        updatedAt: at,
      ));
      await h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId: 'child_keyless00001',
        conversationId: 'g1',
        senderId: 'u_test',
        type: 'text',
        encryptedBody: 'ct',
        iv: 'iv',
        replyToId: Value(parentLocal),
        status: const Value('sent'),
        // Older than the parent so the tile's newest-row pointer still
        // targets the keyless parent under test.
        createdAt: at.subtract(const Duration(hours: 1)),
        updatedAt: at.subtract(const Duration(hours: 1)),
      ));
      await h.db.conversationsDao.upsertConversation(
        ConversationsTableCompanion.insert(
          id: 'g1',
          type: 'group',
          createdById: 'u_test',
          lastMessageAt: Value(at),
          createdAt: at,
          updatedAt: at,
        ),
      );
      repo = buildRepo(h);
    });

    final parentPlaceholder =
        ValueKey('body-placeholder-$parentLocal');

    // ── 4a. conversation tile ─────────────────────────────────────────
    final convRow = await tester.runAsync(
        () => h.db.conversationsDao.getConversationById('g1'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(h.db),
        messageRepositoryProvider.overrideWithValue(repo),
        outboxStatusProvider
            .overrideWith((ref, convId) => Stream.value(const [])),
        reactionsProvider.overrideWith((ref, id) => Stream.value(const [])),
        // Keyless row: the provider resolves null (spec §8).
        messageBodyProvider.overrideWith((ref, id) async => null),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: ConversationPreviewText(
            conversation: Conversation(
              id: convRow!.id,
              type: convRow.type,
              name: convRow.name,
              lastMessageAt: convRow.lastMessageAt,
            ),
            fallback: 'Tap to open chat',
          ),
        ),
      ),
    ));
    await _drain(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(parentPlaceholder), findsOneWidget,
        reason: 'tile: keyless last message renders the keyed placeholder');
    expect(find.text(''), findsNothing, reason: 'never blank (spec §8)');

    // ── 4b. reply quote ──────────────────────────────────────────────
    final child = Message(
      localId: 'child_keyless00001',
      conversationId: 'g1',
      senderId: 'u_test',
      type: 'text',
      replyToId: parentLocal,
      status: 'sent',
      createdAt: DateTime.utc(2026, 10, 7, 10),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(h.db),
        messageRepositoryProvider.overrideWithValue(repo),
        outboxStatusProvider
            .overrideWith((ref, convId) => Stream.value(const [])),
        reactionsProvider.overrideWith((ref, id) => Stream.value(const [])),
        messageBodyProvider.overrideWith((ref, id) async => null),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: ListView(children: [
            MessageBubble(
              message: child,
              isMine: false,
              senderName: 'Peer',
            ),
          ]),
        ),
      ),
    ));
    await _drain(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(parentPlaceholder), findsOneWidget,
        reason: 'quote: a keyless/gone parent renders the keyed placeholder '
            '— never a blank quote, never raw ciphertext, never a throw');
    expect(find.text(''), findsNothing, reason: 'never blank (spec §8)');
  }, timeout: const Timeout(Duration(seconds: 30)));

  // ── 5. Migration ─────────────────────────────────────────────────────
  test('P7.5 migration: fresh v11 and a real v10→v11 upgrade leave NO '
      'preview column in sqlite_master and no preview field in SELECT *',
      () async {
    // (a) Fresh install — onCreate at schemaVersion 11 never creates them.
    final db = AppDatabase.test();
    for (final table in ['messages_table', 'conversations_table']) {
      final sql = await db
          .customSelect(
              "SELECT sql FROM sqlite_master WHERE type='table' AND name='$table'")
          .getSingle();
      expect(sql.read<String>('sql').contains('reply_preview'), isFalse,
          reason: 'fresh install: messages_table has no reply_preview');
      expect(sql.read<String>('sql').contains('last_message_preview'),
          isFalse,
          reason: 'fresh install: conversations_table has no '
              'last_message_preview');
    }
    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
      localId: 'm1',
      conversationId: 'g1',
      senderId: 'u1',
      type: 'text',
      encryptedBody: 'CIPHER',
      iv: 'iv',
      createdAt: DateTime.utc(2026, 10, 7),
      updatedAt: DateTime.utc(2026, 10, 7),
    ));
    await db.conversationsDao.upsertConversation(
      ConversationsTableCompanion.insert(
        id: 'g1',
        type: 'group',
        createdById: 'u1',
        createdAt: DateTime.utc(2026, 10, 7),
        updatedAt: DateTime.utc(2026, 10, 7),
      ),
    );
    final msgRow = await db.customSelect('SELECT * FROM messages_table')
        .getSingle();
    expect(msgRow.data.containsKey('reply_preview'), isFalse,
        reason: 'SELECT * must not expose reply_preview');
    final convRow = await db.customSelect('SELECT * FROM conversations_table')
        .getSingle();
    expect(convRow.data.containsKey('last_message_preview'), isFalse,
        reason: 'SELECT * must not expose last_message_preview');
    await db.close();

    // (b) Existing v10 install — REAL bytes, REAL production onUpgrade.
    final dir = await Directory.systemTemp.createTemp('p7_mig');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/kuch_bhi.sqlite');
    final before = raw.sqlite3.open(file.path);
    // Captured verbatim from drift's onCreate at schemaVersion 10.
    before.execute(_kV10MessagesCreate);
    before.execute(_kV10ConversationsCreate);
    before.execute(
      "INSERT INTO messages_table (local_id, conversation_id, sender_id, "
      "type, encrypted_body, iv, reply_preview, status, decrypt_state, "
      "key_id, created_at, updated_at) VALUES "
      "('m_old','g1','u1','text','CIPHER','ivx','$kSecretReply',"
      "'sent','ready',NULL,1760000000,1760000000)",
    );
    before.execute(
      "INSERT INTO conversations_table (id, type, created_by_id, "
      "last_message_preview, created_at, updated_at) VALUES "
      "('g1','group','u1','$kSecret',1760000000,1760000000)",
    );
    before.execute('PRAGMA user_version = 10');
    before.dispose();

    final upgraded = AppDatabase.forExecutor(NativeDatabase(file));
    // First query triggers migration 10 → 11.
    final msgs = await upgraded.select(upgraded.messagesTable).get();
    final convs = await upgraded.select(upgraded.conversationsTable).get();
    for (final table in ['messages_table', 'conversations_table']) {
      final sql = await upgraded
          .customSelect(
              "SELECT sql FROM sqlite_master WHERE type='table' AND name='$table'")
          .getSingle();
      expect(sql.read<String>('sql').contains('reply_preview'), isFalse,
          reason: 'onUpgrade 10→11 must DROP reply_preview ($table)');
      expect(sql.read<String>('sql').contains('last_message_preview'),
          isFalse,
          reason: 'onUpgrade 10→11 must DROP last_message_preview ($table)');
    }
    expect(msgs, hasLength(1), reason: 'the message row survives the drop');
    expect(msgs.first.localId, 'm_old');
    expect(msgs.first.encryptedBody, 'CIPHER',
        reason: 'ciphertext preserved verbatim through the migration');
    expect(convs, hasLength(1), reason: 'the conversation row survives');
    expect(convs.first.id, 'g1');
    expect(convs.first.lastMessageAt, isNull,
        reason: 'only the preview COLUMN went; the row stays intact');
    final rawMsg = await upgraded
        .customSelect('SELECT * FROM messages_table WHERE local_id=\'m_old\'')
        .getSingle();
    expect(rawMsg.data.containsKey('reply_preview'), isFalse,
        reason: 'SELECT * must not expose reply_preview after the upgrade');
    final rawConv = await upgraded
        .customSelect('SELECT * FROM conversations_table WHERE id=\'g1\'')
        .getSingle();
    expect(rawConv.data.containsKey('last_message_preview'), isFalse,
        reason: 'SELECT * must not expose last_message_preview after the '
            'upgrade');
    final version =
        await upgraded.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, 13, reason: 'user_version advanced');
    await upgraded.close();
  });
}

/// Exact `sqlite_master` DDL drift's onCreate produced at schemaVersion 10
/// (captured pre-drop — the v10→v11 upgrade seeds it verbatim so the
/// production onUpgrade path must remove the preview columns itself).
const String _kV10MessagesCreate = 'CREATE TABLE "messages_table" ('
    '"local_id" TEXT NOT NULL, "server_id" TEXT NULL, '
    '"conversation_id" TEXT NOT NULL, "sender_id" TEXT NOT NULL, '
    '"type" TEXT NOT NULL, "encrypted_body" TEXT NOT NULL, "iv" TEXT NOT NULL, '
    '"reply_to_id" TEXT NULL, "reply_preview" TEXT NULL, '
    '"is_deleted_for_everyone" INTEGER NOT NULL DEFAULT 0 '
    'CHECK ("is_deleted_for_everyone" IN (0, 1)), '
    '"is_deleted_for_me" INTEGER NOT NULL DEFAULT 0 '
    'CHECK ("is_deleted_for_me" IN (0, 1)), '
    '"is_pinned" INTEGER NOT NULL DEFAULT 0 '
    'CHECK ("is_pinned" IN (0, 1)), '
    '"is_starred" INTEGER NOT NULL DEFAULT 0 '
    'CHECK ("is_starred" IN (0, 1)), '
    '"expires_at" INTEGER NULL, "media_id" TEXT NULL, '
    '"status" TEXT NOT NULL DEFAULT \'pending\', '
    '"decrypt_state" TEXT NOT NULL DEFAULT \'ready\', '
    '"key_id" TEXT NULL, "created_at" INTEGER NOT NULL, '
    '"updated_at" INTEGER NOT NULL, PRIMARY KEY ("local_id"))';

const String _kV10ConversationsCreate =
    'CREATE TABLE "conversations_table" ('
    '"id" TEXT NOT NULL, "type" TEXT NOT NULL, "name" TEXT NULL, '
    '"icon_url" TEXT NULL, "created_by_id" TEXT NOT NULL, '
    '"last_message_preview" TEXT NULL, "last_message_at" INTEGER NULL, '
    '"disappearing_duration" INTEGER NOT NULL DEFAULT 0, '
    '"only_admins_can_message" INTEGER NOT NULL DEFAULT 0 '
    'CHECK ("only_admins_can_message" IN (0, 1)), '
    '"is_pinned" INTEGER NOT NULL DEFAULT 0 '
    'CHECK ("is_pinned" IN (0, 1)), '
    '"unread_count" INTEGER NOT NULL DEFAULT 0, '
    '"last_read_local_id" TEXT NULL, "mute_until" INTEGER NULL, '
    '"wallpaper_path" TEXT NULL, "created_at" INTEGER NOT NULL, '
    '"updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"))';
