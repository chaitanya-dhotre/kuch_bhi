import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/constants/app_constants.dart';
import '../core/router/app_router.dart';
import '../data/local/database/app_database.dart';
import '../data/local/database/tables/app_settings_table.dart';
import '../data/local/secure_storage/secure_storage_service.dart';
import '../domain/entities/conversation.dart';
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

  /// One-shot guard: at most one cold-start launch tap routes per app
  /// process. A launch reachable via both getInitialMessage (FCM) and
  /// the local-notification launch details must never double-push.
  static bool _launchHandled = false;

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
      // Tap routing — this response channel fires ONLY while the app is
      // running (foreground or background-alive). A tap that cold-starts
      // a killed app never reaches it on v18; those launches are recovered
      // after initialize() via getNotificationAppLaunchDetails — see
      // _handleLocalLaunchDetails below.
      onDidReceiveNotificationResponse: _onNotificationResponse,
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

    // Tap on an FCM-displayed notification while the app is in the
    // background (system tray) — route by message data.
    FirebaseMessaging.onMessageOpenedApp.listen(
      (msg) => _routeFromData(msg.data),
    );

    // Cold start from an FCM-displayed notification tap. Fire-and-forget:
    // this runs in main() before runApp(), and auth/sync still resolve on
    // splash, so the routing helper polls until the router is ready.
    unawaited(_handleInitialMessage());

    // Cold start from a LOCAL-notification tap (app was killed): v18's
    // response channel never fires for that, so recover the launch payload
    // from the plugin now that initialize() has run, and route it through
    // the same payload path (same router-ready wait guard inside).
    unawaited(_handleLocalLaunchDetails());

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

  // ── Notification tap routing ────────────────────────────────────
  //
  // Payload map (local notifications shown by this service):
  //   'friend_requests'    -> FriendRequestsScreen
  //   'chat:<conv_id>'     -> ChatScreen for that conversation
  // FCM data types (onMessageOpenedApp / getInitialMessage):
  //   'friend_request' / 'group_invite' -> FriendRequestsScreen
  //   'new_message' (conversation_id)   -> ChatScreen for that conversation
  // Anything else is a logged no-op. Every path is crash-proofed: a bad
  // payload never takes the app down, it just opens/keeps the current state.

  /// flutter_local_notifications tap callback (main isolate only — the
  /// background isolate's registration of this simply never fires there).
  /// On v18 this response channel fires ONLY while the app is running
  /// (foreground or background-alive); a tap that cold-starts a killed
  /// app never reaches it. Cold-start local-notification taps are
  /// recovered by [_handleLocalLaunchDetails] via
  /// getNotificationAppLaunchDetails after initialize().
  static Future<void> _onNotificationResponse(
    NotificationResponse response,
  ) async {
    await _routeFromPayload(response.payload);
  }

  /// Cold-start tap on an FCM-displayed notification.
  static Future<void> _handleInitialMessage() async {
    if (_launchHandled) return; // local-notification path already routed.
    try {
      final msg = await FirebaseMessaging.instance.getInitialMessage();
      if (msg == null || _launchHandled) return;
      _launchHandled = true;
      await _routeFromData(msg.data);
    } catch (e) {
      debugPrint('[FCM] getInitialMessage failed: $e');
    }
  }

  /// Cold-start tap on a LOCAL notification shown by this service (app was
  /// killed). On v18 the plugin's response channel only fires while the app
  /// is running, so this launch never invokes
  /// [onDidReceiveNotificationResponse] — instead recover the launch
  /// payload via getNotificationAppLaunchDetails and route it through the
  /// same [_routeFromPayload] path the response handler uses. Best-effort:
  /// any failure is a no-op, and a normal launcher-icon open reports
  /// didNotificationLaunchApp=false, so it never re-routes an old
  /// notification.
  static Future<void> _handleLocalLaunchDetails() async {
    if (_launchHandled) return; // FCM getInitialMessage already routed.
    try {
      final details =
          await _localNotifications.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return;
      if (_launchHandled) return; // FCM path won the concurrent race.
      _launchHandled = true;
      await _routeFromPayload(details.notificationResponse?.payload);
    } catch (e) {
      // Silent no-op — cold-start recovery must never break app start.
      debugPrint('[FCM] Local notification launch recovery failed: $e');
    }
  }

  static Future<void> _routeFromPayload(String? payload) async {
    try {
      if (payload == null || payload.isEmpty) return;
      if (payload == 'friend_requests') {
        await _pushFriendRequests();
        return;
      }
      if (payload.startsWith('chat:')) {
        final convId = payload.substring('chat:'.length);
        if (convId.isNotEmpty) await _openChat(convId);
        return;
      }
      debugPrint('[FCM] Tap with unknown payload "$payload" — no-op.');
    } catch (e, s) {
      debugPrint('[FCM] Tap routing failed: $e\n$s');
    }
  }

  static Future<void> _routeFromData(Map<String, dynamic> data) async {
    try {
      final type = data['type'] as String?;
      if (type == 'friend_request' || type == 'group_invite') {
        await _pushFriendRequests();
        return;
      }
      if (type == 'new_message') {
        final convId = data['conversation_id'] as String?;
        if (convId != null && convId.isNotEmpty) await _openChat(convId);
        return;
      }
      debugPrint('[FCM] Tap with unknown type "$type" — no-op.');
    } catch (e, s) {
      debugPrint('[FCM] Tap routing failed: $e\n$s');
    }
  }

  static Future<void> _pushFriendRequests() async {
    if (!await _waitForRouter()) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    if (_currentLocation() == AppRoutes.friendRequests) return; // already there
    ctx.push(AppRoutes.friendRequests);
  }

  static Future<void> _openChat(String conversationId) async {
    if (!await _waitForRouter()) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    // Already viewing this chat — don't stack a duplicate route.
    if (_currentLocation() == AppRoutes.chat) {
      final top = GoRouter.of(ctx).state.extra;
      if (top is Conversation && top.id == conversationId) return;
    }

    final conv = await _loadConversation(conversationId);
    if (conv == null) {
      debugPrint('[FCM] Conversation $conversationId not cached locally — '
          'staying on current screen. (Follow-up: fetch conversation from '
          'server on tap when local cache is cold.)');
      return;
    }
    // Re-check after the async conversation lookup: mounted, and still
    // not already viewing this chat. N taps that raced past the check
    // above resume here one at a time — the first pushes, the rest see
    // the target chat already on top and bail instead of stacking.
    if (!ctx.mounted) return;
    if (_currentLocation() == AppRoutes.chat) {
      final top = GoRouter.of(ctx).state.extra;
      if (top is Conversation && top.id == conversationId) return;
    }
    ctx.push(AppRoutes.chat, extra: conv);
  }

  /// Resolves the [Conversation] for a tap. Prefers the repository (fills
  /// otherUser / memberCount via the same mapping the home list uses);
  /// falls back to the raw Drift row for cold starts where the repository
  /// provider has not been built yet. Best-effort — null means "don't
  /// navigate", never a crash.
  static Future<Conversation?> _loadConversation(String conversationId) async {
    final repo = _repository;
    if (repo != null) {
      try {
        final conv = await repo.watchConversation(conversationId).first;
        if (conv != null) return conv;
      } catch (e) {
        debugPrint('[FCM] watchConversation tap lookup failed: $e');
      }
    }
    final db = _db;
    if (db != null) {
      try {
        final row =
            await db.conversationsDao.getConversationById(conversationId);
        if (row != null) {
          return Conversation(
            id:        row.id,
            type:      row.type,
            name:      row.name,
            iconUrl:   row.iconUrl,
            lastMessagePreview: row.lastMessagePreview,
            lastMessageAt:      row.lastMessageAt,
            onlyAdminsCanMessage: row.onlyAdminsCanMessage,
          );
        }
      } catch (e) {
        debugPrint('[FCM] DAO tap lookup failed: $e');
      }
    }
    return null;
  }

  /// Current top route location, or null if the router isn't usable yet.
  static String? _currentLocation() {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    try {
      return GoRouter.of(ctx).state.matchedLocation;
    } catch (_) {
      return null; // InheritedGoRouter not mounted yet — caller retries.
    }
  }

  /// Early taps (cold start / launch from a killed app) can arrive before
  /// runApp() has mounted the router, and auth + encryption-sync keep the
  /// app on splash for a few seconds after. Poll until the router leaves
  /// splash, then give up best-effort — never fight the redirect logic.
  static Future<bool> _waitForRouter() async {
    for (var i = 0; i < 15; i++) {
      final loc = _currentLocation();
      if (loc != null && loc != AppRoutes.splash) return true;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    debugPrint('[FCM] Router never left splash — giving up on tap routing.');
    return false;
  }

  // ── Foreground handler ─────────────────────────────────────────

  static Future<void> _handleForegroundMessage(RemoteMessage msg) async {
    final data = msg.data;
    final type = data['type'] as String?;

    if (type == 'friend_request') {
      await _showFriendRequestNotification(data);
      return;
    }
    if (type == 'group_invite') {
      await _showGroupInviteNotification(data);
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
    if (type == 'group_invite') {
      await _showGroupInviteNotification(data);
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
  /// Background-isolate network calls race Android's network bring-up
  /// (Redmi: `Failed host lookup` right after process start) — retry with
  /// backoff so a cold-start FCM pre-cache actually lands.
  static Future<T> _retryNetwork<T>(Future<T> Function() op,
      {int tries = 3}) async {
    for (var i = 1;; i++) {
      try {
        return await op();
      } on ClientException catch (e) {
        // 404 (deleted message / rule-hidden) is terminal — retrying just
        // burns the background isolate's short execution window.
        if (i >= tries || e.statusCode == 404) rethrow;
        debugPrint('[FCM] network retry $i/$tries: $e');
        await Future<void>.delayed(Duration(seconds: 2 * i));
      } catch (e) {
        if (i >= tries) rethrow;
        debugPrint('[FCM] network retry $i/$tries: $e');
        await Future<void>.delayed(Duration(seconds: 2 * i));
      }
    }
  }

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
      final r = await _retryNetwork(
          () => pb.collection('messages').getOne(messageId));
      final rawType = r.getStringValue('type');
      // Keyed on serverId (unique index): when the main isolate already
      // cached this message under a UUID, this updates that row instead of
      // inserting a duplicate bubble.
      await localDb.messagesDao.upsertMessageByServerId(
          MessagesTableCompanion.insert(
        localId:        messageId, // deterministic; matches existing row on conflict
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
      final existing = await _retryNetwork(
          () => pb.collection('message_receipts').getList(
                filter: 'message_id="$messageId"&&recipient_id="$myId"',
                perPage: 1,
              ));

      final nowUtc = DateTime.now().toUtc().toIso8601String();
      if (existing.items.isEmpty) {
        try {
          await _retryNetwork(() => pb.collection('message_receipts').create(
                body: {
                  'message_id':   messageId,
                  'conversation_id': conversationId,
                  'recipient_id': myId,
                  'delivered_at': nowUtc,
                },
              ));
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

  /// Local-only notification for group invites. Safe in the background
  /// isolate: touches no repository/PB — pure local-notifications show,
  /// exactly like [_showFriendRequestNotification].
  static Future<void> _showGroupInviteNotification(
      Map<String, dynamic> data) async {
    try {
      await _ensureNotifications();
      final inviterName = (data['inviter_name'] as String?)?.trim();
      final convName    = (data['conversation_name'] as String?)?.trim();
      final groupName   =
          (convName != null && convName.isNotEmpty) ? convName : 'a group';
      final title = 'Group invite';
      final body  = (inviterName != null && inviterName.isNotEmpty)
          ? '$inviterName invited you to $groupName'
          : 'You were invited to $groupName';
      await _localNotifications.show(
        (data['invite_id'] as String? ?? 'inv').hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _reqChannelId, _reqChannelName,
            importance: Importance.defaultImportance,
            priority:   Priority.defaultPriority,
          ),
        ),
        payload: 'friend_requests', // same Requests screen as friend_request
      );
    } catch (e) {
      debugPrint('[FCM] showGroupInviteNotification: $e');
    }
  }
}
