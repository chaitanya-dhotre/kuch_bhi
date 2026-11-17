import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/core/router/app_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/settings_tile.dart';
import 'package:kuch_bhi/data/local/secure_storage/secure_storage_service.dart';
import 'package:kuch_bhi/features/app_lock/app_lock_controller.dart';
import 'package:kuch_bhi/features/app_lock/app_lock_platform.dart';
import 'package:kuch_bhi/features/app_lock/app_lock_settings_screen.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:kuch_bhi/features/settings/providers/notification_status_provider.dart';
import 'package:kuch_bhi/features/settings/providers/theme_provider.dart';
import 'package:kuch_bhi/features/settings/screens/settings_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/services/encryption_service.dart';
import 'package:local_auth/local_auth.dart';

const _oldPin = '246813';
const _newPin = '135790';
const _hash = 'C/gKg+uv7xoYEBp/eC4h3o+8Ljh1ILHNtCJlIRUU/8w=';

String _entry({
  bool bio = false,
  int after = 60,
  bool hideNames = true,
  int fails = 0,
}) => AppLockConfig(
  salt: 'AAAAAAAAAAAAAAAAAAAAAA==',
  hash: _hash,
  iter: 10000,
  bio: bio,
  after: after,
  hideNames: hideNames,
  fails: fails,
  waitUntil: null,
).encode();

class _Storage extends SecureStorageService {
  final values = <String, String>{};
  bool failWrites = false;

  _Storage([Map<String, String>? initial]) {
    if (initial != null) values.addAll(initial);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    if (failWrites) throw StateError('disk full');
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async => values.remove(key);

  @override
  Future<String?> getCurrentUserId() async => 'u_test';
}

class _Platform extends AppLockPlatform {
  @override
  Future<int?> elapsedRealtime() async => null; // no boot clock in tests

  _Platform({this.supported = false, this.enrolled = false});

  bool supported;
  bool enrolled;
  bool authenticateResult = false;
  int authenticateCalls = 0;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      enrolled ? const [BiometricType.fingerprint] : const [];

  @override
  Future<bool> authenticate() async {
    authenticateCalls++;
    return authenticateResult;
  }

  @override
  Future<void> setHideInRecents(bool hide) async {}
}

class _Encryption implements EncryptionService {
  BackupKind? kind;
  RestoreResult result = RestoreResult.restored;
  int checkCalls = 0;

  @override
  Future<BackupKind?> tryGetBackupKind(String userId) async => kind;

  @override
  Future<RestoreResult> checkBackupSecret(String secret) async {
    checkCalls++;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GoRouter _router({String initial = '/'}) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(path: '/', builder: (_, __) => const SettingsScreen()),
    GoRoute(
      path: AppRoutes.appLock,
      builder: (_, __) => const AppLockSettingsScreen(),
    ),
    GoRoute(
      path: AppRoutes.backupPinSetup,
      builder: (_, __) => const Scaffold(body: Text('backup setup')),
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  _Storage? storage,
  _Platform? platform,
  _Encryption? encryption,
  String? entry,
  bool locked = false,
  bool online = true,
  String initial = '/',
}) async {
  final actualStorage =
      storage ?? _Storage(entry == null ? null : {'app_lock': entry});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(actualStorage),
        appLockPlatformProvider.overrideWithValue(platform ?? _Platform()),
        appLockProvider.overrideWith(
          () => AppLockController(initialEntry: entry, initiallyLocked: locked),
        ),
        encryptionServiceProvider.overrideWithValue(
          encryption ?? _Encryption(),
        ),
        isOnlineProvider.overrideWith((ref) => Stream.value(online)),
        themeModeProvider.overrideWith(
          (ref) => Stream.value(AppThemeMode.light),
        ),
        fontFamilyProvider.overrideWith((ref) => Stream.value(AppFont.jakarta)),
        notificationsEnabledProvider.overrideWith((ref) async => true),
        openSystemSettingsProvider.overrideWithValue(() async => true),
      ],
      child: MaterialApp.router(
        theme: warmPopLight(fontFamily: 'PlusJakartaSans'),
        routerConfig: _router(initial: initial),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _tapDigits(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 700)),
  );
  await tester.pump();
}

