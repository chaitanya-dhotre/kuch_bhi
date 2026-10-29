import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/domain/repositories/auth_repository.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';

/// Screen-test double: records each call, holds it open on [gate], then
/// publishes [next] (or AuthUnauthenticated). No repository behind it.
class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier([this.initial = const AuthUnauthenticated()]);

  final AuthState initial;
  final calls = <String>[];
  final args = <Map<String, Object?>>[];
  Completer<void>? gate;
  AuthState? next;
  GoogleAuthResult? googleResult;
  String? resetError;

  @override
  Future<AuthState> build() async => initial;

  Future<void> _run(String name, Map<String, Object?> a) async {
    calls.add(name);
    args.add(a);
    state = const AsyncData(AuthLoading());
    await gate?.future;
    state = AsyncData(next ?? const AuthUnauthenticated());
  }

  @override
  Future<void> signInWithEmailPassword(
          {required String email, required String password}) =>
      _run('signIn', {'email': email, 'password': password});

  @override
  Future<GoogleAuthResult?> signInWithGoogle() async {
    await _run('google', {});
    return googleResult;
  }

  @override
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required String username,
  }) =>
      _run('register', {
        'email': email,
        'displayName': displayName,
        'username': username,
      });

  @override
  Future<GoogleAuthResult?> registerWithGoogle({
    required String idToken,
    required String displayName,
    required String username,
    File? avatarFile,
  }) async {
    await _run('registerWithGoogle', {
      'displayName': displayName,
      'username': username,
      'avatarFile': avatarFile,
    });
    return googleResult;
  }

  @override
  Future<String?> requestPasswordReset(String email) async {
    calls.add('reset');
    args.add({'email': email});
    await gate?.future;
    return resetError;
  }

  @override
  Future<void> forgetGoogleAccount() async => calls.add('forget');

  @override
  Future<void> refreshSessionThrottled() async {}
}

/// Pumps [home] at `/` inside a router with stub pages for the auth routes.
/// [narrow] = 360dp wide at 200% text (I2).
Future<void> pumpAuth(
  WidgetTester tester,
  Widget home, {
  FakeAuthNotifier? notifier,
  bool online = true,
  bool narrow = false,
  List<GoRoute> routes = const [],
  String initial = '/',
}) async {
  if (narrow) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }
  final router = GoRouter(initialLocation: initial, routes: [
    GoRoute(path: '/', builder: (_, __) => home),
    for (final p in ['/login', '/register', '/forgot-password', '/splash'])
      GoRoute(path: p, builder: (_, __) => Text('page:$p')),
    ...routes,
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authProvider.overrideWith(() => notifier ?? FakeAuthNotifier()),
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
    ],
    child: MaterialApp.router(
      theme: warmPopLight(),
      routerConfig: router,
      builder: narrow
          ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              )
          : null,
    ),
  ));
  await tester.pump();
  await tester.pump();
}

/// C4: no accent- or error-coloured Text anywhere on screen.
void expectNoAccentOrErrorText(WidgetTester tester) {
  final t = ColorTokens.light;
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final c = w.style?.color;
    expect(c, isNot(t.accent), reason: w.data);
    expect(c, isNot(t.error), reason: w.data);
  }
}

Finder fieldWithLabel(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TextField),
    );

/// The AppButton/FilledButton etc. that holds [label].
ButtonStyleButton buttonOf(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(find
        .ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>())
        .first);
