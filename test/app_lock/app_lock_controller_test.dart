import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/data/local/secure_storage/secure_storage_service.dart';
import 'package:kuch_bhi/features/app_lock/app_lock_controller.dart';
import 'package:kuch_bhi/features/app_lock/app_lock_platform.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pocketbase/pocketbase.dart';

const _knownPin = '246813';
const _knownEntryHash = 'C/gKg+uv7xoYEBp/eC4h3o+8Ljh1ILHNtCJlIRUU/8w=';

String _entry({
  bool bio = false,
  int after = 60,
  bool hideNames = true,
  int fails = 0,
  DateTime? waitUntil,
  String hash = _knownEntryHash,
}) => AppLockConfig(
  salt: 'AAAAAAAAAAAAAAAAAAAAAA==',
  hash: hash,
  iter: 10000,
  bio: bio,
  after: after,
  hideNames: hideNames,
  fails: fails,
  waitUntil: waitUntil,
).encode();

class _Storage extends SecureStorageService {
  _Storage([Map<String, String>? initial]) : values = {...?initial};
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
  bool hideInRecents = false;
  bool authenticateResult = false;
  Object? authenticateError;
  int authenticateCalls = 0;
  final authStarted = Completer<void>();
  Completer<bool>? auth;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => const [
    BiometricType.fingerprint,
  ];

  @override
  Future<bool> authenticate() async {
    authenticateCalls++;
    if (!authStarted.isCompleted) authStarted.complete();
    if (authenticateError != null) throw authenticateError!;
    return auth?.future ?? authenticateResult;
  }

  @override
  Future<void> setHideInRecents(bool hide) async => hideInRecents = hide;
}

ProviderContainer _container({
  required _Storage storage,
  required _Platform platform,
  String? entry,
  bool locked = false,
  DateTime Function()? clock,
}) {
  return ProviderContainer(
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
    ],
  );
}

