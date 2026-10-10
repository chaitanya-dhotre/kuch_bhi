import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/chat_tile.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/friendship.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/providers/encryption_sync_provider.dart';
import 'package:kuch_bhi/features/friend_requests/providers/friend_request_provider.dart';
import 'package:kuch_bhi/features/home/providers/friends_provider.dart';
import 'package:kuch_bhi/features/home/screens/home_screen.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/message_bubble.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import 'char_harness.dart';
import 'send_fetch_char_test.dart' show fetchListClient;

/// Placeholder-law characterization: every test here exercises REAL
/// production code (MessageBubble / HomeScreen→ChatTile preview path /
/// MessageRepositoryImpl.searchMessages). Tautological test-local
/// reimplementations were removed in fix round 1 — Task 9's safety net
/// must fail if the real surfaces break.

Message msg({String? body, DateTime? createdAt}) => Message(
      localId: 'l1',
      conversationId: 'c1',
      senderId: 'u2',
      type: 'text',
      decryptedBody: body,
      status: 'sent',
      createdAt: createdAt ?? DateTime(2026, 10, 7),
    );

/// Auth notifier pinned to "no session" so HomeScreen never depends on the
/// real auth repository (which would hit un-overridden providers).
class _StaticAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthUnauthenticated();
}

/// Empty friendships so HomeScreen's `isLoading` gate (home_screen.dart:137)
/// releases and renders the conversation list instead of a skeleton forever.
class _EmptyFriendships extends FriendshipsNotifier {
  @override
  Future<List<Friendship>> build() async => const [];
}

