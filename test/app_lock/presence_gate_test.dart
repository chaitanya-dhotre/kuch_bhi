import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/app.dart';
import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/core/router/app_router.dart';
import 'package:kuch_bhi/data/local/secure_storage/secure_storage_service.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/app_lock/app_lock_controller.dart';
import 'package:kuch_bhi/features/app_lock/app_lock_platform.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/screens/chat_screen.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:kuch_bhi/features/settings/providers/theme_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/presence_service.dart';
import 'package:local_auth/local_auth.dart';

import '../core/sheet_harness.dart';

const _hash = 'C/gKg+uv7xoYEBp/eC4h3o+8Ljh1ILHNtCJlIRUU/8w=';

String _entry() => AppLockConfig(
  salt: 'AAAAAAAAAAAAAAAAAAAAAA==',
  hash: _hash,
  iter: 10000,
  bio: false,
  after: 60,
  hideNames: true,
  fails: 0,
  waitUntil: null,
).encode();

class _Storage extends SecureStorageService {
  _Storage([String? entry]) {
    if (entry != null) values['app_lock'] = entry;
  }
  final values = <String, String>{};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

class _Platform extends AppLockPlatform {
  @override
  Future<int?> elapsedRealtime() async => null; // no boot clock in tests

  @override
  Future<bool> isDeviceSupported() async => false;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [];

  @override
  Future<void> setHideInRecents(bool hide) async {}
}

class _Presence implements PresenceService {
  int onlineCalls = 0;
  int offlineCalls = 0;

  @override
  Future<void> goOnline() async => onlineCalls++;

  @override
  Future<void> goOffline() async => offlineCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Repo extends FakeMessageRepository {
  int resyncCalls = 0;

  @override
  Future<void> resyncOnResume({Duration? awayFor}) async => resyncCalls++;
}

class _ChatRepo extends FakeMessageRepository {
  int markReadCalls = 0;
  final more = StreamController<List<Message>>.broadcast();

  @override
  Stream<List<Message>> watchMessages(String conversationId) async* {
    yield const [];
    yield* more.stream;
  }

  @override
  Stream<Conversation?> watchConversation(String conversationId) =>
      Stream.value(const Conversation(id: 'c1', type: 'direct'));

  @override
  Future<int> countUndecryptable(String conversationId) async => 0;

  @override
  Future<bool> hasUsableKey(String conversationId) async => true;

  @override
  Future<void> markConversationRead(String conversationId) async =>
      markReadCalls++;
}

class _ChatPresence implements PresenceService {
  int enterCalls = 0;
  int leaveCalls = 0;

  @override
  Future<void> enterChat(String conversationId) async => enterCalls++;

  @override
  Future<void> leaveChat(String conversationId) async => leaveCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Auth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthUnauthenticated();

