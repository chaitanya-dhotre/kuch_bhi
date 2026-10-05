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
  const AuthError(this.message);
  final String message;
}

class AuthNotifier extends AsyncNotifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

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
    } on AuthException catch (e) {
      state = AsyncData(AuthError(e.message));
    } catch (e) {
      state = AsyncData(AuthError('Unexpected error: $e'));
    }
  }

  /// Step-1 of Google sign-in: fetch Google account profile without
  /// authenticating. Returns email + display name so the onboarding
  /// screen can autofill (and the user can edit) before the server
  /// creates the PocketBase account.
  /// Returns null if the user cancels the Google picker.
  /// Throws [AuthException] on failure.
  Future<GooglePrefill?> fetchGoogleProfile() async {
    try {
      return await _repo.fetchGoogleProfile();
    } on AuthException catch (e) {
      state = AsyncData(AuthError(e.message));
      return null;
    } catch (e) {
      state = AsyncData(AuthError('Google sign in failed: $e'));
      return null;
    }
  }

  /// Step-2 of Google sign-in: takes the Google idToken + user-confirmed
  /// display name and username, and creates the PocketBase account via
  /// the hook. On success returns the authenticated [User].
  Future<GoogleAuthResult?> registerWithGoogle({
    required String idToken,
    required String displayName,
    required String username,
  }) async {
    state = const AsyncData(AuthLoading());
    try {
      final result = await _repo.registerWithGoogle(
        idToken: idToken,
        displayName: displayName,
        username: username,
      );
      if (result == null) {
        state = const AsyncData(AuthUnauthenticated());
        return null;
      }
      // Existing onboarding callers never had a value (function was
      // declared non-nullable in early designs). Make the user explicit:
      final user = result.user!;
      state = AsyncData(AuthAuthenticated(user));
      return result;
    } on AuthException catch (e) {
      state = AsyncData(AuthError(e.message));
      return null;
    } catch (e) {
      state = AsyncData(AuthError('Google sign in failed: $e'));
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
    } on AuthException catch (e) {
      state = AsyncData(AuthError(e.message));
      return null;
    } catch (e) {
      state = AsyncData(AuthError('Google sign in failed: $e'));
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
    } on AuthException catch (e) {
      state = AsyncData(AuthError(e.message));
    } catch (e) {
      state = AsyncData(AuthError('Registration failed: $e'));
    }
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const AsyncData(AuthUnauthenticated());
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