void main() {
  // ── 1. Bubble: REAL MessageBubble, null-body text message ───────────────
  // Task 9 (brief test 5): same user-visible contract as the pinned
  // baseline — renders without throwing, NEVER an empty text — but the
  // surface is now the keyed placeholder widget (spec §8): the provider
  // resolves null (no body available) → skeleton + 🔒, never blank.
  testWidgets(
      'char: real MessageBubble renders null-body text as placeholder, '
      'no exception, no empty text', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // Provider body stubbed to a resolved-null (hermetic — no repo/DB
        // in this label-level test; the real key_missing resolution path
        // is pinned by placeholder_ui_test T9.1).
        overrides: [
          messageBodyProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: Scaffold(
            body: ListView(children: [
              MessageBubble(
                message: msg(body: null),
                isMine: false,
                senderName: 'Zeta Sender',
                isGroup: true,
              ),
            ]),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'null-body bubble must render without throwing');
    expect(find.byKey(const ValueKey('body-placeholder-l1')), findsOneWidget,
        reason: 'placeholder law (spec §8): keyed skeleton + lock while the '
            'body is unresolved — production no longer prints a raw '
            "'🔒 Encrypted' string nor a blank");
    expect(find.text(''), findsNothing,
        reason: 'production never displays an empty text bubble');
  });

  // ── 2. Preview: REAL HomeScreen → _ConversationTile → ChatTile ──────────
  // Null-body last message flows through the production preview path
  // (cold fetch → preview bump → conversation row → _ConversationTile →
  // ChatTile subtitle). Task 9 (brief test 5): the tile's TEXT preview
  // now resolves the last message body through messageBodyProvider —
  // unresolved → keyed placeholder widget (spec §8 conversation-list
  // previews), NEVER a blank; the stored preview column itself is
  // unchanged ('New message' — asserted below).
  testWidgets(
      'char: null-body last message reaches ChatTile via real preview path '
      'as a placeholder',
      (tester) async {
    // Real async (compute()/isolate decrypt, DB I/O) must run OUTSIDE the
    // testWidgets FakeAsync zone — awaiting it in the body hangs.
    final h2 = charHarness(clientFactory: () => fetchListClient(conversationId: 'g1'));
    addTearDown(h2.close);
    late final MessageRepositoryImpl repo;
    late final List<Message> coldRows;
    late final ConversationsTableData conv;
    late final String lastLocalId;
    await tester.runAsync(() async {
      await seedConversationAndKey(h2, withKey: true);
      repo = buildRepo(h2);
      // Cold fetch through the REAL repo: caches the null-body row (empty
      // ciphertext/iv → decrypt null → decrypt_state 'pending') and runs
      // the production preview bump for it.
      coldRows = await repo.watchMessages('g1').first;
      conv = (await h2.db.conversationsDao.getConversationById('g1'))!;
      final daoRows = await h2.db.messagesDao.watchMessages('g1').first;
      lastLocalId = daoRows.first.localId;
    });

    expect(coldRows, isEmpty,
        reason: 'null-body row hidden from chat stream (group cutoff / state)');
    // P7 (inversion): `last_message_preview` is DROPPED (schema v11) — the
    // preview bump now writes ONLY the ordering timestamp, and the tile
    // derives its label (placeholder for this null-body row) at render time.
    expect(conv.lastMessageAt, isNotNull,
        reason: 'the preview bump still advances lastMessageAt (ordering + '
            'unread-badge guard are unchanged)');
    final rawConv = await h2.db
        .customSelect("SELECT * FROM conversations_table WHERE id = 'g1'")
        .getSingle();
    expect(rawConv.data.containsKey('last_message_preview'), isFalse,
        reason: 'spec §3 / P7: no preview column exists to store it');
    expect(lastLocalId, isNotEmpty);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        pocketbaseClientProvider.overrideWithValue(h2.pbClient),
        messageRepositoryProvider.overrideWithValue(repo),
        authProvider.overrideWith(_StaticAuth.new),
        friendshipsProvider.overrideWith(_EmptyFriendships.new),
        pendingRequestCountProvider.overrideWithValue(0),
        showBackupBannerProvider.overrideWith((ref) async => false),
        appDatabaseProvider.overrideWithValue(h2.db),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: const HomeScreen(),
      ),
    ));
    // Let conversationsProvider's Drift stream resolve into AsyncData, and
    // the preview's body provider run its 50ms coalescing window + the
    // empty-ciphertext runFor (resolves null → placeholder). Two-queue
    // drain (see placeholder_ui_test._drain): fake pumps + real yields.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(tester.takeException(), isNull);
    expect(find.byType(ChatTile), findsOneWidget);
    expect(find.byKey(ValueKey('body-placeholder-$lastLocalId')),
        findsOneWidget,
        reason: 'conversation-list preview renders the keyed placeholder '
            'while the last body is unresolved (spec §8) — fills when the '
            'provider emits (placeholder_ui_test T9.2 pins the fill)');
    expect(find.text(''), findsNothing,
        reason: 'preview never renders an empty Text');

    // Drift schedules a Timer.run (0ms) when a query stream closes
    // (stream_queries.dart markAsClosed). Unmounting here — before the
    // testWidgets pending-timer invariant runs — and elapsing 1ms flushes
    // it; otherwise the invariant fails on the dispose-time timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  // ── 3. Search: REAL repo.searchMessages over seeded rows ────────────────
  // Task 9: search resolves bodies ephemerally (bodyCache / DecryptPass
  // machinery) — no decrypted_body column exists to filter on. Rows are
  // seeded the way production sees them post-drop: ciphertext (or none)
  // at rest, plaintext ONLY in the session cache.
  test('char: repo.searchMessages filters bodyless rows without throwing',
      () async {
    final h = charHarness(
        clientFactory: () =>
            MockClient((req) => Completer<http.Response>().future));
    addTearDown(h.close);
    await seedConversationAndKey(h);

    Future<void> row(String localId, DateTime at) =>
        h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
              localId: localId,
              conversationId: 'g1',
              senderId: 'u_peer',
              type: 'text',
              encryptedBody: 'x',
              iv: 'y',
              status: const Value('sent'),
              createdAt: at,
              updatedAt: at,
            ));

    await row('l_alpha', DateTime(2026, 10, 7, 10));
    await row('l_null', DateTime(2026, 10, 7, 11)); // no body anywhere
    await row('l_beta', DateTime(2026, 10, 7, 12));
    // Resolved bodies live in the session cache (the only plaintext home).
    bodyCache.put('l_alpha', 'alpha');
    bodyCache.put('l_beta', 'beta');

    final repo = buildRepo(h);
    final hits = await repo.searchMessages('g1', 'a');

    expect(hits.map((m) => m.localId).toList(), ['l_beta', 'l_alpha'],
        reason: 'ACTUAL behavior preserved: createdAt DESC, bodyless row '
            'skipped (no resolved body never matches a non-empty needle), '
            'no throw, nothing written back to the DB');
  });
}
