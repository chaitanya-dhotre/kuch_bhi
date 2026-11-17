import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

import '../../data/local/secure_storage/secure_storage_service.dart';
import '../../services/encryption_service.dart' show isUnreachableError;
import 'app_lock_platform.dart';

const _storageKey = 'app_lock';
const _iterations = 10000;
const _hashBits = 256;

bool shouldLock({
  required bool enabled,
  DateTime? awayAt,
  required int afterSeconds,
  required DateTime now,
  int? elapsedAwayMs,
}) {
  if (!enabled || awayAt == null) return false;
  if (afterSeconds == 0) return true;
  // F15: time since boot can't be moved by the user; negative = a reboot.
  if (elapsedAwayMs != null &&
      (elapsedAwayMs < 0 || elapsedAwayMs >= afterSeconds * 1000)) {
    return true;
  }
  return now.difference(awayAt) >= Duration(seconds: afterSeconds);
}

bool isWeakPin(String pin) {
  if (!RegExp(r'^\d{6}$').hasMatch(pin)) return true;
  final digits = pin.codeUnits.map((unit) => unit - 48).toList();
  final same = digits.every((digit) => digit == digits.first);
  if (same) return true;
  final ascending = List.generate(
    5,
    (i) => digits[i + 1] - digits[i],
  ).every((difference) => difference == 1);
  final descending = List.generate(
    5,
    (i) => digits[i + 1] - digits[i],
  ).every((difference) => difference == -1);
  return ascending || descending;
}

/// C4: the only prompt errors that show; everything else (cancel, not
/// available, not enrolled) shows nothing and the PIN works.
String? biometricErrorCopy(Object error) => switch (error) {
  PlatformException(code: auth_error.lockedOut) =>
    'Too many tries with fingerprint or face. Use your PIN.',
  PlatformException(code: auth_error.permanentlyLockedOut) =>
    'Fingerprint or face is off until you unlock your phone. Use your PIN.',
  _ => null,
};

/// G3: a Forgot PIN check that threw.
String forgotPinErrorCopy(Object error) => isUnreachableError(error)
    ? "Can't reach the server. Check your connection and try again."
    : "Couldn't check your key. Try again.";

class AppLockConfig {
  const AppLockConfig({
    required this.salt,
    required this.hash,
    required this.iter,
    required this.bio,
    required this.after,
    required this.hideNames,
    required this.fails,
    required this.waitUntil,
    this.waitStart,
    this.version = 1,
  });

  final int version;
  final String salt;
  final String hash;
  final int iter;
  final bool bio;
  final int after;
  final bool hideNames;
  final int fails;
  final DateTime? waitUntil;

  /// F15: Android time since boot (ms) when the current wait began. The
  /// wait is measured on this clock; [waitUntil] is only for display.
  final int? waitStart;

  Map<String, dynamic> toJson() => {
    'v': version,
    'salt': salt,
    'hash': hash,
    'iter': iter,
    'bio': bio,
    'after': after,
    'hideNames': hideNames,
    'fails': fails,
    'waitUntil': waitUntil?.millisecondsSinceEpoch,
    if (waitStart != null) 'waitStart': waitStart,
  };

  String encode() => jsonEncode(toJson());

  AppLockConfig copyWith({
    String? salt,
    String? hash,
    int? iter,
    bool? bio,
    int? after,
    bool? hideNames,
    int? fails,
    Object? waitUntil = _keepValue,
    Object? waitStart = _keepValue,
  }) {
    return AppLockConfig(
      version: version,
      salt: salt ?? this.salt,
      hash: hash ?? this.hash,
      iter: iter ?? this.iter,
      bio: bio ?? this.bio,
      after: after ?? this.after,
      hideNames: hideNames ?? this.hideNames,
      fails: fails ?? this.fails,
      waitUntil: identical(waitUntil, _keepValue)
          ? this.waitUntil
          : waitUntil as DateTime?,
      waitStart: identical(waitStart, _keepValue)
          ? this.waitStart
          : waitStart as int?,
    );
  }

