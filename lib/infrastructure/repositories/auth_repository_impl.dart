import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
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

/// PB `users.update` body for a profile save: exactly these fields, never
/// `public_key` / `friend_code`. `avatar: null` clears the photo.
Map<String, dynamic> profileUpdateBody({
  required String displayName,
  required String username,
  String? about,
  bool clearAvatar = false,
}) =>
    {
      'display_name': displayName,
      'username': username.toLowerCase(),
      'about': about ?? '',
      if (clearAvatar) 'avatar': null,
    };

/// True only for HTTP 400 `validation_not_unique` on field `username`.
bool isUsernameTaken(ClientException error) {
  if (error.statusCode != 400) return false;
  final data = error.response['data'];
  if (data is! Map) return false;
  final fieldError = data['username'];
  return fieldError is Map && fieldError['code'] == 'validation_not_unique';
}

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
  Future<GooglePrefill?> fetchGoogleProfile() async {
    try {
      final googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null; // user cancelled
      return GooglePrefill(
        email: googleUser.email,
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
      // Try to authenticate existing user with Google idToken.
      final response = await http.post(
        Uri.parse('${_pb.baseUrl}/api/hooks/google-auth'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'idToken': idToken, 'action': 'signin'}),
      );
      if (response.statusCode == 404) {
        // No PocketBase record yet — caller (UI) must run onboarding.
        // Return the email / displayName / idToken so the onboarding
        // screen doesn't have to re-trigger the Google picker.
        return GoogleAuthResult(
          user: null,
          isNew: true,
          email: googleUser.email,
          displayName: googleUser.displayName,
          idToken: idToken,
        );
      }
      if (response.statusCode != 200) {
        final body = json.decode(response.body);
        throw AuthException(body['message'] ?? 'Google auth failed',
            code: response.statusCode.toString());
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      final token = data['token'] as String?;
      final recordData = data['record'] as Map<String, dynamic>?;
      if (token == null || recordData == null) {
        throw const AuthException('Invalid Google auth response from server');
      }
      final record = RecordModel.fromJson(recordData);
      _pb.authStore.save(token, record);
      final user = _recordToUser(record);
      await _saveSession(user);
      return GoogleAuthResult(user: user, isNew: false);
    } on AuthException {
      rethrow;
    } on ClientException catch (e) {
      throw AuthException(_parseErrorMessage(e),
          code: e.statusCode.toString());
    } catch (e) {
      debugPrint('[Auth] Google sign-in FAILED: $e');
      throw AuthException('Google sign in failed: $e');
    }
  }

  @override
  Future<GoogleAuthResult> registerWithGoogle({
    required String idToken,
    required String displayName,
    required String username,
  }) async {
    try {
      // Create account via hook
      final response = await http.post(
        Uri.parse('${_pb.baseUrl}/api/hooks/google-auth'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'idToken': idToken,
          'action': 'register',
          'display_name': displayName,
          'username': username,
        }),
      );
      if (response.statusCode != 200) {
        final body = json.decode(response.body);
        throw AuthException(body['message'] ?? 'Google registration failed',
            code: response.statusCode.toString());
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      final token = data['token'] as String?;
      final recordData = data['record'] as Map<String, dynamic>?;
      if (token == null || recordData == null) {
        throw const AuthException('Invalid Google auth response from server');
      }
      final record = RecordModel.fromJson(recordData);
      _pb.authStore.save(token, record);
      final user = _recordToUser(record);
      await _saveSession(user);
      return GoogleAuthResult(user: user, isNew: true);
    } on AuthException {
      rethrow;
    } on ClientException catch (e) {
      throw AuthException(_parseErrorMessage(e),
          code: e.statusCode.toString());
    } catch (e) {
      debugPrint('[Auth] Google registration FAILED: $e');
      throw AuthException('Google registration failed: $e');
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
        debugPrint('[Auth] Restoring token from Drift');
        _pb.authStore.save(driftToken, null);
      }
      if (!pbClient.isAuthenticated) {
        debugPrint('[Auth] Still not authenticated after drift token restore');
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
      // NOTE: no _backgroundRefresh() here — navigation re-runs this path,
      // and every refresh rotated the token (authStore.onChange → full SSE
      // rebuild, ~54x/25min). Refresh is resume-only, via
      // refreshSessionThrottled().
      return _tableDataToUser(cached);
    }

    // No local cache at all — validate with the server once.
    try {
      debugPrint('[Auth] No cache, calling authRefresh...');
      final authData = await _pb.collection('users').authRefresh();
      debugPrint('[Auth] authRefresh succeeded: ${authData.record?.id}');
      final user = _recordToUser(authData.record!);
      await _saveSession(user);
      return user;
    } on ClientException catch (e) {
      debugPrint('[Auth] No cache and authRefresh failed (${e.statusCode}): $e');
    } catch (e) {
      debugPrint('[Auth] No cache and authRefresh failed: $e');
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

  DateTime? _lastAuthRefresh;
  static const _authRefreshInterval = Duration(minutes: 30);

  /// Session refresh, throttled to once per 30 minutes. Called from app
  /// RESUME only — never from navigation (every navigation used to
  /// authRefresh, rotate the token, and rebuild all SSE subscriptions).
  @override
  Future<void> refreshSessionThrottled() async {
    final now = DateTime.now();
    if (_lastAuthRefresh != null &&
        now.difference(_lastAuthRefresh!) < _authRefreshInterval) {
      return;
    }
    _lastAuthRefresh = now;
    _backgroundRefresh();
  }

  // ── Sign out ───────────────────────────────────────────────────

  @override
  Future<void> signOut() async {
    await _fcmTokenSubscription?.cancel();
    _fcmTokenSubscription = null;
    pbClient.clearAuth();
    // B1: the next sign-in must start CLEAN — wipe every table (messages,
    // conversations, members, receipts, starred/deleted sync state) and all
    // session secrets (auth token, group/contact key caches). The keypair
    // stays: with the DB wiped it opens nothing, and it keeps the same
    // account's re-login history readable. Late in-flight writes from
    // timers fail harmlessly against empty tables; the router has already
    // redirected to splash.
    try {
      await storage.clearSession();
    } catch (e) {
      debugPrint('[Auth] secure storage wipe failed: $e');
    }
    for (final table in db.allTables) {
      await db.delete(table).go();
    }
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

  @override
  Future<User> updateProfile({
    required String displayName,
    required String username,
    String? about,
    File? avatarFile,
    bool clearAvatar = false,
  }) async {
    // A cold start restores the token with a null record (getCurrentUser),
    // so fall back to the cached signed-in id.
    final id = _pb.authStore.record?.id ??
        await db.settingsDao.getSetting(AppSettingsKeys.currentUserId);
    if (id == null || id.isEmpty) throw StateError('No signed-in user');
    final body = profileUpdateBody(
      displayName: displayName,
      username: username,
      about: about,
      clearAvatar: clearAvatar,
    );
    try {
      final record = await _pb.collection('users').update(
        id,
        body: body,
        files: [
          if (avatarFile != null)
            http.MultipartFile.fromBytes(
              'avatar',
              await _avatarJpegWithoutExif(avatarFile),
              filename: 'avatar.jpg',
            ),
        ],
      );
      final user = _recordToUser(record);
      await _cacheUserLocally(user);
      return user;
    } on ClientException catch (e) {
      if (isUsernameTaken(e)) throw const UsernameTakenException();
      rethrow;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────

  /// Re-encodes a picked photo as JPEG with NO metadata: image_picker's resize
  /// keeps EXIF, GPS included, and every friend can download the avatar.
  /// Never falls back to the original bytes.
  Future<Uint8List> _avatarJpegWithoutExif(File file) async {
    final bytes = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      minWidth: 1024,
      minHeight: 1024,
      quality: 80,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (bytes == null) throw StateError('Avatar re-encode failed');
    return bytes;
  }

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

      // One-time migration: claim the pre-scoping GLOBAL keypair — but only
      // if its public half matches THIS account's published key (the global
      // slot may belong to a different account that used the device before
      // per-user slots existed; if it doesn't match, leave it alone for its
      // owner to claim on their next login).
      if (await storage.getPrivateKey() == null) {
        try {
          final legacyPriv = await storage.getLegacyPrivateKey();
          final legacyPub  = await storage.getLegacyLocalPublicKey();
          if (legacyPriv != null && legacyPub != null) {
            final rec = await _pb.collection('users').getOne(userId);
            final serverPub = rec.getStringValue('public_key');
            if (serverPub.isNotEmpty && legacyPub == serverPub) {
              await storage.savePrivateKey(legacyPriv);
              await storage.saveLocalPublicKey(legacyPub);
              debugPrint('[Keys] Adopted legacy keypair for $userId.');
            }
          }
        } catch (e) {
          debugPrint('[Keys] legacy adoption failed: $e');
        }
      }

      // Check if secure storage already had a key pair before this session.
      // If both keys exist in storage, the key pair was NOT freshly generated.
      final existingPriv = await storage.getPrivateKey();
      final existingPub  = await storage.getLocalPublicKey();
      var hadExistingKeys = existingPriv != null && existingPub != null;

      // Belt-over-braces: scoped slots make cross-account confusion
      // impossible, but a mismatch against the server's published key means
      // THIS account rotated keys elsewhere — our slot is stale, drop and
      // restore-or-generate below.
      if (hadExistingKeys) {
        try {
          final record = await _pb.collection('users').getOne(userId);
          final serverPub = record.getStringValue('public_key');
          if (serverPub.isNotEmpty && existingPub != serverPub) {
            debugPrint(
                '[Keys] Local keypair belongs to another account — dropping it.');
            await storage.deleteKeyPair();
            hadExistingKeys = false;
          }
        } catch (e) {
          debugPrint('[Keys] pubkey mismatch check failed: $e');
        }
      }

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
