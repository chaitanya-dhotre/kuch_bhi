import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import 'app.dart';
import 'core/network/pocketbase_client.dart';
import 'data/local/database/app_database.dart';
import 'data/local/secure_storage/secure_storage_service.dart';
import 'firebase_options.dart';
import 'services/fcm_service.dart';
import 'core/utils/fcm_debug_helper.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FcmService.handleBackgroundMessage(message);
}

Future<void> main() async {
  if (kDebugMode) {
    // Marionette: agent-driven app interaction over the VM service —
    // debug builds only (release falls through to the normal binding).
    MarionetteBinding.ensureInitialized();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }

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

  // Initialize all critical services before runApp so providers
  // are immediately available without any loading state.
  final secureStorage = SecureStorageService();
  final db            = AppDatabase();
  final pbClient      = await PocketBaseClient.create(secureStorage);

  await FcmService.init(db, secureStorage);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // FCM token registration is handled by auth_repository_impl and fcm_service.
  await FcmDebugHelper.printFcmDebugInfo();

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
