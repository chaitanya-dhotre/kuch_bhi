import 'dart:math';
import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/network/pocketbase_client.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/app_settings_table.dart';
import '../../data/local/database/tables/users_table.dart';
import '../../data/local/secure_storage/secure_storage_service.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../services/encryption_service.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required this.pbClient,
    required this.db,
    required this.storage,
  });

  final PocketBaseClient pbClient;
  final AppDatabase db;
  final SecureStorageService storage;

  StreamSubscription<String>? _fcmTokenSubscription;

  PocketBase get _pb => pbClient.pb;

  // ── Sign in ────────────────────────────────────────────────────

  @override
  Future<User> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final authData = await _pb
          .collection('users')
          .authWithPassword(email, password);
      final user = _recordToUser(authData.record!);
      await _saveSession(user);
      return user;
    } on ClientException catch (e) {
      throw AuthException(_parseErrorMessage(e),
          code: e.statusCode.toString());
    } catch (e) {
      throw AuthException('Sign in failed: $e');
    }
  }

  @override
  Future<User> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthException('Google sign in was cancelled.');
      }
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw const AuthException('Failed to get Google ID token.');
      }
      final authData = await _pb.collection('users').authWithOAuth2Code(
        'google', idToken, '', '',
        createData: {
          'display_name': googleUser.displayName ?? googleUser.email,
          'username':     _emailToUsername(googleUser.email),
          'friend_code':  _generateFriendCode(),
        },
      );
      final user = _recordToUser(authData.record!);
      await _saveSession(user);
      return user;
    } on AuthException {
      rethrow;
    } on ClientException catch (e) {
      throw AuthException(_parseErrorMessage(e),
          code: e.statusCode.toString());
    } catch (e) {
      throw AuthException('Google sign in failed: $e');
    }
  }

  // ── Register ───────────────────────────────────────────────────

  @override
  Future<User> register({
    required String email,
    required String password,
    required String displayName,
    required String username,
  }) async {
    try {
      final friendCode = await _generateUniqueFriendCode();
      await _pb.collection('users').create(body: {
        'email':           email,
        'password':        password,
        'passwordConfirm': password,
        'display_name':    displayName,
        'username':        username,
        'friend_code':     friendCode,
      });
      final authData = await _pb
          .collection('users')
          .authWithPassword(email, password);
      final user = _recordToUser(authData.record!);
      await _saveSession(user);
      return user;
    } on ClientException catch (e) {
      throw AuthException(_parseErrorMessage(e),
          code: e.statusCode.toString());
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Registration failed: $e');
    }
  }

  // ── Get current user ───────────────────────────────────────────

  /// Single source of truth for session restoration.
  ///
  /// Strategy:
  /// 1. If PocketBase has no token → not authenticated.
  /// 2. Call authRefresh() to validate token AND get fresh user data.
  /// 3. If refresh fails due to network → fall back to Drift cache.
  /// 4. If refresh fails due to invalid token → sign out, return null.
  @override
  Future<User?> getCurrentUser() async {
    debugPrint('[Auth] getCurrentUser. isAuthenticated: ${pbClient.isAuthenticated}');

    if (!pbClient.isAuthenticated) {
      final driftToken = await db.settingsDao
          .getSetting(AppSettingsKeys.authToken);
      if (driftToken != null && driftToken.isNotEmpty) {
        _pb.authStore.save(driftToken, null);
      }
      if (!pbClient.isAuthenticated) {
        return null;
      }
    }

    final userId = await db.settingsDao.getSetting(AppSettingsKeys.currentUserId);
    if (userId == null || userId.isEmpty) return null;

    // Return cached user immediately and refresh in the background.
    final cached = await db.usersDao.getUserById(userId);
    if (cached != null) {
      _backgroundRefresh();
      return _tableDataToUser(cached);
    }

    // No local cache at all — validate with the server once.
    try {
      final authData = await _pb.collection('users').authRefresh();
      final user = _recordToUser(authData.record!);
      await _saveSession(user);
      return user;
    } on ClientException catch (e) {
      debugPrint('[Auth] No cache and refresh failed (${e.statusCode}): $e');
    } catch (e) {
      debugPrint('[Auth] No cache and refresh failed: $e');
    }

    return null;
  }

  void _backgroundRefresh() {
    _pb.collection('users').authRefresh().then((authData) async {
      if (authData.record == null) return;
      final user = _recordToUser(authData.record!);
      await _saveSession(user);
      debugPrint('[Auth] Background refresh done: ${user.displayName}');
    }).catchError((e) {
      debugPrint('[Auth] Background refresh failed: $e');
    });
  }

  // ── Sign out ───────────────────────────────────────────────────

  @override
  Future<void> signOut() async {
    await _fcmTokenSubscription?.cancel();
    _fcmTokenSubscription = null;
    pbClient.clearAuth();
    await storage.deleteAuthToken();
    await db.settingsDao.setSetting(AppSettingsKeys.authToken,     '');
    await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, '');
  }

  // ── Delete account ─────────────────────────────────────────────

  @override
  Future<void> deleteAccount() async {
    try {
      final userId = await db.settingsDao
          .getSetting(AppSettingsKeys.currentUserId);
      if (userId == null || userId.isEmpty) return;
      await _pb.collection('users').delete(userId);
      await signOut();
    } on ClientException catch (e) {
      throw AuthException(_parseErrorMessage(e));
    }
  }

  // ── FCM / public key ───────────────────────────────────────────

  @override
  Future<void> updateFcmToken(String token) async {
    if (!pbClient.isAuthenticated) return;
    final userId = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId);
    if (userId == null || userId.isEmpty) return;
    try {
      await _pb.collection('users')
          .update(userId, body: {'fcm_token': token});
    } catch (_) {}
  }

  @override
  Future<void> updatePublicKey(String publicKeyBase64) async {
    if (!pbClient.isAuthenticated) return;
    final userId = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId);
    if (userId == null || userId.isEmpty) return;
    await _pb.collection('users')
        .update(userId, body: {'public_key': publicKeyBase64});
  }

  // ── Session save ───────────────────────────────────────────────

  Future<void> _saveSession(User user) async {
    final token = _pb.authStore.token;

    // Save token to SecureStorage (primary).
    try {
      await storage.saveAuthToken(token);
    } catch (e) {
      debugPrint('[Auth] SecureStorage save failed: $e');
    }

    // Save token to Drift (reliable fallback for Samsung devices
    // where EncryptedSharedPreferences fails across restarts).
    await db.settingsDao.setSetting(AppSettingsKeys.authToken, token);
    await db.settingsDao.setSetting(
        AppSettingsKeys.currentUserId, user.id);

    await _cacheUserLocally(user);
    debugPrint('[Auth] Session saved. userId: ${user.id}');

    _ensureFcmTokenListener();

    // Register FCM token with server.
    try {
      // Check for pending token first (from app startup)
      var fcmToken = await db.settingsDao.getSetting('pending_fcm_token');
      
      // If no pending token, fetch fresh one
      if (fcmToken == null || fcmToken.isEmpty) {
        fcmToken = await FirebaseMessaging.instance.getToken();
      }
      
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await _pb.collection('users').update(user.id, body: {
          'fcm_token': fcmToken,
        });
        debugPrint('[FCM] Token registered for user ${user.id}');
        // Clear pending token after successful registration
        await db.settingsDao.setSetting('pending_fcm_token', '');
      }
    } catch (e) {
      debugPrint('[FCM] Token update failed: $e');
    }

    // Generate encryption key pair if this is a new device.
    await _initEncryptionKeys(user.id);
  }

  // ── Helpers ────────────────────────────────────────────────────

  Future<void> _cacheUserLocally(User user) async {
    await db.usersDao.upsertUser(UsersTableCompanion.insert(
      id:          user.id,
      displayName: user.displayName,
      username:    user.username,
      email:       Value(user.email),
      avatarUrl:   Value(user.avatarUrl),
      about:       Value(user.about),
      friendCode:  user.friendCode,
      publicKey:   Value(user.publicKey),
      isOnline:    Value(user.isOnline),
      createdAt:   user.createdAt,
      updatedAt:   DateTime.now(),
    ));
  }

  Future<void> _initEncryptionKeys(String userId) async {
    try {
      final enc = EncryptionService(storage);
      final pubKeyB64 = await enc.getPublicKeyBase64();

      // Only upload if server doesn't have it yet.
      final record = await _pb.collection('users').getOne(userId);
      if (record.getStringValue('public_key').isEmpty) {
        await updatePublicKey(pubKeyB64);
      }
    } catch (e) {
      debugPrint('[Keys] initEncryptionKeys: $e');
    }
  }

  void _ensureFcmTokenListener() {
    if (_fcmTokenSubscription != null) return;
    _fcmTokenSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
      (token) {
        updateFcmToken(token);
      },
      onError: (e) => debugPrint('[FCM] Token refresh listener error: $e'),
    );
  }

  User _recordToUser(RecordModel record) {
    final avatar = record.getStringValue('avatar');
    return User(
      id:          record.id,
      displayName: record.getStringValue('display_name'),
      username:    record.getStringValue('username'),
      email:       record.getStringValue('email'),
      friendCode:  record.getStringValue('friend_code'),
      avatarUrl:   avatar.isEmpty ? null
          : '${_pb.baseUrl}/api/files/users/${record.id}/$avatar',
      about:       record.getStringValue('about').isEmpty ? null
          : record.getStringValue('about'),
      publicKey:   record.getStringValue('public_key').isEmpty ? null
          : record.getStringValue('public_key'),
      isOnline:    record.getBoolValue('is_online'),
      createdAt:   DateTime.tryParse(record.created) ?? DateTime.now(),
    );
  }

  User _tableDataToUser(UsersTableData data) => User(
    id:          data.id,
    displayName: data.displayName,
    username:    data.username,
    email:       data.email ?? '',
    friendCode:  data.friendCode,
    avatarUrl:   data.avatarUrl,
    about:       data.about,
    publicKey:   data.publicKey,
    isOnline:    data.isOnline,
    lastSeen:    data.lastSeen,
    createdAt:   data.createdAt,
  );

  String _parseErrorMessage(ClientException e) {
    try {
      final data = e.response['data'] as Map<String, dynamic>?;
      if (data != null) {
        for (final field in data.values) {
          final msg = (field as Map<String, dynamic>)['message'];
          if (msg != null) return msg.toString();
        }
      }
      return (e.response['message'] as String?)
          ?? 'An error occurred. Please try again.';
    } catch (_) {
      return 'An error occurred. Please try again.';
    }
  }

  String _generateFriendCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng   = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<String> _generateUniqueFriendCode() async {
    while (true) {
      final code = _generateFriendCode();
      try {
        await _pb.collection('users')
            .getFirstListItem('friend_code="$code"');
      } on ClientException catch (e) {
        if (e.statusCode == 404) return code;
        rethrow;
      }
    }
  }

  String _emailToUsername(String email) => email
      .split('@').first
      .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
      .toLowerCase();
}

// Clean provider — no loading state, no _LoadingAuthRepository.
// pocketbaseClientProvider is a plain Provider overridden in main().
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    pbClient: ref.watch(pocketbaseClientProvider),
    db:       ref.read(appDatabaseProvider),
    storage:  ref.read(secureStorageProvider),
  );
});