void main() {
  testWidgets('Settings shows Privacy, App lock Off, and the B2 copy', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Privacy'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('App lock'), 400);
    expect(find.text('Off'), findsOneWidget);
    await tester.tap(find.text('App lock'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "Ask for a PIN every time Kuch Bhi opens, so someone holding your unlocked phone can't read your chats.",
      ),
      findsOneWidget,
    );
    expect(find.text('Turn on app lock'), findsOneWidget);
  });

  testWidgets('B2 shows the recovery note only when backup kind is none', (
    tester,
  ) async {
    final none = _Encryption()..kind = BackupKind.none;
    await _pump(tester, encryption: none, initial: AppRoutes.appLock);
    await tester.pump();
    expect(
      find.textContaining("You don't have a recovery key yet"),
      findsOneWidget,
    );
    expect(find.text('Set up a recovery key'), findsOneWidget);

    final current = _Encryption()..kind = BackupKind.current;
    await _pump(tester, encryption: current, initial: AppRoutes.appLock);
    await tester.pump();
    expect(
      find.textContaining("You don't have a recovery key yet"),
      findsNothing,
    );
    expect(find.text('Set up a recovery key'), findsNothing);
  });

  testWidgets('turn-on rejects weak PIN and mismatched confirmation', (
    tester,
  ) async {
    await _pump(tester, initial: AppRoutes.appLock);
    await tester.tap(find.text('Turn on app lock'));
    await tester.pumpAndSettle();
    await _tapDigits(tester, '123456');
    expect(find.text("Pick a PIN that's harder to guess."), findsOneWidget);
    await _tapDigits(tester, _oldPin);
    await _tapDigits(tester, _newPin);
    expect(find.text('Those PINs don\'t match. Try again.'), findsOneWidget);
  });

  testWidgets(
    'turn-on fingerprint step appears only when available and Not now saves defaults',
    (tester) async {
      final platform = _Platform(supported: true, enrolled: true);
      final storage = _Storage();
      await _pump(
        tester,
        storage: storage,
        platform: platform,
        initial: AppRoutes.appLock,
      );
      await tester.tap(find.text('Turn on app lock'));
      await tester.pumpAndSettle();
      await _tapDigits(tester, _oldPin);
      await _tapDigits(tester, _oldPin);
      expect(find.text('Unlock with fingerprint or face?'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 700)),
      );
      await tester.pump();
      final decoded = AppLockConfig.decode(storage.values['app_lock']);
      expect(decoded!.after, 60);
      expect(decoded.hideNames, true);
      expect(decoded.bio, false);
    },
  );

  testWidgets('turn-on app lock shows its success toast', (tester) async {
    await _pump(tester, initial: AppRoutes.appLock);
    await tester.tap(find.text('Turn on app lock'));
    await tester.pumpAndSettle();
    await _tapDigits(tester, _oldPin);
    await _tapDigits(tester, _oldPin);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('App lock is on.'), findsOneWidget);
  });

  testWidgets('opening an enabled page asks for the PIN before settings', (
    tester,
  ) async {
    final entry = _entry();
    await _pump(tester, entry: entry, initial: AppRoutes.appLock);
    expect(find.text('Enter your PIN'), findsOneWidget);
    await _tapDigits(tester, _oldPin);
    expect(find.text('Change PIN'), findsOneWidget);
    expect(find.text('Lock after'), findsOneWidget);
  });

  testWidgets(
    'Change PIN keeps after, hideNames, and bio and shows its toast',
    (tester) async {
      final entry = _entry(bio: true, after: 300, hideNames: false);
      final storage = _Storage({'app_lock': entry});
      await _pump(
        tester,
        storage: storage,
        entry: entry,
        initial: AppRoutes.appLock,
      );
      await _tapDigits(tester, _oldPin);
      await tester.tap(find.text('Change PIN'));
      await tester.pumpAndSettle();
      await _tapDigits(tester, _newPin);
      await _tapDigits(tester, _newPin);
      await tester.pump();
      expect(find.text('PIN changed.'), findsOneWidget);
      final decoded = AppLockConfig.decode(storage.values['app_lock']);
      expect(decoded!.after, 300);
      expect(decoded.hideNames, false);
      expect(decoded.bio, true);
      expect(decoded.fails, 0);
    },
  );

  testWidgets(
    'Lock after options are mutually exclusive and save the selected value',
    (tester) async {
      final entry = _entry();
      final storage = _Storage({'app_lock': entry});
      await _pump(
        tester,
        storage: storage,
        entry: entry,
        initial: AppRoutes.appLock,
      );
      await _tapDigits(tester, _oldPin);
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('Immediately')),
        isSemantics(isInMutuallyExclusiveGroup: true),
      );
      expect(
        tester.getSemantics(find.text('After 1 minute')),
        isSemantics(isInMutuallyExclusiveGroup: true),
      );
      semantics.dispose();
      await tester.tap(find.text('After 5 minutes'));
      await tester.pump();
      expect(jsonDecode(storage.values['app_lock']!)['after'], 300);
    },
  );

  testWidgets(
    'fingerprint settings row shows available, dimmed, or absent states',
    (tester) async {
      final available = _Platform(supported: true, enrolled: true);
      await _pump(
        tester,
        platform: available,
        entry: _entry(),
        initial: AppRoutes.appLock,
      );
      await _tapDigits(tester, _oldPin);
      await tester.pump();
      expect(find.text('Unlock with fingerprint or face'), findsOneWidget);
      expect(find.descendant(
          of: find.widgetWithText(SettingsTile, 'Unlock with fingerprint or face'),
          matching: find.byType(Switch),
        ), findsOneWidget);

      final none = _Platform(supported: true, enrolled: false);
      await _pump(
        tester,
        platform: none,
        entry: _entry(),
        initial: AppRoutes.appLock,
      );
      await _tapDigits(tester, _oldPin);
      await tester.pump();
      expect(
        find.text("Add a fingerprint or face in your phone's settings first."),
        findsOneWidget,
      );
      expect(find.descendant(
          of: find.widgetWithText(SettingsTile, 'Unlock with fingerprint or face'),
          matching: find.byType(Switch),
        ), findsNothing);

      final unsupported = _Platform(supported: false, enrolled: false);
      await _pump(
        tester,
        platform: unsupported,
        entry: _entry(),
        initial: AppRoutes.appLock,
      );
      await _tapDigits(tester, _oldPin);
      expect(find.text('Unlock with fingerprint or face'), findsNothing);
    },
  );

  testWidgets(
    'turn-on flow omits fingerprint step when biometrics are unavailable',
    (tester) async {
      await _pump(
        tester,
        platform: _Platform(supported: false, enrolled: false),
        initial: AppRoutes.appLock,
      );
      await tester.tap(find.text('Turn on app lock'));
      await tester.pumpAndSettle();
      await _tapDigits(tester, _oldPin);
      await _tapDigits(tester, _oldPin);
      expect(find.text('Unlock with fingerprint or face?'), findsNothing);
    },
  );

  testWidgets(
    'turn off confirms, removes the entry, shows toast, and returns to B2',
    (tester) async {
      final entry = _entry();
      final storage = _Storage({'app_lock': entry});
      await _pump(
        tester,
        storage: storage,
        entry: entry,
        initial: AppRoutes.appLock,
      );
      await _tapDigits(tester, _oldPin);
      await tester.tap(find.text('App lock').first);
      await tester.pump();
      expect(find.text('Turn off app lock?'), findsOneWidget);
      await tester.tap(find.text('Turn off'));
      await tester.pump();
      expect(storage.values['app_lock'], isNull);
      expect(find.text('App lock is off.'), findsOneWidget);
      expect(find.text('Turn on app lock'), findsOneWidget);
    },
  );

  testWidgets(
    'failed setting write shows an error toast and keeps the old value',
    (tester) async {
      final entry = _entry(after: 60);
      final storage = _Storage({'app_lock': entry});
      await _pump(
        tester,
        storage: storage,
        entry: entry,
        initial: AppRoutes.appLock,
      );
      await _tapDigits(tester, _oldPin);
      storage.failWrites = true;
      await tester.tap(find.text('After 5 minutes'));
      await tester.pump();
      expect(find.text("Couldn't save. Try again."), findsOneWidget);
      expect(jsonDecode(storage.values['app_lock']!)['after'], 60);
    },
  );
}
