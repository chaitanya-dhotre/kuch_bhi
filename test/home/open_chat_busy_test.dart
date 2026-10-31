import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/friendship.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/friend_requests/providers/friend_request_provider.dart';
import 'package:kuch_bhi/features/home/providers/friends_provider.dart';
import 'package:kuch_bhi/features/home/screens/home_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/encryption_service.dart';

import '../fakes/fake_message_repository.dart';

/// Bug wave 2 §6.4: tapping a friend whose chat must first be fetched shows
/// that it is working, ignores more taps, and gives up after 8s.
class _Enc implements EncryptionService {
  @override
  Future<bool> hasLocalPrivateKey() async => true;
  @override
  Future<BackupKind?> tryGetBackupKind(String userId) async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

User _user(String id, String name) => User(
      id: id,
      displayName: name,
      username: name.toLowerCase(),
      email: '$id@example.com',
      friendCode: 'CODE01',
      createdAt: DateTime.utc(2026, 1, 1),
    );

class _Auth extends AuthNotifier {
  @override
  Future<AuthState> build() async => AuthAuthenticated(_user('u_test', 'Me'));
}

class _OneFriend extends FriendshipsNotifier {
  @override
  Future<List<Friendship>> build() async => [
        Friendship(
          id: 'f1',
          friend: _user('u_aanya', 'Aanya'),
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ];
}

/// The server never answers the open-chat sync.
class _Stalled extends FakeMessageRepository {
  int opens = 0;
  @override
  Future<Conversation> getOrCreateDirectConversation(String otherUserId) {
    opens++;
    return Completer<Conversation>().future;
  }
}

void main() {
  testWidgets('a stalled open: busy subtitle, one call for two taps, and the '
      'toast after 8s (360dp, 200%)', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.test();
    addTearDown(db.close);
    final repo = _Stalled();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        encryptionServiceProvider.overrideWithValue(_Enc()),
        authProvider.overrideWith(_Auth.new),
        appDatabaseProvider.overrideWithValue(db),
        messageRepositoryProvider.overrideWithValue(repo),
        friendshipsProvider.overrideWith(_OneFriend.new),
        pendingRequestCountProvider.overrideWithValue(0),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: const HomeScreen(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    // Home already overflows at 200% before any tap (tracked on its own);
    // only an overflow from the busy tile counts here.
    tester.takeException();

    final tile = find.byKey(const ValueKey('chat-tile-friend-u_aanya'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pump();
    expect(find.text('Opening chat…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(tile);
    await tester.pump();
    expect(repo.opens, 1, reason: 'a second tap while opening is ignored');

    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(find.text('Chat is not ready yet. Try again in a moment.'),
        findsOneWidget);
    expect(find.text('Opening chat…'), findsNothing);
  });
}
