import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/auth_repository.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/infrastructure/repositories/auth_repository_impl.dart';

import '../fakes/fake_auth_repository.dart';

/// Signed-out notifier over a [FakeAuthRepository]; every state is logged.
Future<(ProviderContainer, FakeAuthRepository, List<AuthState?>)> _setUp(
    {Future<User> Function()? onUpdate}) async {
  final repo = _SignedOutRepo(fakeUser(displayName: 'Hook', username: 'hook'))
    ..onUpdateProfile = onUpdate;
  final c = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repo)]);
  await c.read(authProvider.future);
  final states = <AuthState?>[];
  c.listen(authProvider, (_, next) => states.add(next.valueOrNull));
  return (c, repo, states);
}

class _SignedOutRepo extends FakeAuthRepository {
  _SignedOutRepo(super.user);
  @override
  Future<User?> getCurrentUser() async => null;
}

final _photo = File('photo.jpg');

Future<GoogleAuthResult?> _register(ProviderContainer c, {File? photo}) =>
    c.read(authProvider.notifier).registerWithGoogle(
        idToken: 't', displayName: 'Avni', username: 'avni', avatarFile: photo);

void main() {
  test('photo success: the published user is the updated one, uploaded '
      'before the state turns authenticated', () async {
    late List<AuthState?> states;
    final (c, repo, s) = await _setUp(onUpdate: () async {
      // F5: still not signed in while the photo uploads.
      expect(states.whereType<AuthAuthenticated>(), isEmpty);
      return fakeUser(displayName: 'Avni', avatarUrl: 'https://x/a.jpg');
    });
    states = s;
    addTearDown(c.dispose);
    final r = await _register(c, photo: _photo);
    expect(repo.updateProfileCalls, 1);
    expect(repo.lastAvatarFile, _photo);
    expect(r!.photoFailed, isFalse);
    final last = c.read(authProvider).value as AuthAuthenticated;
    expect(last.user.avatarUrl, 'https://x/a.jpg');
    expect(states.whereType<AuthAuthenticated>().length, 1);
  });

  test('photo throws: still signed in with the hook user, photoFailed',
      () async {
    final (c, _, _) = await _setUp(onUpdate: () async => throw StateError('x'));
    addTearDown(c.dispose);
    final r = await _register(c, photo: _photo);
    expect(r!.photoFailed, isTrue);
    expect((c.read(authProvider).value as AuthAuthenticated).user.displayName,
        'Hook');
  });

  testWidgets('photo hangs past 30s: still signed in, photoFailed',
      (tester) async {
    final (c, _, _) = await _setUp(onUpdate: () => Completer<User>().future);
    addTearDown(c.dispose);
    GoogleAuthResult? r;
    unawaited(_register(c, photo: _photo).then((v) => r = v));
    await tester.pump(const Duration(seconds: 29));
    expect(r, isNull);
    expect(c.read(authProvider).value, isA<AuthLoading>());
    await tester.pump(const Duration(seconds: 2));
    expect(r!.photoFailed, isTrue);
    expect(c.read(authProvider).value, isA<AuthAuthenticated>());
  });

  test('no photo: no profile call', () async {
    final (c, repo, _) = await _setUp();
    addTearDown(c.dispose);
    final r = await _register(c);
    expect(repo.updateProfileCalls, 0);
    expect(r!.photoFailed, isFalse);
  });

  test('hook failures map to G1 / field errors, never server text', () async {
    final (c, repo, _) = await _setUp();
    addTearDown(c.dispose);
    repo.onRegisterWithGoogle =
        () async => throw const AuthException('GAuth: raw db error', code: '500');
    expect(await _register(c), isNull);
    var s = c.read(authProvider).value as AuthError;
    expect(s.message, "Google sign-in didn't work. Try again.");
    repo.onRegisterWithGoogle = () async => throw const UsernameTakenException();
    await _register(c);
    s = c.read(authProvider).value as AuthError;
    expect((s.message, s.field), (kUsernameTakenCopy, 'username'));
    repo.onRegisterWithGoogle =
        () async => throw const AuthException('exists', code: '409');
    await _register(c);
    s = c.read(authProvider).value as AuthError;
    expect((s.message, s.code), (kGoogleAccountExistsCopy, '409'));
  });

  test('the photo step re-sends what the hook saved, not typed values',
      () async {
    final (c, _, _) = await _setUp();
    addTearDown(c.dispose);
    await _register(c, photo: _photo); // typed: Avni / avni
    final u = (c.read(authProvider).value as AuthAuthenticated).user;
    expect((u.displayName, u.username), ('Hook', 'hook'));
  });
}
