import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/constants/app_constants.dart';
import '../data/local/database/app_database.dart';
import '../data/local/database/tables/app_settings_table.dart';
import '../data/local/secure_storage/secure_storage_service.dart';

class FcmService {
  FcmService._();

  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId   = 'kb_messages';
  static const _channelName = 'Messages';

  // ── Init (call once at app start) ─────────────────────────────

  static Future<void> init() async {
    // Request permission.
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );

    // Init local notifications.
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );

    // Create Android notification channel.
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId, _channelName,
        importance: Importance.high,
      ),
    );

    // Foreground messages: show notification + mark delivered.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Token refresh listener
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('[FCM] Token refreshed: $newToken');
      try {
        final db = AppDatabase();
        final userId = await db.settingsDao.getSetting(AppSettingsKeys.currentUserId);
        if (userId != null && userId.isNotEmpty) {
          final storage = SecureStorageService();
          String? token = await storage.getAuthToken();
          token ??= await db.settingsDao.getSetting(AppSettingsKeys.authToken);
          if (token != null && token.isNotEmpty) {
            final pb = PocketBase(AppConstants.baseUrl);
            pb.authStore.save(token, null);
            await pb.collection('users').update(userId, body: {'fcm_token': newToken});
            await db.settingsDao.setSetting('last_fcm_token', newToken);
          }
        }
        await db.close();
      } catch (e) {
        debugPrint('[FCM] Token refresh update failed: $e');
      }
    });

    // Immediately try to register token if logged in
    try {
      final db = AppDatabase();
      final userId = await db.settingsDao.getSetting(AppSettingsKeys.currentUserId);
      if (userId != null && userId.isNotEmpty) {
        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          final storage = SecureStorageService();
          String? token = await storage.getAuthToken();
          token ??= await db.settingsDao.getSetting(AppSettingsKeys.authToken);
          if (token != null && token.isNotEmpty) {
            final pb = PocketBase(AppConstants.baseUrl);
            pb.authStore.save(token, null);
            await pb.collection('users').update(userId, body: {'fcm_token': fcmToken});
            await db.settingsDao.setSetting('last_fcm_token', fcmToken);
          }
        }
      }
      await db.close();
    } catch (e) {
      debugPrint('[FCM] init registration failed: $e');
    }
  }

  // ── Foreground handler ─────────────────────────────────────────

  static Future<void> _handleForegroundMessage(RemoteMessage msg) async {
    final data = msg.data;
    if (data['type'] != 'new_message') return;

    final messageId      = data['message_id'] as String?;
    final conversationId = data['conversation_id'] as String?;
    if (messageId == null || conversationId == null) return;

    await _markDelivered(messageId, conversationId);
    await _showNotification(data);
  }

  // ── Background handler (called from main.dart) ─────────────────

  static Future<void> handleBackgroundMessage(RemoteMessage msg) async {
    final data = msg.data;
    if (data['type'] != 'new_message') return;

    final messageId      = data['message_id'] as String?;
    final conversationId = data['conversation_id'] as String?;
    if (messageId == null || conversationId == null) return;

    await _markDelivered(messageId, conversationId);
    await _showNotification(data);
  }

  // ── Mark delivered ─────────────────────────────────────────────

  static Future<void> _markDelivered(
    String messageId,
    String conversationId,
  ) async {
    try {
      final storage = SecureStorageService();
      final db      = AppDatabase();

      // Restore auth token.
      String? token = await storage.getAuthToken();
      token ??= await db.settingsDao.getSetting(AppSettingsKeys.authToken);
      if (token == null || token.isEmpty) return;

      final myId = await db.settingsDao
          .getSetting(AppSettingsKeys.currentUserId);
      if (myId == null || myId.isEmpty) return;

      final pb = PocketBase(AppConstants.baseUrl);
      pb.authStore.save(token, null);

      // Check if receipt already exists.
      final existing = await pb.collection('message_receipts').getList(
        filter: 'message_id="$messageId"&&recipient_id="$myId"',
        perPage: 1,
      );

      if (existing.items.isEmpty) {
        await pb.collection('message_receipts').create(body: {
          'message_id':     messageId,
          'conversation_id': conversationId,
          'recipient_id':   myId,
          'delivered_at':   DateTime.now().toIso8601String(),
        });
      } else if (existing.items.first.getStringValue('delivered_at').isEmpty) {
        await pb.collection('message_receipts').update(
          existing.items.first.id,
          body: {'delivered_at': DateTime.now().toIso8601String()},
        );
      }

      debugPrint('[FCM] Marked delivered: $messageId');
      await db.close();
    } catch (e) {
      debugPrint('[FCM] markDelivered error: $e');
    }
  }

  // ── Show notification ──────────────────────────────────────────

  static Future<void> _showNotification(Map<String, dynamic> data) async {
    try {
      await _localNotifications.show(
        data['message_id'].hashCode,
        'New message',
        'You have a new message',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId, _channelName,
            importance: Importance.high,
            priority:   Priority.high,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[FCM] showNotification: $e');
    }
  }
}
