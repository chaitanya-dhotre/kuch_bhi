import 'package:drift/drift.dart' show Value;
import 'dart:math';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/pocketbase_client.dart';
import '../../data/local/database/app_database.dart';
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
      await _cacheUserLocally(user);
      return user;
    } on ClientException catch (e) {
      throw AuthException(
        _parseErrorMessage(e),
        code: e.statusCode.toString(),
      );
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

      // Exchange Google ID token with PocketBase.
      // PocketBase 0.21.x: use authWithOAuth2Code for mobile flows.
      final authData = await _pb.collection('users').authWithOAuth2Code(
        'google',
        idToken,
        '', // code verifier — not required for implicit flow
        '', // redirect url — not required for mobile
        createData: {
          'display_name': googleUser.displayName ?? googleUser.email,
          'username': _emailToUsername(googleUser.email),
          'friend_code': _generateFriendCode(),
        },
      );

      final user = _recordToUser(authData.record!);
      await _cacheUserLocally(user);
      return user;
    } on AuthException {
      rethrow;
    } on ClientException catch (e) {
      throw AuthException(
        _parseErrorMessage(e),
        code: e.statusCode.toString(),
      );
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
      // Generate a unique friend code and verify it's not taken.
      final friendCode = await _generateUniqueFriendCode();

      // Create the PocketBase auth record.
      await _pb.collection('users').create(body: {
        'email': email,
        'password': password,
        'passwordConfirm': password,
        'display_name': displayName,
        'username': username,
        'friend_code': friendCode,
      });

      // Sign in immediately after registration.
      return signInWithEmailPassword(email: email, password: password);
    } on ClientException catch (e) {
      throw AuthException(
        _parseErrorMessage(e),
        code: e.statusCode.toString(),
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('Registration failed: $e');
    }
  }

  // ── Current user ───────────────────────────────────────────────

  @override
  Future<User?> getCurrentUser() async {
    final userId = await storage.getCurrentUserId();
    if (userId == null) return null;

    // Load from local cache first for instant response.
    final cached = await db.usersDao.getUserById(userId);
    if (cached == null) return null;

    return _tableDataToUser(cached);
  }

  // ── Sign out ───────────────────────────────────────────────────

  @override
  Future<void> signOut() async {
    pbClient.clearAuth();
    await storage.clearAll();
    // Note: we intentionally keep local Drift DB intact so the
    // user can see their history if they sign back in.
    // Full wipe only happens on deleteAccount().
  }

  // ── Delete account ─────────────────────────────────────────────

  @override
  Future<void> deleteAccount() async {
    try {
      final userId = await storage.getCurrentUserId();
      if (userId == null) return;

      // Delete the PocketBase auth record.
      // PocketBase cascade rules handle related data deletion.
      await _pb.collection('users').delete(userId);

      pbClient.clearAuth();
      await storage.clearAll();
    } on ClientException catch (e) {
      throw AuthException(_parseErrorMessage(e));
    }
  }

  // ── FCM token ──────────────────────────────────────────────────

  @override
  Future<void> updateFcmToken(String token) async {
    if (!pbClient.isAuthenticated) return;
    final userId = await storage.getCurrentUserId();
    if (userId == null) return;

    try {
      await _pb.collection('users').update(userId, body: {
        'fcm_token': token,
      });
    } catch (_) {
      // Non-critical — don't throw. Will retry on next launch.
    }
  }

  // ── Public key ─────────────────────────────────────────────────

  @override
  Future<void> updatePublicKey(String publicKeyBase64) async {
    if (!pbClient.isAuthenticated) return;
    final userId = await storage.getCurrentUserId();
    if (userId == null) return;

    await _pb.collection('users').update(userId, body: {
      'public_key': publicKeyBase64,
    });
  }

  // ── Private helpers ────────────────────────────────────────────

  /// Cache a user to local Drift DB after auth.
  Future<void> _cacheUserLocally(User user) async {
    await db.usersDao.upsertUser(UsersTableCompanion.insert(
      id: user.id,
      displayName: user.displayName,
      username: user.username,
      email: Value(user.email),
      avatarUrl: Value(user.avatarUrl),
      about: Value(user.about),
      friendCode: user.friendCode,
      publicKey: Value(user.publicKey),
      createdAt: user.createdAt,
      updatedAt: DateTime.now(),
    ));
  }

  User _recordToUser(RecordModel record) {
    return User(
      id: record.id,
      displayName: record.getStringValue('display_name'),
      username: record.getStringValue('username'),
      email: record.getStringValue('email'),
      friendCode: record.getStringValue('friend_code'),
      avatarUrl: _buildAvatarUrl(record),
      about: record.getStringValue('about').isEmpty
          ? null
          : record.getStringValue('about'),
      publicKey: record.getStringValue('public_key').isEmpty
          ? null
          : record.getStringValue('public_key'),
      isOnline: record.getBoolValue('is_online'),
      createdAt: DateTime.tryParse(record.created) ?? DateTime.now(),
    );
  }

  User _tableDataToUser(UsersTableData data) {
    return User(
      id: data.id,
      displayName: data.displayName,
      username: data.username,
      email: data.email ?? '',
      friendCode: data.friendCode,
      avatarUrl: data.avatarUrl,
      about: data.about,
      publicKey: data.publicKey,
      isOnline: data.isOnline,
      lastSeen: data.lastSeen,
      createdAt: data.createdAt,
    );
  }

  String? _buildAvatarUrl(RecordModel record) {
    final avatar = record.getStringValue('avatar');
    if (avatar.isEmpty) return null;
    return '${_pb.baseUrl}/api/files/users/${record.id}/$avatar';
  }

  String _parseErrorMessage(ClientException e) {
    try {
      final data = e.response['data'] as Map<String, dynamic>?;
      if (data != null) {
        for (final field in data.values) {
          final msg = (field as Map<String, dynamic>)['message'];
          if (msg != null) return msg.toString();
        }
      }
      final message = e.response['message'] as String?;
      return message ?? 'An error occurred. Please try again.';
    } catch (_) {
      return 'An error occurred. Please try again.';
    }
  }

  /// Generates a random 6-character uppercase alphanumeric friend code.
  String _generateFriendCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  /// Generates a friend code and verifies it's not already taken.
  Future<String> _generateUniqueFriendCode() async {
    while (true) {
      final code = _generateFriendCode();
      try {
        // If this query returns a result, the code is taken — try again.
        await _pb
            .collection('users')
            .getFirstListItem('friend_code="$code"');
        // Record found — code is taken, loop again.
      } on ClientException catch (e) {
        if (e.statusCode == 404) {
          // 404 means no record found — code is free to use.
          return code;
        }
        rethrow;
      }
    }
  }

  String _emailToUsername(String email) {
    // Generate a base username from email, strip special chars.
    return email
        .split('@')
        .first
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
        .toLowerCase();
  }
}

