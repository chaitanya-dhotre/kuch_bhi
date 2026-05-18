import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/network/pocketbase_client.dart';
import 'data/local/database/app_database.dart';
import 'data/local/database/tables/app_settings_table.dart';
import 'data/local/secure_storage/secure_storage_service.dart';
import 'firebase_options.dart';
import 'services/fcm_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FcmService.handleBackgroundMessage(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FcmService.init();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize all critical services before runApp so providers
  // are immediately available without any loading state.
  final secureStorage = SecureStorageService();
  final db            = AppDatabase();
  final pbClient      = await PocketBaseClient.create(secureStorage);

  // Force FCM token registration on every app start
  FirebaseMessaging.instance.getToken().then((token) async {
    if (token == null) return;
    debugPrint('[FCM] Device token: $token');
    // Will be picked up by auth_repository._saveSession on next auth refresh
    final db = AppDatabase();
    await db.settingsDao.setSetting('pending_fcm_token', token);
  });

  runApp(
    ProviderScope(
      overrides: [
        // Plain Provider overrides — no AsyncValue, no loading flash.
        secureStorageProvider.overrideWithValue(secureStorage),
        appDatabaseProvider.overrideWithValue(db),
        pocketbaseClientProvider.overrideWithValue(pbClient),
      ],
      child: const KuchBhiApp(),
    ),
  );
}
