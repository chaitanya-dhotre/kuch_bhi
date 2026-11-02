// 12.1 test harness: a faked `kuch_bhi/share` channel, a stub router on the
// app's root navigator key, and controllable auth / key-sync state.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/core/router/app_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/providers/encryption_sync_provider.dart';
import 'package:kuch_bhi/features/home/providers/conversations_provider.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/share_in_service.dart';

User shareUser(String id, String name) => User(
  id: id,
  displayName: name,
  username: name.toLowerCase(),
  email: '$id@example.com',
  friendCode: 'CODE01',
  createdAt: DateTime.utc(2026, 1, 1),
);

final me = shareUser('u_me', 'Me');

Conversation direct(String id, String name) =>
    Conversation(id: id, type: 'direct', otherUser: shareUser('u_$id', name));

Conversation groupChat(
  String id,
  String name, {
  int members = 5,
  bool adminsOnly = false,
}) => Conversation(
  id: id,
  type: 'group',
  name: name,
  memberCount: members,
  onlyAdminsCanMessage: adminsOnly,
);

Map<String, Object?> shareMap(List<(String mime, String name)> items,
        {String? text}) =>
    {
      'items': [
        for (final (mime, name) in items)
          {'uri': 'content://test/$name', 'mime': mime, 'name': name, 'size': 10},
      ],
      'text': text,
    };

class TestAuth extends AuthNotifier {
  TestAuth(this.initial);
  final AuthState initial;
  @override
  Future<AuthState> build() async => initial;
  void set(AuthState s) => state = AsyncData(s);
}

/// Group rule lookups for the picker's D6 check.
class GroupRuleRepo implements MessageRepository {
  GroupRuleRepo({this.roles = const {}, this.keyReady = true});
  final Map<String, String> roles; // conversation → my role
  final bool keyReady;

  @override
  Stream<List<User>> watchGroupMembers(String conversationId) => Stream.value([
    if (roles[conversationId] != null)
      User(
        id: me.id,
        displayName: me.displayName,
        username: me.username,
        email: me.email,
        friendCode: me.friendCode,
        createdAt: me.createdAt,
        groupRole: roles[conversationId],
      ),
  ]);

  @override
  Future<bool> hasUsableKey(String conversationId) async => keyReady;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class ShareHarness {
  ShareHarness(this.tester, this.container, this.router, this.auth);

  final WidgetTester tester;
  final ProviderContainer container;
  final GoRouter router;
  final TestAuth auth;
  final calls = <MethodCall>[];
  Map<String, Object?>? nextShare;

  /// Each copy's answer: a path, or throw a PlatformException.
  FutureOr<String?> Function(MethodCall call, int n) onCopy = (call, n) =>
      '/cache/share_in/$n/${call.arguments['name']}';
  int _copies = 0;

  List<String> get methods => [for (final c in calls) c.method];
  int get copies => methods.where((m) => m == 'copyShared').length;

  void _install() {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      shareChannel,
      (call) async {
        calls.add(call);
        switch (call.method) {
          case 'takeShare':
            final s = nextShare;
            nextShare = null;
            return s;
          case 'copyShared':
            return onCopy(call, ++_copies);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        shareChannel,
        null,
      ),
    );
  }

  /// A warm share: Android calls `shareArrived`, Dart takes it.
  Future<void> arrive(Map<String, Object?> share) async {
    nextShare = share;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      shareChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('shareArrived'),
      ),
      (_) {},
    );
    await tester.pump();
  }

  Future<void> start() async {
    await container.read(shareInServiceProvider).start();
    await tester.pump();
    await tester.pump();
  }
}

Widget _stub(String label) => Scaffold(body: Center(child: Text(label)));

EncryptionSyncStatus? syncStatus = EncryptionSyncStatus.keyOk;

Future<ShareHarness> pumpShareApp(
  WidgetTester tester, {
  AuthState? auth,
  String initial = AppRoutes.splash,
  List<Conversation> convs = const [],
  MessageRepository? repo,
  Map<String, Object?>? share,
  double textScale = 1,
  String? font,
  bool reduceMotion = false,
}) async {
  syncStatus = EncryptionSyncStatus.keyOk;
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initial,
    routes: [
      for (final path in [
        AppRoutes.splash,
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.home,
        AppRoutes.backupPinRestore,
      ])
        GoRoute(path: path, builder: (_, _) => _stub('at $path')),
      GoRoute(
        path: AppRoutes.chat,
        builder: (_, state) =>
            _stub('chat ${(state.extra! as Conversation).id}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  final authNotifier = TestAuth(auth ?? AuthAuthenticated(me));
  final container = ProviderContainer(
    overrides: [
      appRouterProvider.overrideWithValue(router),
      authProvider.overrideWith(() => authNotifier),
      encryptionSyncProvider.overrideWith((ref) async {
        final s = syncStatus;
        if (s == null) return Completer<EncryptionSyncStatus>().future;
        return s;
      }),
      conversationsProvider.overrideWith((ref) => Stream.value(convs)),
      messageRepositoryProvider.overrideWithValue(repo ?? GroupRuleRepo()),
    ],
  );
  addTearDown(container.dispose);
  final h = ShareHarness(tester, container, router, authNotifier)
    ..nextShare = share;
  h._install();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: warmPopLight(fontFamily: font),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pump();
  // Resolve the overridden auth + sync futures.
  container.read(encryptionSyncProvider);
  await tester.pump();
  return h;
}
