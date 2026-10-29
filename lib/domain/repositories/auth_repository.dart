import 'dart:io';

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

  /// Fetch email + display name from a Google account for prefilling
  /// registration. Does NOT authenticate — the user still completes normal
  /// email+password registration.
  /// Returns null if the user cancels the Google sign-in flow.
  /// Throws [AuthException] on failure.
  Future<GooglePrefill?> getGooglePrefill();

  /// Full Google OAuth: authenticates against PocketBase (creating the
  /// account when it doesn't exist yet). Returns null when cancelled.
  /// [GoogleAuthResult.isNew] tells the UI whether to run onboarding.
  /// Throws [AuthException] on failure.
  Future<GoogleAuthResult?> signInWithGoogle();

  /// Step-1 of Google sign-in: fetch Google account profile without
  /// authenticating. Returns email + display name so the onboarding
  /// screen can autofill (and the user can edit) before the server
  /// creates the PocketBase account.
  /// Returns null if the user cancels the Google picker.
  /// Throws [AuthException] on failure.
  Future<GooglePrefill?> fetchGoogleProfile();

  /// Step-2 of Google sign-in: takes the Google idToken + user-confirmed
  /// display name and username, and creates the PocketBase account via
  /// the hook. On success returns the authenticated [User].
  Future<GoogleAuthResult> registerWithGoogle({
    required String idToken,
    required String displayName,
    required String username,
  });

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

  /// Throttled (30 min) background session refresh. Resume-only.
  Future<void> refreshSessionThrottled();

  /// Permanently delete the account and all associated data.
  /// This is irreversible.
  Future<void> deleteAccount();

  /// Update FCM token on the server.
  /// Called on app launch and when FCM token refreshes.
  Future<void> updateFcmToken(String token);

  /// Update the user's public encryption key on the server.
  /// Called once after key generation on first login.
  Future<void> updatePublicKey(String publicKeyBase64);

  /// Update display name, username, about and avatar for the signed-in user.
  /// Throws [UsernameTakenException] when the username is already in use.
  Future<User> updateProfile({
    required String displayName,
    required String username,
    String? about,
    File? avatarFile,
    bool clearAvatar = false,
  });

  /// Ask PocketBase to email a password-reset link (bounded at 8s).
  /// PocketBase answers the same whether or not the email has an account.
  /// Throws [AuthException] on failure.
  Future<void> requestPasswordReset(String email);

  /// Best effort: sign the Google picker out so the account chooser shows
  /// on the next Google sign-in. Never throws.
  Future<void> forgetGoogleAccount();
}

/// Lightweight data carried from a Google account into the registration form.
class GooglePrefill {
  const GooglePrefill({required this.email, this.displayName});
  final String email;
  final String? displayName;
}

/// Result of a full Google OAuth sign-in.
///
/// For an existing account, [user] is non-null and [isNew] is `false`.
/// For a brand-new account (the hook returned 404 — no PB record yet),
/// [user] is null, [isNew] is `true`, and the prefill fields
/// ([email], [displayName], [idToken]) are populated so the UI can
/// route to [GoogleOnboardingScreen] without re-triggering the
/// Google account picker.
class GoogleAuthResult {
  const GoogleAuthResult({
    required this.user,
    required this.isNew,
    this.email,
    this.displayName,
    this.idToken,
    this.photoFailed = false,
  });
  final User? user;

  /// True when PocketBase needs to create this account.
  final bool isNew;

  /// Prefill for the onboarding screen — only populated when [isNew].
  final String? email;
  final String? displayName;
  final String? idToken;

  /// Onboarding only: the account exists but the picked photo didn't upload.
  final bool photoFailed;

  bool get needsOnboarding => isNew && user == null;
}

/// Typed exception for auth failures.
class AuthException implements Exception {
  const AuthException(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String toString() => 'AuthException($code): $message';
}

/// The server rejected a profile save because the username is taken.
class UsernameTakenException implements Exception {
  const UsernameTakenException();

  @override
  String toString() => 'UsernameTakenException';
}
