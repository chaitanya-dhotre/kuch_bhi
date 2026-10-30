import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
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

/// A set-up device (key on the phone); the server answers [kind].
class _Enc implements EncryptionService {
  _Enc(this.kind);
  final BackupKind? kind;
  @override
  Future<bool> hasLocalPrivateKey() async => true;
  @override
  Future<BackupKind?> tryGetBackupKind(String userId) async => kind;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Auth extends AuthNotifier {
  @override
  Future<AuthState> build() async => AuthAuthenticated(
    User(
      id: 'u_test',
      displayName: 'Test',
      username: 'test',
      email: 'test@example.com',
      friendCode: 'FRIEND1',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
}

class _NoFriends extends FriendshipsNotifier {
  @override
  Future<List<Friendship>> build() async => const [];
}

const _upgrade =
    "Your backup uses a short PIN that's easy to crack. Tap to get a recovery key.";
const _setup =
    'Back up your encryption key so you can restore your messages after a reinstall. Tap to set up.';

Future<void> _home(
  WidgetTester tester,
  BackupKind? kind, {
  Map<String, String> settings = const {},
}) async {
  final db = AppDatabase.test();
  addTearDown(db.close);
  for (final e in settings.entries) {
    await db.settingsDao.setSetting(e.key, e.value);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        encryptionServiceProvider.overrideWithValue(_Enc(kind)),
        authProvider.overrideWith(_Auth.new),
        appDatabaseProvider.overrideWithValue(db),
        messageRepositoryProvider.overrideWithValue(FakeMessageRepository()),
        friendshipsProvider.overrideWith(_NoFriends.new),
        pendingRequestCountProvider.overrideWithValue(0),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp(theme: warmPopLight(), home: const HomeScreen()),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('legacy backup → the upgrade banner, with its own dismiss', (
    tester,
  ) async {
    await _home(tester, BackupKind.legacy);
    expect(find.text(_upgrade), findsOneWidget);
    expect(find.text(_setup), findsNothing);
    expect(find.byTooltip('Dismiss reminder'), findsOneWidget);
  });

  testWidgets('recovery-key backup → no banner', (tester) async {
    await _home(tester, BackupKind.current);
    expect(find.text(_upgrade), findsNothing);
    expect(find.text(_setup), findsNothing);
  });

  testWidgets('no backup → the set-up banner only', (tester) async {
    await _home(tester, BackupKind.none);
    expect(find.text(_setup), findsOneWidget);
    expect(find.text(_upgrade), findsNothing);
  });

  testWidgets('unknown (offline / any error) → no banner', (tester) async {
    await _home(tester, null);
    expect(find.text(_upgrade), findsNothing);
    expect(find.text(_setup), findsNothing);
  });

  testWidgets('upgrade dismissed under 7 days ago → hidden', (tester) async {
    final recent = DateTime.now().subtract(const Duration(days: 6));
    await _home(
      tester,
      BackupKind.legacy,
      settings: {'backup_upgrade_dismissed_at': recent.toIso8601String()},
    );
    expect(find.text(_upgrade), findsNothing);
  });

  testWidgets('upgrade dismissed 8 days ago → back', (tester) async {
    final old = DateTime.now().subtract(const Duration(days: 8));
    await _home(
      tester,
      BackupKind.legacy,
      settings: {'backup_upgrade_dismissed_at': old.toIso8601String()},
    );
    expect(find.text(_upgrade), findsOneWidget);
  });

  testWidgets('dismissing the upgrade banner hides it and records the time', (
    tester,
  ) async {
    await _home(tester, BackupKind.legacy);
    await tester.tap(find.byTooltip('Dismiss reminder'));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text(_upgrade), findsNothing);
  });
}
