import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/domain/repositories/auth_repository.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';

const _offline = "Can't reach the server. Check your connection and try again.";

void main() {
  test('timeout, status 0 and socket errors read as offline for every action',
      () {
    for (final action in AuthAction.values) {
      for (final e in <Object>[
        TimeoutException('x'),
        const AuthException('t', code: 'timeout'),
        const AuthException('z', code: '0'),
        const AuthException('google down', code: '503'),
        const SocketException('down'),
      ]) {
        expect(authErrorMessage(e, action), _offline, reason: '$action $e');
      }
    }
  });

  test('each G1 row', () {
    expect(authErrorMessage(const AuthException('bad', code: '400'),
        AuthAction.signIn), 'Wrong email, username or password.');
    expect(authErrorMessage(const AuthException('x', code: '500'),
        AuthAction.google), "Google sign-in didn't work. Try again.");
    expect(authErrorMessage(const AuthException('forged', code: '401'),
        AuthAction.google), "Google sign-in didn't work. Try again.");
    expect(authErrorMessage(const AuthException('x', code: '409'),
        AuthAction.google), kGoogleAccountExistsCopy);
    expect(authErrorMessage(StateError('boom'), AuthAction.signIn),
        "Couldn't sign you in. Try again.");
    expect(authErrorMessage(const AuthException('x', code: '400'),
        AuthAction.register), "Couldn't create your account. Try again.");
    expect(authErrorMessage(const AuthException('x', code: '400'),
        AuthAction.reset), "Couldn't send the link. Try again.");
  });

  test('never leaks server text, exception names or interpolation', () {
    const leak = AuthException('Failed to authenticate. SECRET', code: '403');
    for (final action in AuthAction.values) {
      for (final e in <Object>[leak, StateError('SECRET'), Exception('SECRET')]) {
        final m = authErrorMessage(e, action);
        expect(m, isNot(contains('SECRET')));
        expect(m, isNot(contains('Exception')));
        expect(m, isNot(contains(r'$')));
      }
    }
  });
}