  @override
  Future<void> refreshSessionThrottled() async {}
}

Future<(_Presence, _Repo)> _pumpApp(
  WidgetTester tester, {
  required String? entry,
  required bool locked,
}) async {
  final presence = _Presence();
  final repo = _Repo();
  final storage = _Storage(entry);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('home')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        authProvider.overrideWith(() => _Auth()),
        presenceServiceProvider.overrideWithValue(presence),
        messageRepositoryProvider.overrideWithValue(repo),
        secureStorageProvider.overrideWithValue(storage),
        appLockPlatformProvider.overrideWithValue(_Platform()),
        appLockProvider.overrideWith(
          () => AppLockController(initialEntry: entry, initiallyLocked: locked),
        ),
        themeModeProvider.overrideWith(
          (ref) => Stream.value(AppThemeMode.light),
        ),
        fontFamilyProvider.overrideWith((ref) => Stream.value(AppFont.jakarta)),
      ],
      child: const KuchBhiApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (presence, repo);
}

void main() {
  testWidgets(
    'locked KuchBhiApp resume waits for unlock before goOnline',
    (tester) async {
      final (presence, repo) = await _pumpApp(
        tester,
        entry: _entry(),
        locked: true,
      );
      expect(presence.onlineCalls, 0);
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(KuchBhiApp)),
      ).read(appLockProvider.notifier);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(presence.onlineCalls, 0);
      expect(repo.resyncCalls, greaterThanOrEqualTo(1));

      await controller.unlockWithBiometric();
      await tester.pump();
      await tester.pump();
      expect(presence.onlineCalls, 1);
    },
  );

  testWidgets(
    'lock-off KuchBhiApp goes online on resume as before',
    (tester) async {
      final (presence, _) = await _pumpApp(tester, entry: null, locked: false);
      expect(presence.onlineCalls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(presence.onlineCalls, 2);
    },
  );

  test(
    'controller-level gate keeps presence work pending while covered',
    () async {
      final storage = _Storage(_entry());
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          appLockPlatformProvider.overrideWithValue(_Platform()),
          appLockProvider.overrideWith(
            () => AppLockController(initialEntry: storage.values['app_lock']),
          ),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(appLockProvider.notifier);
      controller.onHidden(DateTime(2026, 11, 3));
      var released = false;
      final waiter = controller.whenUnlocked().then((_) => released = true);
      await Future<void>.delayed(Duration.zero);
      expect(released, false);
      await controller.onResumed(DateTime(2026, 11, 3, 0, 0, 1));
      await waiter;
      expect(released, true);
    },
  );

  testWidgets(
    'locked ChatScreen delays read receipt and enterChat until unlock',
    (tester) async {
      final entry = _entry();
      final storage = _Storage(entry);
      final repo = _ChatRepo();
      final presence = _ChatPresence();
      await pumpHost(
        tester,
        SheetLauncher(
          (context, ref) => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: const ChatScreen(
                  conversation: Conversation(id: 'c1', type: 'direct'),
                ),
              ),
            ),
          ),
        ),
        overrides: [
          messageRepositoryProvider.overrideWithValue(repo),
          presenceServiceProvider.overrideWithValue(presence),
          appLockProvider.overrideWith(
            () => AppLockController(initialEntry: entry, initiallyLocked: true),
          ),
          secureStorageProvider.overrideWithValue(storage),
          appLockPlatformProvider.overrideWithValue(_Platform()),
          currentUserIdProvider.overrideWith((ref) async => 'u_test'),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          messageBodyProvider.overrideWith((ref, id) async => null),
          outboxStatusProvider.overrideWith(
            (ref, id) => Stream.value(const []),
          ),
          reactionsProvider.overrideWith((ref, id) => Stream.value(const [])),
        ],
      );
      await tapOpen(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(repo.markReadCalls, 0);
      expect(presence.enterCalls, 0);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      await container.read(appLockProvider.notifier).unlockWithBiometric();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(repo.markReadCalls, 1);
      expect(presence.enterCalls, 1);
    },
  );

  testWidgets(
    'a message arriving under the lock is not marked read until unlock',
    (tester) async {
      final entry = _entry();
      final storage = _Storage(entry);
      final repo = _ChatRepo();
      final presence = _ChatPresence();
      await pumpHost(
        tester,
        SheetLauncher(
          (context, ref) => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: const ChatScreen(
                  conversation: Conversation(id: 'c1', type: 'direct'),
                ),
              ),
            ),
          ),
        ),
        overrides: [
          messageRepositoryProvider.overrideWithValue(repo),
          presenceServiceProvider.overrideWithValue(presence),
          appLockProvider.overrideWith(
            () => AppLockController(initialEntry: entry, initiallyLocked: true),
          ),
          secureStorageProvider.overrideWithValue(storage),
          appLockPlatformProvider.overrideWithValue(_Platform()),
          currentUserIdProvider.overrideWith((ref) async => 'u_test'),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          messageBodyProvider.overrideWith((ref, id) async => null),
          outboxStatusProvider.overrideWith(
            (ref, id) => Stream.value(const []),
          ),
          reactionsProvider.overrideWith((ref, id) => Stream.value(const [])),
        ],
      );
      await tapOpen(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(repo.markReadCalls, 0);
      // The 1.5 s mark-read debounce runs on every new message (SSE or
      // resync backfill); it must wait for the unlock too (F5).
      repo.more.add([
        Message(
          localId: 'm1',
          conversationId: 'c1',
          senderId: 'u_other',
          type: 'text',
          status: 'delivered',
          createdAt: DateTime(2026, 11, 3),
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(repo.markReadCalls, 0);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      await container.read(appLockProvider.notifier).unlockWithBiometric();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      // One from opening the chat, one from the debounced new message.
      expect(repo.markReadCalls, 2);
      expect(presence.enterCalls, 1);
    },
  );
}
