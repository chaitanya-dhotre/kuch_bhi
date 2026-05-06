import 'package:firebase_messaging/firebase_messaging.dart';

/// Handles all FCM message processing.
/// Background handler logic goes here — runs even when app is killed.
class FcmService {
  FcmService._();

  /// Called by the top-level background handler in main.dart.
  /// Do NOT call PocketBase here yet — implement in Phase 4.
  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    // Phase 4 implementation: mark message as delivered in PocketBase
  }
}
