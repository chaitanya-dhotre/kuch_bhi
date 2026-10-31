import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/user.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../../infrastructure/repositories/auth_repository_impl.dart';

sealed class AuthState { const AuthState(); }
class AuthLoading        extends AuthState { const AuthLoading(); }
class AuthAuthenticated  extends AuthState {
  const AuthAuthenticated(this.user);
  final User user;
}
class AuthUnauthenticated extends AuthState { const AuthUnauthenticated(); }
class AuthError           extends AuthState {
  const AuthError(this.message, {this.field, this.code});
  final String message;

  /// D4 / F8: `'email'` or `'username'` when the error belongs on a field.
  final String? field;

  /// The repository's [AuthException.code] (e.g. `'409'`), for routing only.
  final String? code;
}

enum AuthAction { signIn, google, register, reset }

const kUsernameTakenCopy = 'That username is taken.';
const kEmailTakenCopy = 'An account with this email already exists.';
const kGoogleAccountExistsCopy =
    'This Google account already has a Kuch Bhi account. Sign in instead.';

/// G1: the only failure copy auth screens show. Server text never reaches
/// the user; the detail goes to debugPrint at the call site.
String authErrorMessage(Object error, AuthAction action) {
  final code = error is AuthException ? error.code : null;
  if (error is TimeoutException ||
      error is SocketException ||
      code == 'timeout' ||
      code == '0' ||
      code == '503') { // 503: the google-auth hook can't reach Google
    return "Can't reach the server. Check your connection and try again.";
  }
  return switch (action) {
    AuthAction.signIn when code == '400' => 'Wrong email, username or password.',
    AuthAction.google when code == '409' => kGoogleAccountExistsCopy,
    AuthAction.google => "Google sign-in didn't work. Try again.",
    AuthAction.signIn => "Couldn't sign you in. Try again.",
    AuthAction.register => "Couldn't create your account. Try again.",
    AuthAction.reset => "Couldn't send the link. Try again.",
  };
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// G2: user copy from G1 (or the field copy); the detail to the log only.
  void _fail(Object error, AuthAction action) {
    debugPrint('[Auth] ${action.name} failed: $error');
    state = AsyncData(switch (error) {
      UsernameTakenException() =>
        const AuthError(kUsernameTakenCopy, field: 'username'),
      AuthException(code: 'email_taken') =>
        const AuthError(kEmailTakenCopy, field: 'email'),
      AuthException(:final code) =>
        AuthError(authErrorMessage(error, action), code: code),
      _ => AuthError(authErrorMessage(error, action)),
    });
  }

  @override
  Future<AuthState> build() async {
    // PocketBase is pre-initialized in main() before runApp.
    // No need to watch/await the client here — just check local cache.
    final user = await _repo.getCurrentUser();
    if (user != null) return AuthAuthenticated(user);
    return const AuthUnauthenticated();
  }

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    state = const AsyncData(AuthLoading());
    try {
      final user = await _repo.signInWithEmailPassword(
        email: email,
        password: password,
      );
      state = AsyncData(AuthAuthenticated(user));
    } catch (e) {
      _fail(e, AuthAction.signIn);
    }
  }

  /// Step-2 of Google sign-in: takes the Google idToken + user-confirmed
  /// display name and username, and creates the PocketBase account via
  /// the hook. On success returns the authenticated [User].
  ///
  /// F5: a picked photo uploads HERE, before state turns authenticated —
  /// the redirect replaces the onboarding screen the moment it does. It goes
  /// through updateProfile (EXIF stripped). A failed photo still signs in,
  /// with [GoogleAuthResult.photoFailed].
  Future<GoogleAuthResult?> registerWithGoogle({
    required String idToken,
    required String displayName,
    required String username,
    File? avatarFile,
  }) async {
    state = const AsyncData(AuthLoading());
    try {
      final result = await _repo.registerWithGoogle(
        idToken: idToken,
        displayName: displayName,
        username: username,
      );
      var user = result.user!;
      var photoFailed = false;
      if (avatarFile != null) {
        try {
          user = await _repo
              .updateProfile(
                // What the hook saved, never re-sent client values.
                displayName: user.displayName,
                username: user.username,
                about: '',
                avatarFile: avatarFile,
              )
              .timeout(const Duration(seconds: 30));
        } catch (e) {
          debugPrint('[Auth] onboarding photo upload failed: $e');
          photoFailed = true;
        }
      }
      state = AsyncData(AuthAuthenticated(user));
      return GoogleAuthResult(user: user, isNew: true, photoFailed: photoFailed);
    } catch (e) {
      _fail(e, AuthAction.google);
      return null;
    }
  }

  /// Full Google OAuth:
  /// - Existing account → returns [GoogleAuthResult] with `user != null`
  ///   and transitions to [AuthAuthenticated]. Caller should send the
  ///   splash so [encryptionSyncProvider] can route to backup-pin or home.
  /// - New account → returns [GoogleAuthResult] with `user == null`,
  ///   `isNew = true`, and prefill (`email`, `displayName`, `idToken`)
  ///   populated. Caller should send to `/google-onboarding`.
  Future<GoogleAuthResult?> signInWithGoogle() async {
    state = const AsyncData(AuthLoading());
    try {
      final result = await _repo.signInWithGoogle();
      if (result == null) {
        // User cancelled the Google picker.
        state = const AsyncData(AuthUnauthenticated());
        return null;
      }
      if (result.needsOnboarding) {
        // Don't authenticate yet — onboarding will create the account
        // and then call registerWithGoogle() which sets AuthAuthenticated.
        state = const AsyncData(AuthUnauthenticated());
        return result;
      }
      // Existing user authenticated successfully.
      state = AsyncData(AuthAuthenticated(result.user!));
      return result;
    } catch (e) {
      _fail(e, AuthAction.google);
      return null;
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required String username,
  }) async {
    state = const AsyncData(AuthLoading());
    try {
      final user = await _repo.register(
        email: email,
        password: password,
        displayName: displayName,
        username: username,
      );
      state = AsyncData(AuthAuthenticated(user));
    } catch (e) {
      _fail(e, AuthAction.register);
    }
  }

  /// E1: returns the G1 copy on failure, null when the link was requested.
  /// Leaves auth state alone (the user is signed out either way).
  Future<String?> requestPasswordReset(String email) async {
    try {
      await _repo.requestPasswordReset(email);
      return null;
    } catch (e) {
      debugPrint('[Auth] reset failed: $e');
      return authErrorMessage(e, AuthAction.reset);
    }
  }

  /// F7: best effort; the next Google tap shows the account chooser.
  Future<void> forgetGoogleAccount() => _repo.forgetGoogleAccount();

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AsyncData(AuthUnauthenticated());
  }

  /// Saves the profile and publishes the saved user straight to state.
  /// Never invalidates: a rebuild re-runs getCurrentUser (stale cache,
  /// reinstall branch that can rotate keys).
  Future<void> updateProfile({
    required String displayName,
    required String username,
    String? about,
    File? avatarFile,
    bool clearAvatar = false,
  }) async {
    final user = await _repo.updateProfile(
      displayName: displayName,
      username: username,
      about: about,
      avatarFile: avatarFile,
      clearAvatar: clearAvatar,
    );
    state = AsyncData(AuthAuthenticated(user));
  }

  /// Throttled session refresh — called from app resume only, never from
  /// navigation (see refreshSessionThrottled in the auth repository).
  Future<void> refreshSessionThrottled() => _repo.refreshSessionThrottled();

  void clearError() {
    if (state.value is AuthError) {
      state = const AsyncData(AuthUnauthenticated());
    }
  }
}

final authProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);