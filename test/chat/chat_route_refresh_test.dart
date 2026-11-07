import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/core/router/app_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/friendship.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/providers/encryption_sync_provider.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/screens/chat_screen.dart';
import 'package:kuch_bhi/features/friend_requests/providers/friend_request_provider.dart';
import 'package:kuch_bhi/features/groups/screens/group_settings_screen.dart';
import 'package:kuch_bhi/features/home/providers/conversations_provider.dart';
import 'package:kuch_bhi/features/home/providers/friends_provider.dart';
import 'package:kuch_bhi/features/home/screens/home_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/encryption_service.dart';
import 'package:kuch_bhi/services/presence_service.dart';

import '../auth/auth_harness.dart';

/// The M52, 2026-11-07: a chat tapped within a second of a cold start, while
/// the key check was reloading. The check finished, the REAL router refreshed,
/// and the pushed chat came back from go_router's encoded stack without its
/// Conversation: `Null` is not a `Conversation`, a grey screen in release.

final _me = User(
  id: 'u_test',
  displayName: 'Test',
  username: 'test',
  email: 'test@example.com',
  friendCode: 'FRIEND1',
  createdAt: DateTime.utc(2026, 1, 1),
);
const _chat = Conversation(id: 'c1', type: 'direct');
const _group = Conversation(id: 'g1', type: 'group', name: 'Group');

class _Repo extends FakeMessageRepository {
  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream.value(const []);
  @override
  Stream<Conversation?> watchConversation(String conversationId) =>
      Stream.value(_chat);
  @override
  Future<int> countUndecryptable(String conversationId) async => 0;
  @override
  Future<bool> hasUsableKey(String conversationId) async => true;
  @override
  Future<void> markConversationRead(String conversationId) async {}
}

class _Presence implements PresenceService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Enc implements EncryptionService {
  @override
  Future<bool> hasLocalPrivateKey() async => true;
  @override
  Future<BackupKind?> tryGetBackupKind(String userId) async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _NoFriends extends FriendshipsNotifier {
  @override
  Future<List<Friendship>> build() async => [];
}

class _Route {
  _Route(this.tester, this.container);
  final WidgetTester tester;
  final ProviderContainer container;
  GoRouter get router => container.read(appRouterProvider);

  Future<void> settle() async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Signed in, key ok, on Home. [sync] answers every key check.
Future<_Route> _toHome(
  WidgetTester tester,
  Future<EncryptionSyncStatus> Function() sync,
) async {
  final db = AppDatabase.test();
  addTearDown(db.close);
  final c = ProviderContainer(overrides: [
    authProvider.overrideWith(() => FakeAuthNotifier(AuthAuthenticated(_me))),
    encryptionSyncProvider.overrideWith((ref) => sync()),
    appDatabaseProvider.overrideWithValue(db),
    encryptionServiceProvider.overrideWithValue(_Enc()),
    friendshipsProvider.overrideWith(_NoFriends.new),
    pendingRequestCountProvider.overrideWithValue(0),
    conversationsProvider.overrideWith((ref) => Stream.value(const [])),
    messageRepositoryProvider.overrideWithValue(_Repo()),
    presenceServiceProvider.overrideWithValue(_Presence()),
    currentUserIdProvider.overrideWith((ref) async => _me.id),
    isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    messageBodyProvider.overrideWith((ref, id) async => null),
    outboxStatusProvider.overrideWith((ref, id) => Stream.value(const [])),
    reactionsProvider.overrideWith((ref, id) => Stream.value(const [])),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(
        theme: warmPopLight(), routerConfig: c.read(appRouterProvider)),
  ));
  final r = _Route(tester, c);
  await r.settle();
  expect(find.byType(HomeScreen), findsOneWidget);
  return r;
}

void main() {
  testWidgets('a key check finishing after the tap leaves the chat open, '
      'same state', (tester) async {
    var answer = Future.value(EncryptionSyncStatus.keyOk);
    final r = await _toHome(tester, () => answer);

    // The key check starts reloading, then the tile is tapped.
    final finish = Completer<EncryptionSyncStatus>();
    answer = finish.future;
    r.container.invalidate(encryptionSyncProvider);
    await tester.pump();
    r.router.push(AppRoutes.chat, extra: _chat);
    await r.settle();
    expect(find.byType(ChatScreen), findsOneWidget);
    final before = tester.state(find.byType(ChatScreen));
    await tester.enterText(find.byType(TextField).last, 'half a thought');

    finish.complete(EncryptionSyncStatus.keyOk);
    await r.settle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(identical(tester.state(find.byType(ChatScreen)), before), isTrue,
        reason: 'ChatScreen must not remount');
    expect(tester.widget<ChatScreen>(find.byType(ChatScreen)).conversation,
        same(_chat));
    expect(find.text('half a thought'), findsOneWidget);

    // Back still lands on Home.
    r.router.pop();
    await r.settle();
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('an auth re-publish keeps group settings and what an FCM tap '
      'reads from the top page', (tester) async {
    final r = await _toHome(tester, () async => EncryptionSyncStatus.keyOk);
    r.router.push(AppRoutes.groupSettings, extra: _group);
    await r.settle();

    r.container.read(routerRefreshNotifierProvider).notifyListeners();
    await r.settle();

    expect(tester.takeException(), isNull);
    expect(find.byType(GroupSettingsScreen), findsOneWidget);
    expect(r.router.state.extra, same(_group));
  });

  testWidgets('a picker open over the chat survives the refresh and still '
      'returns its result', (tester) async {
    final r = await _toHome(tester, () async => EncryptionSyncStatus.keyOk);
    r.router.push(AppRoutes.chat, extra: _chat);
    await r.settle();

    final picked = Navigator.of(tester.element(find.byType(ChatScreen)))
        .push<String>(MaterialPageRoute(builder: (_) => const Text('picker')));
    await r.settle();
    r.container.read(routerRefreshNotifierProvider).notifyListeners();
    await r.settle();

    expect(tester.takeException(), isNull);
    expect(find.text('picker'), findsOneWidget);
    Navigator.of(tester.element(find.text('picker'))).pop('photo');
    await r.settle();
    expect(await picked, 'photo');
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  testWidgets('a page the stack lost the Conversation for goes back to Home',
      (tester) async {
    final r = await _toHome(tester, () async => EncryptionSyncStatus.keyOk);
    for (final route in [AppRoutes.chat, AppRoutes.groupSettings]) {
      r.router.push(route);
      await r.settle();
      expect(tester.takeException(), isNull);
      expect(find.byType(HomeScreen), findsOneWidget);
    }
  });
}
