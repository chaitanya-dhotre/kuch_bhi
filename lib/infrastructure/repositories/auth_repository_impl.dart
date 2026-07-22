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
  Future<GooglePrefill?> getGooglePrefill() async {
    try {
      final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null; // user cancelled
      return GooglePrefill(
        email:       googleUser.email,
        displayName: googleUser.displayName,
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException('Google sign in failed: $e');
    }
  }

  @override
  Future<GoogleAuthResult?> signInWithGoogle() async {
    try {
      final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null; // user cancelled
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw const AuthException('Failed to get Google ID token.');
      }
      // Pre-generate the fields PB requires on CREATE. For an existing
      // account these are simply ignored and the user is signed in directly.
      final friendCode = await _generateUniqueFriendCode();
      final username   = await _generateUniqueUsername(googleUser.email);
      final displayName = (googleUser.displayName?.trim().isNotEmpty ?? false)
          ? googleUser.displayName!.trim()
          : googleUser.email.split('@').first;
      final authData = await _pb.collection('users').authWithOAuth2Code(
        'google', idToken, '', '',
        createData: {
          'display_name': displayName,
          'username':     username,
          'friend_code':  friendCode,
          'emailVisibility': true,
        },
      );
      final user = _recordToUser(authData.record!);
      await _saveSession(user);
      final isNew = authData.meta['isNew'] == true;
      return GoogleAuthResult(user: user, isNew: isNew);
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
      // Ensure current_user_id is written to Drift NOW so that _myId() in the
      // message repository resolves immediately without waiting for _backgroundRefresh.
      await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, userId);

      // Detect reinstall: Drift token survived but SecureStorage (private key) was wiped.
      // In this case we must synchronously generate and upload the new key pair BEFORE
      // returning, so the messaging layer derives the correct conversation keys from the start.
      final existingPriv = await storage.getPrivateKey();
      if (existingPriv == null) {
        debugPrint('[Auth] Reinstall detected on restart — re-initialising encryption keys synchronously.');
        await _initEncryptionKeys(userId);
      }
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

    // Save token + userId to SecureStorage (primary).
    // Writing userId here lets _myId() resolve immediately via SecureStorage
    // fallback before the Drift write below has a chance to complete.
    try {
      await storage.saveAuthToken(token);
      await storage.saveCurrentUserId(user.id);
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
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null && fcmToken.isNotEmpty) {
        final lastToken = await db.settingsDao.getSetting('last_fcm_token');
        if (fcmToken != lastToken) {
          await _pb.collection('users').update(user.id, body: {
            'fcm_token': fcmToken,
          });
          await db.settingsDao.setSetting('last_fcm_token', fcmToken);
          debugPrint('[FCM] Token registered for user ${user.id}');
        }
      }
    } catch (e) {
      debugPrint('[FCM] Token registration failed: $e');
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
      final enc = EncryptionService(storage, pbClient);

      // Check if secure storage already had a key pair before this session.
      // If both keys exist in storage, the key pair was NOT freshly generated.
      final existingPriv = await storage.getPrivateKey();
      final existingPub  = await storage.getLocalPublicKey();
      final hadExistingKeys = existingPriv != null && existingPub != null;

      if (!hadExistingKeys) {
        // Private key is missing locally. Check if there is a PocketBase backup before generating a new key!
        final hasBackup = await enc.hasPocketBaseBackup(userId);
        if (hasBackup) {
          debugPrint('[Keys] Reinstall with server backup detected — skipping key generation to allow restore.');
          return;
        }

        // Fresh install / new registration / reinstall without backup — generate a new key pair
        final pubKeyB64 = await enc.getPublicKeyBase64();
        debugPrint('[Keys] New device/reinstall detected — uploading fresh public key.');
        await updatePublicKey(pubKeyB64);
      } else {
        // Keys already existed in secure storage. Only upload if server is missing it.
        final record = await _pb.collection('users').getOne(userId);
        if (record.getStringValue('public_key').isEmpty) {
          final pubKeyB64 = await enc.getPublicKeyBase64();
          await updatePublicKey(pubKeyB64);
        }
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

  /// Builds a unique username from an email. Enforces the users-collection
  /// `min 3` rule (pads short locals) and appends a numeric suffix until the
  /// server reports the username is free.
  Future<String> _generateUniqueUsername(String email) async {
    var base = email
        .split('@').first
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .toLowerCase();
    if (base.length < 3) base = base.padRight(3, '0');
    var candidate = base;
    var suffix = 0;
    while (true) {
      try {
        await _pb.collection('users')
            .getFirstListItem('username="$candidate"');
        // Found → taken, try the next suffix.
        suffix += 1;
        candidate = '$base$suffix';
      } on ClientException catch (e) {
        if (e.statusCode == 404) return candidate;
        rethrow;
      }
    }
  }
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
