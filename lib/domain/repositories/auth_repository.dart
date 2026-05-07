import '../entities/user.dart';

/// Abstract contract for authentication operations.
/// The UI and providers depend ONLY on this interface —
/// never on the concrete PocketBase implementation.
abstract class AuthRepository {

  /// Sign in with email and password.
  /// Throws [AuthException] on failure.
  Future<User> signInWithEmailPassword({
    required String email,
    required String password,
  });

  /// Sign in with Google.
  /// Uses google_sign_in package + PocketBase token exchange.
  /// Throws [AuthException] on failure.
  Future<User> signInWithGoogle();

  /// Register a new account.
  /// Auto-generates a unique friend code.
  /// Throws [AuthException] on failure.
  Future<User> register({
    required String email,
    required String password,
    required String displayName,
    required String username,
  });

  /// Returns the currently authenticated user from local cache.
  /// Returns null if not authenticated.
  Future<User?> getCurrentUser();

  /// Sign out and clear all local auth state.
  Future<void> signOut();

  /// Permanently delete the account and all associated data.
  /// This is irreversible.
  Future<void> deleteAccount();

  /// Update FCM token on the server.
  /// Called on app launch and when FCM token refreshes.
  Future<void> updateFcmToken(String token);

  /// Update the user's public encryption key on the server.
  /// Called once after key generation on first login.
  Future<void> updatePublicKey(String publicKeyBase64);
}

/// Typed exception for auth failures.
class AuthException implements Exception {
  const AuthException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => 'AuthException($code): $message';
}
