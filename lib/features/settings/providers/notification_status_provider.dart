import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Whether Android lets the app post notifications (spec S5). A read-out
/// only: the server keeps no per-user preference, so there is no in-app
/// switch. The Settings screen re-reads it on resume.
final notificationsEnabledProvider = FutureProvider.autoDispose<bool>(
  (ref) async => (await Permission.notification.status).isGranted,
);

/// Opens the app's system settings page. A provider so tests can override it.
final openSystemSettingsProvider =
    Provider<Future<bool> Function()>((ref) => openAppSettings);
