import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/app_settings_table.dart';

class FcmDebugHelper {
  static Future<void> printFcmDebugInfo() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      final isAuthorized = settings.authorizationStatus == AuthorizationStatus.authorized;
      
      final db = AppDatabase();
      final userId = await db.settingsDao.getSetting(AppSettingsKeys.currentUserId);
      final isAuth = userId != null && userId.isNotEmpty;
      await db.close();
      
      debugPrint('[FCM Debug] Token: $fcmToken Permission: ${isAuthorized ? 'authorized' : 'denied'} User: ${isAuth ? userId : 'unauthenticated'}');
    } catch (e) {
      debugPrint('[FCM Debug] Error: $e');
    }
  }
}
