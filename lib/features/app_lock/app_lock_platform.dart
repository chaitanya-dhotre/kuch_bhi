import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

class AppLockPlatform {
  AppLockPlatform({LocalAuthentication? authentication})
    : _authentication = authentication ?? LocalAuthentication();

  final LocalAuthentication _authentication;
  static const _channel = MethodChannel('kuch_bhi/privacy');

  Future<bool> isDeviceSupported() async {
    try {
      return await _authentication.isDeviceSupported();
    } on MissingPluginException {
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _authentication.getAvailableBiometrics();
    } on MissingPluginException {
      return const [];
    }
  }

  Future<bool> isAvailable() async {
    if (!await isDeviceSupported()) return false;
    return (await getAvailableBiometrics()).isNotEmpty;
  }

  Future<bool> authenticate() async {
    try {
      return await _authentication.authenticate(
        localizedReason: 'Unlock Kuch Bhi',
        authMessages: [
          AndroidAuthMessages(
            signInTitle: 'Unlock Kuch Bhi',
            cancelButton: 'Use PIN',
            biometricHint: '',
          ),
        ],
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: false,
          useErrorDialogs: false,
        ),
      );
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> setHideInRecents(bool hide) async {
    try {
      await _channel.invokeMethod<void>('setHideInRecents', hide);
    } on MissingPluginException {
      // The channel is unavailable in Dart-only tests.
    }
  }

  /// F15: Android's time since boot, in ms. It counts sleep and the user
  /// can't set it. Null when the channel is missing (Dart-only tests).
  Future<int?> elapsedRealtime() async {
    try {
      return await _channel.invokeMethod<int>('elapsedRealtime');
    } catch (_) {
      return null;
    }
  }

  Future<void> moveTaskToBack() async {
    try {
      await _channel.invokeMethod<void>('moveTaskToBack');
    } on MissingPluginException {
      // The channel is unavailable in Dart-only tests.
    }
  }
}

final appLockPlatformProvider = Provider<AppLockPlatform>((_) {
  return AppLockPlatform();
});
