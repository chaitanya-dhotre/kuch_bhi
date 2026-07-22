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

  /// Fetches email + display name from a Google account for prefilling the
  /// registration form. Does NOT authenticate — the caller navigates to the
  /// register screen with the returned prefill data.
  /// Returns null if the user cancelled the Google sign-in flow.
  Future<GooglePrefill?> getGooglePrefill() async {
    try {
      return await _repo.getGooglePrefill();
    } on AuthException catch (e) {
      state = AsyncData(AuthError(e.message));
      return null;
    } catch (e) {
      state = AsyncData(AuthError('Google sign in failed: $e'));
      return null;
    }
  }

  /// Full Google OAuth. On success sets AuthAuthenticated. Returns the result
  /// so the caller can send brand-new accounts through onboarding.
  Future<GoogleAuthResult?> signInWithGoogle() async {
    state = const AsyncData(AuthLoading());
    try {
      final result = await _repo.signInWithGoogle();
      if (result == null) {
        // Cancelled — restore unauthenticated state.
        state = const AsyncData(AuthUnauthenticated());
        return null;
      }
      state = AsyncData(AuthAuthenticated(result.user));
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

  void clearError() {
    if (state.value is AuthError) {
      state = const AsyncData(AuthUnauthenticated());
    }
  }
}

final authProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
