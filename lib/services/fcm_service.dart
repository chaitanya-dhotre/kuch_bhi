import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/constants/app_constants.dart';
import '../data/local/database/app_database.dart';
import '../data/local/database/tables/app_settings_table.dart';
import '../data/local/secure_storage/secure_storage_service.dart';
import '../domain/repositories/message_repository.dart';

class FcmService {
  FcmService._();

  static final _localNotifications = FlutterLocalNotificationsPlugin();

  // Notification channels (per bible §9).
  static const _msgChannelId     = 'kb_messages';
  static const _msgChannelName   = 'Messages';
  static const _reqChannelId     = 'kb_requests';
  static const _reqChannelName   = 'Friend Requests';
  static const _sysChannelId     = 'kb_system';
  static const _sysChannelName   = 'System';

  static AppDatabase? _db;
  static SecureStorageService? _storage;
  static MessageRepository? _repository;

  static String? activeConversationId;
  static bool _notificationsReady = false;

  static void setRepository(MessageRepository repo) {
    _repository = repo;
  }

  /// Initializes local notifications + all channels. Idempotent and safe to
  /// call from the background isolate (which does NOT run [init]).
  static Future<void> _ensureNotifications() async {
    if (_notificationsReady) return;
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _msgChannelId, _msgChannelName, importance: Importance.high));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _reqChannelId, _reqChannelName, importance: Importance.defaultImportance));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _sysChannelId, _sysChannelName, importance: Importance.low));
    _notificationsReady = true;
  }

  // ── Init (call once at app start) ─────────────────────────────

  static Future<void> init(AppDatabase db, SecureStorageService storage) async {
    _db = db;
    _storage = storage;

    // Request permission.
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );

    // Init local notifications + channels.
    await _ensureNotifications();

    // Foreground messages: show notification + mark delivered.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Token refresh listener
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('[FCM] Token refreshed: $newToken');
      try {
        final localDb = _db ?? AppDatabase();
        final userId = await localDb.settingsDao.getSetting(AppSettingsKeys.currentUserId);
        if (userId != null && userId.isNotEmpty) {
          final localStorage = _storage ?? SecureStorageService();
          String? token = await localStorage.getAuthToken();
          token ??= await localDb.settingsDao.getSetting(AppSettingsKeys.authToken);
          if (token != null && token.isNotEmpty) {
            final pb = PocketBase(AppConstants.baseUrl);
            pb.authStore.save(token, null);
            await pb.collection('users').update(userId, body: {'fcm_token': newToken});
            await localDb.settingsDao.setSetting('last_fcm_token', newToken);
          }
        }
        if (_db == null) {
          await localDb.close();
        }
      } catch (e) {
        debugPrint('[FCM] Token refresh update failed: $e');
      }
    });

    // Register the token, retrying with backoff. On microG / degraded
    // Play-services devices the first getToken() often fails with
    // "Firebase Installations Service is unavailable" — a later retry
    // usually succeeds once microG finishes its own registration.
    unawaited(_registerTokenWithRetry());
  }

  static Future<void> _registerTokenWithRetry() async {
    const delays = [0, 15, 60, 300, 900]; // seconds
    for (final delay in delays) {
      if (delay > 0) await Future.delayed(Duration(seconds: delay));
      try {
        final localDb = _db ?? AppDatabase();
        final userId = await localDb.settingsDao
            .getSetting(AppSettingsKeys.currentUserId);
        if (userId == null || userId.isEmpty) {
          if (_db == null) await localDb.close();
          continue; // not logged in yet — try again later
        }
        final fcmToken = await FirebaseMessaging.instance.getToken();
        if (fcmToken == null || fcmToken.isEmpty) {
          if (_db == null) await localDb.close();
          continue;
        }
        final localStorage = _storage ?? SecureStorageService();
        String? token = await localStorage.getAuthToken();
        token ??= await localDb.settingsDao.getSetting(AppSettingsKeys.authToken);
        if (token != null && token.isNotEmpty) {
          final pb = PocketBase(AppConstants.baseUrl);
          pb.authStore.save(token, null);
          await pb.collection('users').update(userId, body: {'fcm_token': fcmToken});
          await localDb.settingsDao.setSetting('last_fcm_token', fcmToken);
          debugPrint('[FCM] Token registered successfully.');
          if (_db == null) await localDb.close();
          return; // success
        }
        if (_db == null) await localDb.close();
      } catch (e) {
        debugPrint('[FCM] token registration attempt failed: $e');
      }
    }
    debugPrint('[FCM] Token registration gave up — device likely has no '
        'working push services. Realtime SSE remains the delivery path.');
  }

  // ── Foreground handler ─────────────────────────────────────────

  static Future<void> _handleForegroundMessage(RemoteMessage msg) async {
    final data = msg.data;
    final type = data['type'] as String?;

    if (type == 'friend_request') {
      await _showFriendRequestNotification(data);
      return;
    }
    if (type != 'new_message') return;

    final messageId      = data['message_id'] as String?;
    final conversationId = data['conversation_id'] as String?;
    if (messageId == null || conversationId == null) return;

    await _markDelivered(messageId, conversationId);

    // Fetch and cache message in the local database so it displays immediately
    if (_repository != null) {
      try {
        debugPrint('[FCM] Fetching message $messageId in foreground');
        await _repository!.fetchAndCacheSingleMessage(messageId, conversationId);
      } catch (e) {
        debugPrint('[FCM] Failed to fetch/cache message in foreground: $e');
      }
    }

    // Only show notification if the user is not currently in the chat screen for this conversation.
    if (conversationId != activeConversationId) {
      await _showMessageNotification(data);
    }
  }

  // ── Background handler (called from main.dart) ─────────────────

  static Future<void> handleBackgroundMessage(RemoteMessage msg) async {
    // The background isolate has NOT run init() — set up notifications first,
    // otherwise the channel doesn't exist and nothing is shown.
    await _ensureNotifications();

    final data = msg.data;
    final type = data['type'] as String?;

    if (type == 'friend_request') {
      await _showFriendRequestNotification(data);
      return;
    }
    if (type != 'new_message') return;

    final messageId      = data['message_id'] as String?;
    final conversationId = data['conversation_id'] as String?;
    if (messageId == null || conversationId == null) return;

    await _markDelivered(messageId, conversationId);
    // Pre-cache the message so it's already in Drift when the user opens the
    // app from the notification (fixes "notification arrives but no message").
    await _cacheMessageBackground(messageId, conversationId);
    await _showMessageNotification(data);
  }

  /// Fetches + caches a single message using a standalone PB client in the
  /// background isolate (the repository singleton isn't available there).
  static Future<void> _cacheMessageBackground(
      String messageId, String conversationId) async {
    try {
      final localDb = _db ?? AppDatabase();
      final existing = await localDb.messagesDao.getMessageByServerId(messageId);
      if (existing != null) {
        if (_db == null) await localDb.close();
        return;
      }
      // We can only store the ciphertext row here (no key material in bg
      // isolate); the app decrypts on next open via reconciliation. Storing
      // the row guarantees the message exists locally the moment the app opens.
      final localStorage = _storage ?? SecureStorageService();
      String? token = await localStorage.getAuthToken();
      token ??= await localDb.settingsDao.getSetting(AppSettingsKeys.authToken);
      if (token == null || token.isEmpty) {
        if (_db == null) await localDb.close();
        return;
      }
      final pb = PocketBase(AppConstants.baseUrl);
      pb.authStore.save(token, null);
      final r = await pb.collection('messages').getOne(messageId);
      final rawType = r.getStringValue('type');
      await localDb.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId:        messageId, // deterministic; replaced by real localId on decrypt-sync
        serverId:       Value(messageId),
        conversationId: conversationId,
        senderId:       r.getStringValue('sender_id'),
        type:           rawType == 'file' ? 'document' : rawType,
        encryptedBody:  r.getStringValue('encrypted_body'),
        iv:             r.getStringValue('iv'),
        status:         const Value('delivered'),
        createdAt:      DateTime.tryParse(r.created) ?? DateTime.now(),
        updatedAt:      DateTime.now(),
      ));
      if (_db == null) await localDb.close();
    } catch (e) {
      debugPrint('[FCM] bg cache message error: $e');
    }
  }

  // ── Mark delivered ─────────────────────────────────────────────

  static Future<void> _markDelivered(
    String messageId,
    String conversationId,
  ) async {
    AppDatabase? localDb;
    try {
      final localStorage = _storage ?? SecureStorageService();
      localDb = _db ?? AppDatabase();

      // Restore auth token.
      String? token = await localStorage.getAuthToken();
      token ??= await localDb.settingsDao.getSetting(AppSettingsKeys.authToken);
      if (token == null || token.isEmpty) return;

      final myId = await localDb.settingsDao
          .getSetting(AppSettingsKeys.currentUserId);
      if (myId == null || myId.isEmpty) return;

      final pb = PocketBase(AppConstants.baseUrl);
      pb.authStore.save(token, null);

      // Check if receipt already exists.
      final existing = await pb.collection('message_receipts').getList(
        filter: 'message_id="$messageId"&&recipient_id="$myId"',
        perPage: 1,
      );

      final nowUtc = DateTime.now().toUtc().toIso8601String();
      if (existing.items.isEmpty) {
        try {
          await pb.collection('message_receipts').create(body: {
            'message_id':      messageId,
            'conversation_id': conversationId,
            'recipient_id':    myId,
            'delivered_at':    nowUtc,
          });
        } catch (_) {
          // Unique-index race — re-read and update if still undelivered.
          final again = await pb.collection('message_receipts').getList(
            filter: 'message_id="$messageId"&&recipient_id="$myId"', perPage: 1,
          );
          if (again.items.isNotEmpty &&
              again.items.first.getStringValue('delivered_at').isEmpty) {
            await pb.collection('message_receipts').update(
              again.items.first.id, body: {'delivered_at': nowUtc});
          }
        }
      } else if (existing.items.first.getStringValue('delivered_at').isEmpty) {
        await pb.collection('message_receipts').update(
          existing.items.first.id,
          body: {'delivered_at': nowUtc},
        );
      }

      debugPrint('[FCM] Marked delivered: $messageId');
    } catch (e) {
      debugPrint('[FCM] markDelivered error: $e');
    } finally {
      // Only close a DB we created here (never the shared singleton).
      if (_db == null && localDb != null) {
        await localDb.close();
      }
    }
  }

  // ── Show notification ──────────────────────────────────────────

  static Future<void> _showMessageNotification(Map<String, dynamic> data) async {
    try {
      await _ensureNotifications();
      final senderName = (data['sender_name'] as String?)?.trim();
      final title = (senderName != null && senderName.isNotEmpty)
          ? senderName
          : 'New message';
      // Body: media messages send a preview type; text is E2E so we can't
      // show content — show a neutral line.
      final preview = (data['preview'] as String?)?.trim();
      final body = (preview != null && preview.isNotEmpty)
          ? preview
          : 'Sent you a message';
      await _localNotifications.show(
        (data['conversation_id'] as String? ?? '').hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _msgChannelId, _msgChannelName,
            importance: Importance.high,
            priority:   Priority.high,
          ),
        ),
        payload: 'chat:${data['conversation_id']}',
      );
    } catch (e) {
      debugPrint('[FCM] showMessageNotification: $e');
    }
  }

  static Future<void> _showFriendRequestNotification(
      Map<String, dynamic> data) async {
    try {
      await _ensureNotifications();
      final fromName = (data['from_user_name'] as String?)?.trim();
      final title = 'Friend request';
      final body = (fromName != null && fromName.isNotEmpty)
          ? '$fromName wants to connect'
          : 'You have a new friend request';
      await _localNotifications.show(
        (data['request_id'] as String? ?? 'req').hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _reqChannelId, _reqChannelName,
            importance: Importance.defaultImportance,
            priority:   Priority.defaultPriority,
          ),
        ),
        payload: 'friend_requests',
      );
    } catch (e) {
      debugPrint('[FCM] showFriendRequestNotification: $e');
    }
  }
}
