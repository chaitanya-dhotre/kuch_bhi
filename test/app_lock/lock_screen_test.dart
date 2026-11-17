import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/data/local/secure_storage/secure_storage_service.dart';
import 'package:kuch_bhi/features/app_lock/app_lock_controller.dart';
import 'package:kuch_bhi/features/app_lock/app_lock_platform.dart';
import 'package:kuch_bhi/features/app_lock/lock_overlay.dart';
import 'package:kuch_bhi/features/mascot/capy.dart';
import 'package:kuch_bhi/features/mascot/capy_spots.dart';
import 'package:kuch_bhi/core/widgets/app_button.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/services/encryption_service.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pocketbase/pocketbase.dart';

import '../mascot/capy_test.dart' show FakeSource;

const _oldPin = '246813';
const _newPin = '135790';
const _hash = 'C/gKg+uv7xoYEBp/eC4h3o+8Ljh1ILHNtCJlIRUU/8w=';
final _fixedNow = DateTime(2026, 11, 3, 12);
GlobalKey<NavigatorState>? _routeNavigatorKey;

String _entry({
  bool bio = false,
  int after = 60,
  bool hideNames = true,
  int fails = 0,
  DateTime? waitUntil,
}) => AppLockConfig(
  salt: 'AAAAAAAAAAAAAAAAAAAAAA==',
  hash: _hash,
  iter: 10000,
  bio: bio,
  after: after,
  hideNames: hideNames,
  fails: fails,
  waitUntil: waitUntil,
).encode();

class _Storage extends SecureStorageService {
  _Storage(this.values);
  final Map<String, String> values;

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

  _Platform({this.supported = false, this.enrolled = false});

  bool supported;
  bool enrolled;
  bool authenticateResult = false;
  Object? authenticateError;
  int authenticateCalls = 0;
  int moveTaskCalls = 0;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async =>
      enrolled ? const [BiometricType.fingerprint] : const [];

  @override
  Future<bool> authenticate() async {
    authenticateCalls++;
    if (authenticateError != null) throw authenticateError!;
    return authenticateResult;
  }

  @override
  Future<void> moveTaskToBack() async => moveTaskCalls++;

  @override
  Future<void> setHideInRecents(bool hide) async {}
}

class _Encryption implements EncryptionService {
  RestoreResult result = RestoreResult.restored;
  Object? error;
  int checkCalls = 0;

  @override
  Future<RestoreResult> checkBackupSecret(String secret) async {
    checkCalls++;
    if (error != null) throw error!;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpOverlay(
  WidgetTester tester, {
  required _Storage storage,
  required _Platform platform,
  String? entry,
  bool locked = true,
  _Encryption? encryption,
  bool online = true,
  DateTime Function()? clock,
  Size size = const Size(800, 1000),
  double textScale = 1,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _routeNavigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(storage),
        appLockPlatformProvider.overrideWithValue(platform),
        appLockProvider.overrideWith(
          () => AppLockController(
            initialEntry: entry,
            initiallyLocked: locked,
            clock: clock,
          ),
        ),
        if (encryption != null)
          encryptionServiceProvider.overrideWithValue(encryption),
        isOnlineProvider.overrideWith((ref) => Stream.value(online)),
      ],
      // Mounted like production: in MaterialApp's builder, above the
      // Navigator (no Material or Overlay from a route above the lock).
      child: MaterialApp.router(
        theme: warmPopLight(fontFamily: 'PlusJakartaSans'),
        routerConfig: GoRouter(
          navigatorKey: _routeNavigatorKey,
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) =>
                  const Scaffold(body: Center(child: Text('home route'))),
            ),
          ],
        ),
        builder: (context, child) {
          final media = MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          );
          return MediaQuery(
            data: media,
            child: LockOverlay(child: child!),
          );
        },
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<NavigatorState> _pushChat(WidgetTester tester) async {
  final navigator = _routeNavigatorKey!.currentState!;
  unawaited(
    navigator.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('chat line'))),
      ),
    ),
  );
  await tester.pump();
  return navigator;
}

Future<void> _tapDigits(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.text(digit).last);
    await tester.pump();
  }
  // PBKDF2 runs in compute(), so let the test isolate receive the result.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 700)),
  );
  await tester.pump();
}