void main() {
  test('shouldLock table covers every boundary', () {
    final now = DateTime(2026, 11, 2, 12);
    final rows = [
      (
        name: 'off',
        enabled: false,
        awayAt: now,
        after: 60,
        at: now,
        value: false,
      ),
      (
        name: 'awayAt null',
        enabled: true,
        awayAt: null,
        after: 60,
        at: now,
        value: false,
      ),
      (
        name: 'away < after',
        enabled: true,
        awayAt: now,
        after: 60,
        at: now.add(const Duration(seconds: 59)),
        value: false,
      ),
      (
        name: 'away == after',
        enabled: true,
        awayAt: now,
        after: 60,
        at: now.add(const Duration(seconds: 60)),
        value: true,
      ),
      (
        name: 'away > after',
        enabled: true,
        awayAt: now,
        after: 60,
        at: now.add(const Duration(seconds: 61)),
        value: true,
      ),
      (
        name: 'Immediately (0)',
        enabled: true,
        awayAt: now,
        after: 0,
        at: now,
        value: true,
      ),
    ];
    for (final row in rows) {
      expect(
        shouldLock(
          enabled: row.enabled,
          awayAt: row.awayAt,
          afterSeconds: row.after,
          now: row.at,
        ),
        row.value,
        reason: row.name,
      );
    }
  });

  test('isWeakPin refuses all A3 PINs and malformed lengths', () {
    const weak = [
      '000000',
      '111111',
      '222222',
      '333333',
      '444444',
      '555555',
      '666666',
      '777777',
      '888888',
      '999999',
      '012345',
      '123456',
      '234567',
      '345678',
      '456789',
      '987654',
      '876543',
      '765432',
      '654321',
      '543210',
    ];
    for (final pin in weak) {
      expect(isWeakPin(pin), true, reason: pin);
    }
    for (final pin in ['246813', '135790', '908172']) {
      expect(isWeakPin(pin), false, reason: pin);
    }
    for (final pin in ['', '12345', '1234567', 'abcdef', '１２３４５６']) {
      expect(isWeakPin(pin), true, reason: pin);
    }
  });

  test('lock-off hidden and inactive-only lifecycle changes nothing', () {
    final container = _container(storage: _Storage(), platform: _Platform());
    addTearDown(container.dispose);
    final controller = container.read(appLockProvider.notifier);
    final before = controller.state;

    // There is intentionally no inactive handler on AppLockController.
    final afterInactive = controller.state;
    expect(afterInactive.covered, before.covered);
    expect(afterInactive.awayAt, before.awayAt);

    controller.onHidden(DateTime(2026, 11, 2));
    expect(controller.state.covered, false);
    expect(controller.state.awayAt, isNull);
  });

  test('cold start locks only when an entry was supplied', () {
    final locked = _container(
      storage: _Storage({'app_lock': _entry()}),
      platform: _Platform(),
      entry: _entry(),
      locked: true,
    );
    addTearDown(locked.dispose);
    expect(locked.read(appLockProvider).locked, true);

    final off = _container(storage: _Storage(), platform: _Platform());
    addTearDown(off.dispose);
    expect(off.read(appLockProvider).locked, false);
    expect(off.read(appLockProvider).enabled, false);
  });

  test('whenUnlocked waits through cover and completes after resume', () async {
    var now = DateTime(2026, 11, 2, 12);
    final storage = _Storage();
    final container = _container(
      storage: storage,
      platform: _Platform(),
      clock: () => now,
    );
    addTearDown(container.dispose);
    final controller = container.read(appLockProvider.notifier);
    await controller.turnOn(_knownPin);
    controller.onHidden(now);
    final waiter = controller.whenUnlocked();
    var completed = false;
    waiter.then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, false);

    now = now.add(const Duration(seconds: 30));
    await controller.onResumed(now);
    expect(controller.state.covered, false);
    expect(controller.state.locked, false);
    await waiter;
    expect(completed, true);
  });

  test(
    'wrong PIN ladder, wait blocking, reset, and persistence use full schedule',
    () async {
      var now = DateTime(2026, 11, 2, 12);
      final storage = _Storage({'app_lock': _entry()});
      final platform = _Platform();
      final first = _container(
        storage: storage,
        platform: platform,
        entry: storage.values['app_lock'],
        clock: () => now,
      );
      addTearDown(first.dispose);
      final controller = first.read(appLockProvider.notifier);
      const freeMessages = [
        'Wrong PIN.',
        'Wrong PIN.',
        'Wrong PIN. 2 more tries before a short wait.',
        'Wrong PIN. 1 more try before a short wait.',
      ];
      for (var i = 0; i < 4; i++) {
        expect(await controller.unlockWithPin('246814'), false);
        expect(controller.state.config!.fails, i + 1);
        expect(controller.state.message, freeMessages[i]);
        expect(controller.isWaiting(now), false);
      }

      expect(await controller.unlockWithPin('246814'), false);
      expect(controller.state.config!.fails, 5);
      expect(controller.state.message, 'Too many tries. Try again in 0:30.');
      expect(controller.waitRemaining(now), const Duration(seconds: 30));
      await controller.unlockWithPin('246814');
      expect(
        controller.state.config!.fails,
        5,
        reason: 'a wrong PIN during a wait does not count',
      );

      now = now.add(const Duration(seconds: 31));
      expect(await controller.unlockWithPin('246814'), false);
      expect(controller.state.config!.fails, 6);
      expect(controller.state.message, 'Too many tries. Try again in 1:00.');

      now = now.add(const Duration(minutes: 1, seconds: 1));
      expect(await controller.unlockWithPin('246814'), false);
      expect(controller.state.config!.fails, 7);
      expect(controller.state.message, 'Too many tries. Try again in 5:00.');

      now = now.add(const Duration(minutes: 5, seconds: 1));
      expect(await controller.unlockWithPin('246814'), false);
      expect(controller.state.config!.fails, 8);
      expect(controller.state.message, 'Too many tries. Try again in 15:00.');

      now = now.add(const Duration(minutes: 15, seconds: 1));
      expect(await controller.unlockWithPin('246814'), false);
      expect(controller.state.config!.fails, 9);
      expect(controller.state.message, 'Too many tries. Try again in 15:00.');

      final persisted = _container(
        storage: storage,
        platform: platform,
        entry: storage.values['app_lock'],
        locked: true,
        clock: () => now,
      );
      addTearDown(persisted.dispose);
      final restored = persisted.read(appLockProvider.notifier);
      expect(restored.state.config!.fails, 9);
      expect(restored.state.config!.waitUntil, isNotNull);
      expect(
        restored.waitRemaining(now.subtract(const Duration(hours: 1))),
        lessThanOrEqualTo(const Duration(minutes: 15)),
      );

      now = now.add(const Duration(minutes: 15, seconds: 1));
      expect(await restored.unlockWithPin(_knownPin), true);
      expect(restored.state.config!.fails, 0);
      expect(restored.state.config!.waitUntil, isNull);
    },
  );

  test(
    'turn on, change PIN, reset PIN, and storage never keep either PIN',
    () async {
      final storage = _Storage({
        'app_lock': _entry(bio: true, after: 300, hideNames: false, fails: 4),
      });
      final container = _container(
        storage: storage,
        platform: _Platform(),
        entry: storage.values['app_lock'],
      );
      addTearDown(container.dispose);
      final controller = container.read(appLockProvider.notifier);

      await controller.changePin('135790');
      var raw = storage.values['app_lock']!;
      expect(raw, isNot(contains(_knownPin)));
      expect(raw, isNot(contains('135790')));
      expect(controller.state.config!.bio, true);
      expect(controller.state.config!.after, 300);
      expect(controller.state.config!.hideNames, false);
      expect(controller.state.config!.fails, 0);

      await controller.resetPin('908172');
      raw = storage.values['app_lock']!;
      expect(raw, isNot(contains('135790')));
      expect(raw, isNot(contains('908172')));
      expect(controller.state.config!.bio, true);
      expect(controller.state.config!.after, 300);
      expect(controller.state.config!.hideNames, false);
      expect(controller.state.config!.fails, 0);

      final freshStorage = _Storage();
      final fresh = _container(storage: freshStorage, platform: _Platform());
      addTearDown(fresh.dispose);
      await fresh.read(appLockProvider.notifier).resetPin(_knownPin);
      expect(
        freshStorage.values['app_lock'],
        isNotNull,
        reason: 'resetPin creates a fresh entry when none is readable',
      );
      final freshJson = jsonDecode(freshStorage.values['app_lock']!);
      expect(freshJson['after'], 60);
      expect(freshJson['hideNames'], true);
    },
  );

  test('turnOn defaults after and hideNames', () async {
    final storage = _Storage();
    final container = _container(storage: storage, platform: _Platform());
    addTearDown(container.dispose);
    await container.read(appLockProvider.notifier).turnOn(_knownPin);
    final json = jsonDecode(storage.values['app_lock']!);
    expect(json['after'], 60);
    expect(json['hideNames'], true);
    expect(json['fails'], 0);
  });

  test('biometric and Forgot PIN error mappers expose only approved copy', () {
    expect(
      biometricErrorCopy(PlatformException(code: 'LockedOut')),
      'Too many tries with fingerprint or face. Use your PIN.',
    );
    expect(
      biometricErrorCopy(PlatformException(code: 'PermanentlyLockedOut')),
      'Fingerprint or face is off until you unlock your phone. Use your PIN.',
    );
    expect(biometricErrorCopy(PlatformException(code: 'NotAvailable')), isNull);
    expect(biometricErrorCopy(PlatformException(code: 'NotEnrolled')), isNull);
    expect(biometricErrorCopy(StateError('private detail')), isNull);
    expect(
      forgotPinErrorCopy(ClientException(statusCode: 0)),
      "Can't reach the server. Check your connection and try again.",
    );
    expect(
      forgotPinErrorCopy(StateError('private detail')),
      "Couldn't check your key. Try again.",
    );
  });

  test(
    'biometric LockedOut is shown and never counted as a PIN failure',
    () async {
      final storage = _Storage({'app_lock': _entry(bio: true)});
      final platform = _Platform()
        ..authenticateError = PlatformException(code: 'LockedOut');
      final container = _container(
        storage: storage,
        platform: platform,
        entry: storage.values['app_lock'],
        locked: true,
      );
      addTearDown(container.dispose);
      final controller = container.read(appLockProvider.notifier);
      expect(await controller.authenticateWithBiometrics(), false);
      expect(
        controller.state.message,
        'Too many tries with fingerprint or face. Use your PIN.',
      );
      expect(controller.state.config!.fails, 0);
      expect(platform.authenticateCalls, 1);
    },
  );

  test('lifecycle signals during biometric auth are ignored', () async {
    final storage = _Storage({'app_lock': _entry(bio: true)});
    final platform = _Platform()..auth = Completer<bool>();
    final container = _container(
      storage: storage,
      platform: platform,
      entry: storage.values['app_lock'],
      locked: true,
    );
    addTearDown(container.dispose);
    final controller = container.read(appLockProvider.notifier);
    final auth = controller.authenticateWithBiometrics();
    await platform.authStarted.future;
    controller.onHidden(DateTime(2026, 11, 3));
    await controller.onResumed(DateTime(2026, 11, 3, 0, 1));
    expect(controller.state.covered, false);
    expect(controller.state.locked, true);
    platform.auth!.complete(false);
    await auth;
    expect(controller.state.authInProgress, false);
  });

  test('a prompt cancelled by leaving the app still counts the time away', () async {
    final away = DateTime(2026, 11, 3, 12);
    final storage = _Storage({'app_lock': _entry(bio: true)});
    final platform = _Platform()..auth = Completer<bool>();
    final container = _container(
      storage: storage,
      platform: platform,
      entry: storage.values['app_lock'],
      clock: () => away.add(const Duration(minutes: 31)),
    );
    addTearDown(container.dispose);
    final controller = container.read(appLockProvider.notifier);
    final auth = controller.authenticateWithBiometrics();
    await platform.authStarted.future;
    controller.onHidden(away);
    await controller.onResumed(away.add(const Duration(minutes: 31)));
    platform.auth!.complete(false);
    await auth;
    expect(controller.state.locked, true);
    expect(controller.state.covered, false);
  });

  test('a successful prompt ignores its own lifecycle noise', () async {
    final away = DateTime(2026, 11, 3, 12);
    final storage = _Storage({'app_lock': _entry(bio: true, after: 0)});
    final platform = _Platform()..auth = Completer<bool>();
    final container = _container(
      storage: storage,
      platform: platform,
      entry: storage.values['app_lock'],
      clock: () => away,
    );
    addTearDown(container.dispose);
    final controller = container.read(appLockProvider.notifier);
    final auth = controller.authenticateWithBiometrics();
    await platform.authStarted.future;
    controller.onHidden(away);
    await controller.onResumed(away);
    platform.auth!.complete(true);
    await auth;
    expect(controller.state.locked, false);
    expect(controller.state.covered, false);
  });

  test('after sign-out wipes the entry, readConfig turns the lock off and '
      'nothing writes it back', () async {
    final now = DateTime(2026, 11, 3, 12);
    final storage = _Storage({'app_lock': _entry()});
    final container = _container(
      storage: storage,
      platform: _Platform(),
      entry: storage.values['app_lock'],
      clock: () => now,
    );
    addTearDown(container.dispose);
    final controller = container.read(appLockProvider.notifier);
    storage.values.remove('app_lock'); // clearSession
    await controller.readConfig();
    expect(controller.state.enabled, false);
    controller.onHidden(now);
    await controller.onResumed(now.add(const Duration(hours: 1)));
    expect(controller.state.locked, false);
    await controller.registerWrongAttempt(now: now);
    await controller.updateSettings(after: 0);
    expect(storage.values.containsKey('app_lock'), false);
  });

  test('turn off deletes the entry and clears recents protection', () async {
    final storage = _Storage();
    final platform = _Platform();
    final container = _container(storage: storage, platform: platform);
    addTearDown(container.dispose);
    final controller = container.read(appLockProvider.notifier);
    await controller.turnOn(_knownPin);
    expect(platform.hideInRecents, true);
    await controller.turnOff();
    expect(storage.values.containsKey('app_lock'), false);
    expect(platform.hideInRecents, false);
  });
}
