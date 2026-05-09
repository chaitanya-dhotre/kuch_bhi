import 'dart:math';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../core/network/pocketbase_client.dart';
import '../../data/local/database/app_database.dart';
import '../../data/local/database/tables/app_settings_table.dart';
import '../../data/local/database/tables/users_table.dart';
import '../../data/local/secure_storage/secure_storage_service.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    required this.pbClient,
    required this.db,
    required this.storage,
  });

  final PocketBaseClient pbClient;
  final AppDatabase db;
  final SecureStorageService storage;

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
    debugPrint('[Auth] getCurrentUser called. '
        'isAuthenticated: ${pbClient.isAuthenticated}');

    if (!pbClient.isAuthenticated) {
      // Try to restore token from Drift (SecureStorage may have failed).
      final driftToken = await db.settingsDao
          .getSetting(AppSettingsKeys.authToken);
      if (driftToken != null && driftToken.isNotEmpty) {
        _pb.authStore.save(driftToken, null);
        debugPrint('[Auth] Token restored from Drift. '
            'isValid: ${pbClient.isAuthenticated}');
      }
      if (!pbClient.isAuthenticated) {
        debugPrint('[Auth] No valid token found anywhere. '
            'User must sign in.');
        return null;
      }
    }

    // Validate token with server and get fresh user data.
    try {
      final authData = await _pb.collection('users').authRefresh();
      final user = _recordToUser(authData.record!);
      await _saveSession(user);
      debugPrint('[Auth] Session refreshed from server. '
          'User: ${user.displayName}');
      return user;
    } on ClientException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        // Token is expired or revoked — force re-login.
        debugPrint('[Auth] Token invalid (${e.statusCode}). '
            'Clearing session.');
        await signOut();
        return null;
      }
      // Network error — fall back to local cache.
      debugPrint('[Auth] Server unreachable (${e.statusCode}). '
          'Using cached user.');
    } catch (e) {
      // Any other error — fall back to local cache.
      debugPrint('[Auth] authRefresh error: $e. Using cached user.');
    }

    // Offline fallback: use cached user from Drift.
    final userId = await db.settingsDao
        .getSetting(AppSettingsKeys.currentUserId);
    if (userId == null || userId.isEmpty) return null;
    final cached = await db.usersDao.getUserById(userId);
    if (cached == null) return null;
    debugPrint('[Auth] Using cached user: ${cached.displayName}');
    return _tableDataToUser(cached);
  }

  // ── Sign out ───────────────────────────────────────────────────

  @override
  Future<void> signOut() async {
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
