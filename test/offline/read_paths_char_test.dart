import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

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
  // Production behavior pinned: message_bubble.dart `_TextBubble` renders
  // `message.decryptedBody ?? '🔒 Encrypted'` and the build-time body is
  // `decryptedBody ?? ''` (so no emoji-only path, no empty Text).
  testWidgets(
      'char: real MessageBubble renders null-body text as fallback, '
      'no exception, no empty text', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
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
    expect(tester.takeException(), isNull,
        reason: 'null-body bubble must render without throwing');
    expect(find.text('🔒 Encrypted'), findsOneWidget,
        reason: 'production fallback in _TextBubble (message_bubble.dart)');
    expect(find.text(''), findsNothing,
        reason: 'production never displays an empty text bubble');
  });

  // ── 2. Preview: REAL HomeScreen → _ConversationTile → ChatTile ──────────
  // Null-body last message flows through the production preview computation
  // (`_bumpConversationForIncoming` → previewText null → 'New message',
  // message_repository_impl.dart:2968) into the conversation-list entity,
  // then the real _ConversationTile feeds the real ChatTile subtitle.
  testWidgets(
      'char: null-body last message reaches ChatTile via real preview path',
      (tester) async {
    // Real async (compute()/isolate decrypt, DB I/O) must run OUTSIDE the
    // testWidgets FakeAsync zone — awaiting it in the body hangs.
    final h2 = charHarness(clientFactory: () => fetchListClient(conversationId: 'g1'));
    addTearDown(h2.close);
    late final MessageRepositoryImpl repo;
    late final List<Message> coldRows;
    late final ConversationsTableData conv;
    await tester.runAsync(() async {
      await seedConversationAndKey(h2, withKey: true);
      repo = buildRepo(h2);
      // Cold fetch through the REAL repo: caches the null-body row (empty
      // ciphertext/iv → decrypt null → decryptedBody stays null) and runs
      // the production preview bump for it.
      coldRows = await repo.watchMessages('g1').first;
      conv = (await h2.db.conversationsDao.getConversationById('g1'))!;
    });

    expect(coldRows, isEmpty,
        reason: 'null-body row hidden from chat stream (group cutoff)');
    expect(conv.lastMessagePreview, 'New message',
        reason: 'production preview computation for a null decryptedBody '
            '(message_repository_impl.dart:2968)');

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
    // Let conversationsProvider's Drift stream resolve into AsyncData.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    expect(find.byType(ChatTile), findsOneWidget);
    expect(find.text('New message'), findsOneWidget,
        reason: 'real _ConversationTile feeds production preview to ChatTile');

    // Drift schedules a Timer.run (0ms) when a query stream closes
    // (stream_queries.dart markAsClosed). Unmounting here — before the
    // testWidgets pending-timer invariant runs — and elapsing 1ms flushes
    // it; otherwise the invariant fails on the dispose-time timer.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  // ── 3. Search: REAL repo.searchMessages over seeded rows ────────────────
  test('char: repo.searchMessages filters null-body rows without throwing',
      () async {
    final h = charHarness(
        clientFactory: () =>
            MockClient((req) => Completer<http.Response>().future));
    addTearDown(h.close);
    await seedConversationAndKey(h);

    Future<void> row(String localId, String? body, DateTime at) =>
        h.db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
              localId: localId,
              conversationId: 'g1',
              senderId: 'u_peer',
              type: 'text',
              encryptedBody: 'x',
              iv: 'y',
              decryptedBody: Value(body),
              status: const Value('sent'),
              createdAt: at,
              updatedAt: at,
            ));

    await row('l_alpha', 'alpha', DateTime(2026, 10, 7, 10));
    await row('l_null', null, DateTime(2026, 10, 7, 11));
    await row('l_beta', 'beta', DateTime(2026, 10, 7, 12));

    final repo = buildRepo(h);
    final hits = await repo.searchMessages('g1', 'a');

    expect(hits.map((m) => m.localId).toList(), ['l_beta', 'l_alpha'],
        reason: 'ACTUAL behavior: createdAt DESC, null-body row skipped '
            '((row.decryptedBody ?? "") never matches a non-empty needle), '
            'no throw');
  });
}