Future<void> _openForgot(WidgetTester tester) async {
  final button = tester.widget<AppButton>(
    find.byType(AppButton, skipOffstage: false).last,
  );
  button.onPressed!();
  await tester.pump();
  await tester.pump();
  expect(find.text('Reset your PIN', skipOffstage: false), findsOneWidget);
}

void _expectNoLeakedErrorText(WidgetTester tester) {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final data = text.data ?? '';
    expect(data, isNot(contains('Exception')), reason: data);
    expect(data, isNot(contains(r'$')), reason: data);
  }
}

Finder _semanticsLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

void main() {
  testWidgets('locked route is untouchable and absent from semantics', (
    tester,
  ) async {
    final entry = _entry();
    final storage = _Storage({'app_lock': entry});
    await _pumpOverlay(
      tester,
      storage: storage,
      platform: _Platform(),
      entry: entry,
    );
    await _pushChat(tester);
    final semantics = tester.ensureSemantics();

    expect(find.text('chat line').hitTestable(), findsNothing);
    expect(find.bySemanticsLabel('chat line'), findsNothing);
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) => widget is Offstage && widget.offstage),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('six wrong digits show Wrong PIN and clear the dots', (
    tester,
  ) async {
    final entry = _entry();
    await _pumpOverlay(
      tester,
      storage: _Storage({'app_lock': entry}),
      platform: _Platform(),
      entry: entry,
      clock: () => _fixedNow,
    );
    await _tapDigits(tester, '123456');
    expect(find.text('Wrong PIN.'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(_semanticsLabel('PIN, 0 of 6 digits entered'), findsOneWidget);
    _expectNoLeakedErrorText(tester);
    semantics.dispose();
  });

  testWidgets(
    'fifth wrong PIN shows wait and disables only digit/delete keys',
    (tester) async {
      final entry = _entry();
      await _pumpOverlay(
        tester,
        storage: _Storage({'app_lock': entry}),
        platform: _Platform(),
        entry: entry,
        clock: () => _fixedNow,
      );
      for (var i = 0; i < 5; i++) {
        await _tapDigits(tester, '123456');
      }
      expect(find.text('Too many tries. Try again in 0:30.'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(
        tester.getSemantics(_semanticsLabel('1')),
        isSemantics(isEnabled: false),
      );
      expect(
        tester.getSemantics(_semanticsLabel('Delete digit')),
        isSemantics(isEnabled: false),
      );
      final forgot = tester.widget<ButtonStyleButton>(
        find
            .ancestor(
              of: find.text('Forgot PIN?'),
              matching: find.bySubtype<ButtonStyleButton>(),
            )
            .first,
      );
      expect(forgot.onPressed, isNotNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'right PIN removes the overlay without changing the pushed route',
    (tester) async {
      final entry = _entry();
      await _pumpOverlay(
        tester,
        storage: _Storage({'app_lock': entry}),
        platform: _Platform(),
        entry: entry,
      );
      await _pushChat(tester);
      await _tapDigits(tester, _oldPin);
      expect(find.text('Enter your PIN'), findsNothing);
      expect(find.text('chat line').hitTestable(), findsOneWidget);
    },
  );

  testWidgets(
    'fingerprint key is absent unless bio and biometrics are available',
    (tester) async {
      final noBio = _entry(bio: false);
      await _pumpOverlay(
        tester,
        storage: _Storage({'app_lock': noBio}),
        platform: _Platform(supported: true, enrolled: true),
        entry: noBio,
      );
      final semantics = tester.ensureSemantics();
      expect(_semanticsLabel('Unlock with fingerprint or face'), findsNothing);
      expect(_semanticsLabel('1'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'bio enabled without current biometric availability has no key or prompt',
    (tester) async {
      final entry = _entry(bio: true);
      final platform = _Platform(supported: false, enrolled: false);
      await _pumpOverlay(
        tester,
        storage: _Storage({'app_lock': entry}),
        platform: platform,
        entry: entry,
      );
      final semantics = tester.ensureSemantics();
      expect(_semanticsLabel('Unlock with fingerprint or face'), findsNothing);
      expect(platform.authenticateCalls, 0);
      semantics.dispose();
    },
  );

  testWidgets(
    'biometric prompt opens once automatically and again only on tap',
    (tester) async {
      final entry = _entry(bio: true);
      final platform = _Platform(supported: true, enrolled: true);
      await _pumpOverlay(
        tester,
        storage: _Storage({'app_lock': entry}),
        platform: platform,
        entry: entry,
      );
      expect(platform.authenticateCalls, 1);
      final semantics = tester.ensureSemantics();
      await tester.tap(_semanticsLabel('Unlock with fingerprint or face'));
      await tester.pump();
      expect(platform.authenticateCalls, 2);
      semantics.dispose();
    },
  );

  testWidgets('LockedOut biometric error uses the C4 copy', (tester) async {
    final entry = _entry(bio: true);
    final platform = _Platform(supported: true, enrolled: true)
      ..authenticateError = PlatformException(code: 'LockedOut');
    await _pumpOverlay(
      tester,
      storage: _Storage({'app_lock': entry}),
      platform: platform,
      entry: entry,
    );
    expect(
      find.text('Too many tries with fingerprint or face. Use your PIN.'),
      findsOneWidget,
    );
    _expectNoLeakedErrorText(tester);
  });

  testWidgets('PermanentlyLockedOut biometric error uses the C4 copy', (
    tester,
  ) async {
    final entry = _entry(bio: true);
    final platform = _Platform(supported: true, enrolled: true)
      ..authenticateError = PlatformException(code: 'PermanentlyLockedOut');
    await _pumpOverlay(
      tester,
      storage: _Storage({'app_lock': entry}),
      platform: platform,
      entry: entry,
    );
    expect(
      find.text(
        'Fingerprint or face is off until you unlock your phone. Use your PIN.',
      ),
      findsOneWidget,
    );
    _expectNoLeakedErrorText(tester);
  });

  testWidgets('locked back moves the task back and never pops the route', (
    tester,
  ) async {
    final entry = _entry();
    final platform = _Platform();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pumpOverlay(
      tester,
      storage: _Storage({'app_lock': entry}),
      platform: platform,
      entry: entry,
    );
    await _pushChat(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(platform.moveTaskCalls, 1);
    expect(find.text('chat line').hitTestable(), findsNothing);

    await _tapDigits(tester, _oldPin);
    expect(find.text('chat line').hitTestable(), findsOneWidget);
    expect(
      calls.where(
        (call) =>
            call.method == 'SystemNavigator.setFrameworkHandlesBack' &&
            call.arguments == false,
      ),
      isNotEmpty,
    );
    expect(
      calls.where(
        (call) =>
            call.method == 'SystemNavigator.setFrameworkHandlesBack' &&
            call.arguments == true,
      ),
      isNotEmpty,
    );
  });

  testWidgets('Forgot PIN rejects malformed input without a service call', (
    tester,
  ) async {
    final entry = _entry();
    final encryption = _Encryption();
    await _pumpOverlay(
      tester,
      storage: _Storage({'app_lock': entry}),
      platform: _Platform(),
      entry: entry,
      encryption: encryption,
    );
    await _openForgot(tester);
    await tester.enterText(find.byType(TextField), 'not-a-key');
    await tester.tap(find.text('Reset PIN'));
    await tester.pump();
    expect(
      find.text(
        'A recovery key has 25 letters and numbers. Check that you have all of it.',
      ),
      findsOneWidget,
    );
    expect(encryption.checkCalls, 0);
  });

  testWidgets(
    'Forgot PIN restored flow saves a new PIN and preserves settings',
    (tester) async {
      final entry = _entry(after: 300, hideNames: false);
      final storage = _Storage({'app_lock': entry});
      final encryption = _Encryption();
      await _pumpOverlay(
        tester,
        storage: storage,
        platform: _Platform(),
        entry: entry,
        encryption: encryption,
        clock: () => _fixedNow,
      );
      await _openForgot(tester);
      await tester.enterText(
        find.byType(TextField),
        '1234567890123456789012345',
      );
      await tester.tap(find.text('Reset PIN'));
      await tester.pump();
      expect(encryption.checkCalls, 1);
      expect(find.text('Create a PIN'), findsOneWidget);

      await _tapDigits(tester, _newPin);
      expect(find.text('Enter it again'), findsOneWidget);
      await _tapDigits(tester, _newPin);
      // Read-back proves the reset kept non-PIN settings and reset the ladder.
      final decoded = AppLockConfig.decode(storage.values['app_lock']);
      expect(decoded!.after, 300);
      expect(decoded.hideNames, false);
      expect(decoded.fails, 0);
      expect(decoded.waitUntil, isNull);
      expect(storage.values['app_lock'], isNot(contains(_oldPin)));
      expect(storage.values['app_lock'], isNot(contains(_newPin)));
      final lock = ProviderScope.containerOf(
        tester.element(find.byType(LockOverlay)),
      ).read(appLockProvider.notifier);
      final away = DateTime(2026, 11, 3, 12);
      lock.onHidden(away);
      await lock.onResumed(away.add(const Duration(minutes: 5)));
      expect(lock.state.locked, true);
      final oldPin = await tester.runAsync(() => lock.unlockWithPin(_oldPin));
      final newPin = await tester.runAsync(() => lock.unlockWithPin(_newPin));
      expect(oldPin, false);
      expect(newPin, true);
      _expectNoLeakedErrorText(tester);
    },
  );

  testWidgets('Forgot PIN restored flow shows the New PIN set toast', (
    tester,
  ) async {
    final entry = _entry();
    await _pumpOverlay(
      tester,
      storage: _Storage({'app_lock': entry}),
      platform: _Platform(),
      entry: entry,
      encryption: _Encryption(),
      clock: () => _fixedNow,
    );
    await _openForgot(tester);
    await tester.enterText(find.byType(TextField), '1234567890123456789012345');
    await tester.tap(find.text('Reset PIN'));
    await tester.pump();
    await _tapDigits(tester, _newPin);
    await _tapDigits(tester, _newPin);
    // Reset then unlock: two PBKDF2 runs in compute().
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 700)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('New PIN set.'), findsOneWidget);
    expect(find.text('home route'), findsOneWidget);
  });

  testWidgets('Forgot PIN wrong secret increments fails and shows safe copy', (
    tester,
  ) async {
    final entry = _entry();
    final storage = _Storage({'app_lock': entry});
    final encryption = _Encryption()..result = RestoreResult.wrongSecret;
    await _pumpOverlay(
      tester,
      storage: storage,
      platform: _Platform(),
      entry: entry,
      encryption: encryption,
    );
    await _openForgot(tester);
    await tester.enterText(find.byType(TextField), '1234567890123456789012345');
    await tester.tap(find.text('Reset PIN'));
    await tester.pump();
    expect(
      find.text(
        "That doesn't match your backup. Check for typos and try again.",
      ),
      findsOneWidget,
    );
    expect(AppLockConfig.decode(storage.values['app_lock'])!.fails, 1);
    _expectNoLeakedErrorText(tester);
  });

  testWidgets('Forgot PIN shows no-backup, unsupported, and network copies', (
    tester,
  ) async {
    final entry = _entry();
    final encryption = _Encryption()..result = RestoreResult.noBackup;
    await _pumpOverlay(
      tester,
      storage: _Storage({'app_lock': entry}),
      platform: _Platform(),
      entry: entry,
      encryption: encryption,
    );
    await _openForgot(tester);
    final key = '1234567890123456789012345';
    Future<void> submit() async {
      await tester.enterText(find.byType(TextField), key);
      await tester.tap(find.text('Reset PIN'));
      await tester.pump();
    }

    await submit();
    expect(
      find.textContaining('This account has no recovery key'),
      findsOneWidget,
    );
    encryption.result = RestoreResult.unsupported;
    await submit();
    expect(
      find.textContaining('This backup was made by a newer version'),
      findsOneWidget,
    );
    encryption.error = ClientException(statusCode: 0);
    await submit();
    expect(
      find.text("Can't reach the server. Check your connection and try again."),
      findsOneWidget,
    );
    _expectNoLeakedErrorText(tester);
  });

  testWidgets('Forgot PIN while waiting does not call the service', (
    tester,
  ) async {
    final entry = _entry(
      fails: 5,
      waitUntil: _fixedNow.add(const Duration(seconds: 30)),
    );
    final encryption = _Encryption();
    await _pumpOverlay(
      tester,
      storage: _Storage({'app_lock': entry}),
      platform: _Platform(),
      entry: entry,
      encryption: encryption,
      clock: () => _fixedNow,
    );
    await _openForgot(tester);
    await tester.enterText(find.byType(TextField), '1234567890123456789012345');
    await tester.tap(find.text('Reset PIN'));
    await tester.pump();
    expect(encryption.checkCalls, 0);
    expect(find.text('Too many tries. Try again in 0:30.'), findsOneWidget);
  });

  testWidgets(
    'Forgot PIN offline disables Reset PIN and explains availability',
    (tester) async {
      final entry = _entry();
      await _pumpOverlay(
        tester,
        storage: _Storage({'app_lock': entry}),
        platform: _Platform(),
        entry: entry,
        online: false,
      );
      await _openForgot(tester);
      await tester.pump();
      expect(find.text('Available online'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find
            .ancestor(
              of: find.text('Reset PIN'),
              matching: find.bySubtype<ButtonStyleButton>(),
            )
            .first,
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'lock semantics expose dots, named keys, live message, and header',
    (tester) async {
      final entry = _entry();
      await _pumpOverlay(
        tester,
        storage: _Storage({'app_lock': entry}),
        platform: _Platform(),
        entry: entry,
      );
      final semantics = tester.ensureSemantics();
      expect(_semanticsLabel('PIN, 0 of 6 digits entered'), findsOneWidget);
      expect(_semanticsLabel('1'), findsOneWidget);
      expect(_semanticsLabel('Delete digit'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Enter your PIN')),
        isSemantics(isHeader: true),
      );
      await _tapDigits(tester, '123456');
      expect(
        tester.getSemantics(find.text('Wrong PIN.')),
        isSemantics(isLiveRegion: true),
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'lock screen has no overflow at large portrait and landscape text',
    (tester) async {
      final entry = _entry();
      await _pumpOverlay(
        tester,
        storage: _Storage({'app_lock': entry}),
        platform: _Platform(),
        entry: entry,
        size: const Size(360, 640),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      await _openForgot(tester);
      expect(tester.takeException(), isNull);

      final landscapeEntry = _entry();
      await _pumpOverlay(
        tester,
        storage: _Storage({'app_lock': landscapeEntry}),
        platform: _Platform(),
        entry: landscapeEntry,
        size: const Size(640, 360),
      );
      expect(tester.takeException(), isNull);
      await _openForgot(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reduced motion leaves no running shake animation after wrong PIN',
    (tester) async {
      final entry = _entry();
      await _pumpOverlay(
        tester,
        storage: _Storage({'app_lock': entry}),
        platform: _Platform(),
        entry: entry,
        disableAnimations: true,
      );
      await _tapDigits(tester, '123456');
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, false);
    },
  );

  group('K2 capybara (mascot spec §G1)', () {
    late FakeSource capys;
    setUp(() => CapyLoader.debugSource = capys = FakeSource());
    tearDown(() => CapyLoader.debugSource = null);

    Future<void> pump(WidgetTester tester) async {
      final entry = _entry();
      await _pumpOverlay(
        tester,
        storage: _Storage({'app_lock': entry}),
        platform: _Platform(),
        entry: entry,
        clock: () => _fixedNow,
      );
    }

    testWidgets('guards the key, focused; its face follows the dots', (
      tester,
    ) async {
      await pump(tester);
      final rig = capys.rigs.single;
      expect(capys.views.single, CapyView.front);
      expect(rig.pose, CapyPose.guard);
      expect(rig.mood, CapyMood.focused);
      expect(rig.bools['still'], isFalse);
      expect(rig.lookX, 0, reason: 'no digits: looks at you');
      await tester.tap(find.text('1').last);
      await tester.pump();
      expect(rig.lookX, pinLookX(1));
      await tester.tap(find.text('2').last);
      await tester.pump();
      expect(rig.lookX, pinLookX(2));
      await tester.tap(_semanticsLabel('Delete digit'));
      await tester.pump();
      expect(rig.lookX, pinLookX(1), reason: 'delete moves it back');
    });

    testWidgets('wrong PIN: worried for 1.2 s, then focused again', (
      tester,
    ) async {
      await pump(tester);
      final rig = capys.rigs.single;
      await _tapDigits(tester, '123456');
      expect(find.text('Wrong PIN.'), findsOneWidget);
      expect(rig.mood, CapyMood.worried);
      expect(rig.lookX, 0, reason: 'the dots cleared');
      await tester.pump(const Duration(milliseconds: 1100));
      expect(rig.mood, CapyMood.worried);
      await tester.pump(const Duration(milliseconds: 150));
      expect(rig.mood, CapyMood.focused);
    });

    testWidgets('lockout countdown: worried the whole time', (tester) async {
      await pump(tester);
      final rig = capys.rigs.single;
      for (var i = 0; i < 5; i++) {
        await _tapDigits(tester, '123456');
      }
      expect(find.text('Too many tries. Try again in 0:30.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(rig.mood, CapyMood.worried);
    });
  });
}