/// Riverpod provider. Waits for PocketBase to be ready.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final pbClientAsync = ref.watch(pocketbaseClientProvider);

  return pbClientAsync.when(
    data: (pbClient) => AuthRepositoryImpl(
      pbClient: pbClient,
      db: ref.read(appDatabaseProvider),
      storage: ref.read(secureStorageProvider),
    ),
    // While loading — return an empty impl that does nothing.
    // The authProvider handles this loading state gracefully.
    loading: () => _LoadingAuthRepository(),
    error: (e, _) => throw StateError('PocketBase failed to init: $e'),
  );
});

/// Stub repository returned while PocketBase is still initializing.
/// AuthNotifier.build() awaits the PocketBase future before calling
/// getCurrentUser(), so this stub is never actually invoked for real ops.
class _LoadingAuthRepository implements AuthRepository {
  @override Future<User> signInWithEmailPassword({required String email, required String password}) => Future.error('Not ready');
  @override Future<User> signInWithGoogle() => Future.error('Not ready');
  @override Future<User> register({required String email, required String password, required String displayName, required String username}) => Future.error('Not ready');
  @override Future<User?> getCurrentUser() async => null;
  @override Future<void> signOut() async {}
  @override Future<void> deleteAccount() async {}
  @override Future<void> updateFcmToken(String token) async {}
  @override Future<void> updatePublicKey(String publicKeyBase64) async {}
}