  static AppLockConfig? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['v'] != 1) return null;
      final salt = decoded['salt'];
      final hash = decoded['hash'];
      final iter = decoded['iter'];
      final after = decoded['after'];
      final fails = decoded['fails'];
      final wait = decoded['waitUntil'];
      if (salt is! String ||
          hash is! String ||
          iter is! num ||
          after is! num ||
          fails is! num ||
          decoded['bio'] is! bool ||
          decoded['hideNames'] is! bool) {
        return null;
      }
      return AppLockConfig(
        salt: salt,
        hash: hash,
        iter: iter.toInt(),
        bio: decoded['bio'] as bool,
        after: after.toInt(),
        hideNames: decoded['hideNames'] as bool,
        fails: fails.toInt(),
        waitUntil: wait is num
            ? DateTime.fromMillisecondsSinceEpoch(wait.toInt())
            : null,
        waitStart: decoded['waitStart'] is num
            ? (decoded['waitStart'] as num).toInt()
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

const _keepValue = Object();

class AppLockState {
  const AppLockState({
    required this.enabled,
    required this.locked,
    required this.covered,
    required this.authInProgress,
    required this.awayAt,
    required this.config,
    this.message,
  });

  final bool enabled;
  final bool locked;
  final bool covered;
  final bool authInProgress;
  final DateTime? awayAt;
  final AppLockConfig? config;
  final String? message;

  bool get gated => locked || covered;

  AppLockState copyWith({
    bool? enabled,
    bool? locked,
    bool? covered,
    bool? authInProgress,
    Object? awayAt = _keepValue,
    Object? config = _keepValue,
    Object? message = _keepValue,
  }) {
    return AppLockState(
      enabled: enabled ?? this.enabled,
      locked: locked ?? this.locked,
      covered: covered ?? this.covered,
      authInProgress: authInProgress ?? this.authInProgress,
      awayAt: identical(awayAt, _keepValue) ? this.awayAt : awayAt as DateTime?,
      config: identical(config, _keepValue)
          ? this.config
          : config as AppLockConfig?,
      message: identical(message, _keepValue)
          ? this.message
          : message as String?,
    );
  }
}

class AppLockController extends Notifier<AppLockState> {
  AppLockController({
    this.initialEntry,
    this.initiallyLocked = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String? initialEntry;
  final bool initiallyLocked;
  final DateTime Function() _clock;

  late bool _loaded;
  DateTime? _hiddenDuringAuth;
  Future<int?>? _hiddenElapsedDuringAuth;
  Future<int?>? _awayElapsed;
  bool _resumedDuringAuth = false;
  final _unlockWaiters = <Completer<void>>[];

  SecureStorageService get _storage => ref.read(secureStorageProvider);
  AppLockPlatform get _platform => ref.read(appLockPlatformProvider);

  bool get locked => state.locked;
  bool get covered => state.covered;
  bool get authInProgress => state.authInProgress;
  bool get enabled => state.enabled;

  @override
  AppLockState build() {
    _loaded = initialEntry != null;
    ref.onDispose(() {
      for (final waiter in _unlockWaiters) {
        if (!waiter.isCompleted) waiter.complete();
      }
    });
    final config = AppLockConfig.decode(initialEntry);
    return AppLockState(
      enabled: initialEntry != null,
      locked: initiallyLocked,
      covered: false,
      authInProgress: false,
      awayAt: null,
      config: config,
    );
  }

  Future<AppLockConfig?> readConfig() async {
    final raw = await _storage.read(key: _storageKey);
    _loaded = true;
    final config = AppLockConfig.decode(raw);
    state = state.copyWith(enabled: raw != null, config: config);
    return config;
  }

  Future<AppLockConfig?> _config() async {
    if (_loaded) return state.config;
    return readConfig();
  }

  void onHidden(DateTime now, {Future<int?>? elapsed}) {
    // Lock off: no cover, so returning to the app looks exactly as before.
    if (!state.enabled || state.covered) return;
    if (state.authInProgress) {
      _hiddenDuringAuth ??= now;
      _hiddenElapsedDuringAuth ??= _platform.elapsedRealtime();
      return;
    }
    _awayElapsed = elapsed ?? _platform.elapsedRealtime();
    state = state.copyWith(covered: true, awayAt: now);
  }

  Future<void> onResumed(DateTime now) async {
    if (state.authInProgress) {
      if (_hiddenDuringAuth != null) _resumedDuringAuth = true;
      return;
    }
    final hiddenElapsed = _awayElapsed;
    _awayElapsed = null;
    int? elapsedAway;
    if (hiddenElapsed != null) {
      final from = await hiddenElapsed;
      final to = await _platform.elapsedRealtime();
      if (from != null && to != null) elapsedAway = to - from;
    }
    final config = await _config();
    final lock = shouldLock(
      enabled: config != null,
      awayAt: state.awayAt,
      afterSeconds: config?.after ?? 0,
      now: now,
      elapsedAwayMs: elapsedAway,
    );
    state = state.copyWith(
      covered: false,
      locked: state.locked || lock,
      awayAt: null,
    );
    _completeIfUnlocked();
  }

  Future<void> whenUnlocked() {
    if (!state.gated) return Future<void>.value();
    final waiter = Completer<void>();
    _unlockWaiters.add(waiter);
    return waiter.future;
  }

  Future<bool> unlockWithPin(String pin) async {
    final config = await _config();
    if (config == null) {
      if (!state.enabled) {
        _unlock();
        return true;
      }
      return false;
    }
    final now = _clock();
    if (await waitingNow(now)) {
      state = state.copyWith(message: messageFor(now));
      return false;
    }
    final actual = await _hashPin(pin, base64.decode(config.salt), config.iter);
    if (_constantTimeEquals(actual, base64.decode(config.hash))) {
      await _save(config.copyWith(fails: 0, waitUntil: null, waitStart: null));
      _unlock();
      return true;
    }
    await registerWrongAttempt(now: now);
    return false;
  }

  Future<bool> authenticateWithBiometrics() async {
    state = state.copyWith(authInProgress: true);
    _hiddenDuringAuth = null;
    _hiddenElapsedDuringAuth = null;
    _resumedDuringAuth = false;
    var ok = false;
    try {
      ok = await _platform.authenticate();
      if (ok) {
        await unlockWithBiometric();
      } else {
        state = state.copyWith(message: null);
      }
      return ok;
    } catch (error) {
      debugPrint('[AppLock] biometric prompt failed: $error');
      state = state.copyWith(message: biometricErrorCopy(error));
      return false;
    } finally {
      state = state.copyWith(authInProgress: false);
      // C5 ignores the prompt's own lifecycle noise, but a prompt that did
      // not succeed may have been cancelled by the user leaving the app
      // (stickyAuth: false): count that time away as usual.
      final hiddenAt = _hiddenDuringAuth;
      if (!ok && hiddenAt != null) {
        onHidden(hiddenAt, elapsed: _hiddenElapsedDuringAuth);
        if (_resumedDuringAuth) await onResumed(_clock());
      }
      _hiddenDuringAuth = null;
      _hiddenElapsedDuringAuth = null;
      _resumedDuringAuth = false;
    }
  }

  Future<void> unlockWithBiometric() async {
    final config = await _config();
    if (config != null) {
      await _save(config.copyWith(fails: 0, waitUntil: null, waitStart: null));
    }
    _unlock();
  }

  /// F15: the PIN-wait gate. Measures the wait on Android's time since
  /// boot, then rewrites [AppLockConfig.waitUntil] so the sync display
  /// checks below agree with it. A moved wall clock can't end a wait; a
  /// reboot (the boot clock went back) starts it again at full length.
  Future<bool> waitingNow([DateTime? now]) async {
    final current = now ?? _clock();
    await _syncWait(current);
    return isWaiting(current);
  }

  Future<void> _syncWait(DateTime now) async {
    final config = await _config();
    final until = config?.waitUntil;
    if (config == null || until == null) return;
    final elapsed = await _platform.elapsedRealtime();
    if (elapsed == null) return; // no boot clock (Dart-only tests)
    var start = config.waitStart;
    // A wait saved before F15 that is already over stays over.
    if (start == null && !now.isBefore(until)) return;
    if (start == null || elapsed < start) start = elapsed;
    final left = _waitSeconds(config.fails) * 1000 - (elapsed - start);
    await _save(left > 0
        ? config.copyWith(
            waitStart: start,
            waitUntil: now.add(Duration(milliseconds: left)),
          )
        : config.copyWith(waitStart: null, waitUntil: null));
  }

  bool isWaiting([DateTime? now]) {
    final config = state.config;
    final until = state.config?.waitUntil;
    if (config == null || until == null) return false;
    final remaining = until.difference(now ?? _clock());
    return remaining > Duration.zero &&
        remaining <= Duration(seconds: _waitSeconds(config.fails));
  }

  Duration waitRemaining([DateTime? now]) {
    final config = state.config;
    final until = config?.waitUntil;
    if (config == null || until == null) return Duration.zero;
    final current = now ?? _clock();
    if (!current.isBefore(until)) return Duration.zero;
    final remaining = until.difference(current);
    final maximum = Duration(seconds: _waitSeconds(config.fails));
    return remaining > maximum ? maximum : remaining;
  }

  String? messageFor([DateTime? now]) {
    final current = now ?? _clock();
    if (isWaiting(current)) {
      final seconds = (waitRemaining(current).inMilliseconds + 999) ~/ 1000;
      return 'Too many tries. Try again in ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}.';
    }
    if (state.message?.startsWith('Too many tries.') == true) return null;
    return state.message;
  }

  Future<void> registerWrongAttempt({DateTime? now}) async {
    final config = await _config();
    if (config == null) return;
    final current = now ?? _clock();
    if (isWaiting(current)) return;
    final fails = config.fails + 1;
    final wait = fails >= 5
        ? current.add(Duration(seconds: _waitSeconds(fails)))
        : null;
    final updated = config.copyWith(
      fails: fails,
      waitUntil: wait,
      waitStart: wait == null ? null : await _platform.elapsedRealtime(),
    );
    await _save(updated);
    final message = wait == null
        ? switch (5 - fails) {
            1 => 'Wrong PIN. 1 more try before a short wait.',
            2 => 'Wrong PIN. 2 more tries before a short wait.',
            _ => 'Wrong PIN.',
          }
        : messageFor(current);
    state = state.copyWith(message: message);
  }

  Future<void> turnOn(String pin, {bool bio = false}) async {
    if (isWeakPin(pin)) throw const FormatException('weak pin');
    final config = await _newConfig(pin, bio: bio);
    await _save(config);
    await _platform.setHideInRecents(true);
    state = state.copyWith(enabled: true, config: config, message: null);
  }

  Future<void> changePin(String pin) async {
    if (isWeakPin(pin)) throw const FormatException('weak pin');
    final current = await _config();
    if (current == null) return turnOn(pin);
    final next = await _newConfig(
      pin,
      bio: current.bio,
      after: current.after,
      hideNames: current.hideNames,
    );
    await _save(next);
    state = state.copyWith(config: next, message: null);
  }

  Future<void> resetPin(String pin) async {
    if (isWeakPin(pin)) throw const FormatException('weak pin');
    final current = await _config();
    // An entry that can't be read must not leave Forgot PIN a dead end.
    if (current == null) return turnOn(pin);
    final next = await _newConfig(
      pin,
      bio: current.bio,
      after: current.after,
      hideNames: current.hideNames,
    );
    await _save(next);
    state = state.copyWith(config: next, message: null);
  }

  Future<void> updateSettings({bool? bio, int? after, bool? hideNames}) async {
    final current = await _config();
    if (current == null) return;
    final next = current.copyWith(bio: bio, after: after, hideNames: hideNames);
    await _save(next);
    state = state.copyWith(config: next);
  }

  Future<void> turnOff() async {
    await _storage.delete(key: _storageKey);
    await _platform.setHideInRecents(false);
    _loaded = true;
    state = state.copyWith(
      enabled: false,
      locked: false,
      covered: false,
      awayAt: null,
      config: null,
      message: null,
    );
    _completeIfUnlocked();
  }

  Future<AppLockConfig> _newConfig(
    String pin, {
    required bool bio,
    int after = 60,
    bool hideNames = true,
  }) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hash = await _hashPin(pin, salt, _iterations);
    return AppLockConfig(
      salt: base64.encode(salt),
      hash: base64.encode(hash),
      iter: _iterations,
      bio: bio,
      after: after,
      hideNames: hideNames,
      fails: 0,
      waitUntil: null,
    );
  }

  Future<void> _save(AppLockConfig config) async {
    await _storage.write(key: _storageKey, value: config.encode());
    _loaded = true;
    state = state.copyWith(enabled: true, config: config);
  }

  void _unlock() {
    state = state.copyWith(
      locked: false,
      covered: false,
      awayAt: null,
      message: null,
    );
    _completeIfUnlocked();
  }

  void _completeIfUnlocked() {
    if (state.gated) return;
    for (final waiter in _unlockWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _unlockWaiters.clear();
  }
}

int _waitSeconds(int fails) => switch (fails) {
  5 => 30,
  6 => 60,
  7 => 300,
  _ when fails >= 8 => 900,
  _ => 0,
};

Future<List<int>> _hashPin(String pin, List<int> salt, int iterations) async {
  return compute(_derivePinHash, <String, dynamic>{
    'pin': pin,
    'salt': salt,
    'iterations': iterations,
  });
}

Future<List<int>> _derivePinHash(Map<String, dynamic> input) async {
  final pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: input['iterations'] as int,
    bits: _hashBits,
  );
  final key = await pbkdf2.deriveKeyFromPassword(
    password: input['pin'] as String,
    nonce: (input['salt'] as List).cast<int>(),
  );
  return key.extractBytes();
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  final length = min(left.length, right.length);
  for (var i = 0; i < length; i++) {
    difference |= left[i] ^ right[i];
  }
  return difference == 0;
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);
