import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/router/app_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/repositories/auth_repository.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/providers/encryption_sync_provider.dart';
import 'package:kuch_bhi/features/auth/screens/google_onboarding_screen.dart';
import 'package:kuch_bhi/features/auth/screens/login_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';

import 'auth_harness.dart';

/// The REAL router: an AuthError on onboarding notifies its refresh
/// listenable, and the onboarding route is rebuilt from `extra`.
Future<ProviderContainer> _pump(WidgetTester tester, FakeAuthNotifier n) async {
  final c = ProviderContainer(overrides: [
    authProvider.overrideWith(() => n),
    encryptionSyncProvider
        .overrideWith((ref) async => EncryptionSyncStatus.keyOk),
    isOnlineProvider.overrideWith((ref) => Stream.value(true)),
  ]);
  addTearDown(c.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(
        theme: warmPopLight(), routerConfig: c.read(appRouterProvider)),
  ));
  await tester.pump();
  c.read(appRouterProvider).go(AppRoutes.googleOnboarding,
      extra: const GoogleAuthResult(
          user: null,
          isNew: true,
          email: 'ichigo@x.y',
          displayName: 'Ichigo',
          idToken: 't'));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('taken username from the hook: field error, no red screen, '
      'still on onboarding', (tester) async {
    final n = FakeAuthNotifier()
      ..next = const AuthError(kUsernameTakenCopy, field: 'username');
    await _pump(tester, n);
    expect(find.byType(GoogleOnboardingScreen), findsOneWidget);
    final create = find.descendant(
        of: find.bySubtype<ButtonStyleButton>(),
        matching: find.text('Create account'));
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byType(GoogleOnboardingScreen), findsOneWidget);
    expect(find.text('That username is taken.'), findsOneWidget);
  });

  testWidgets('onboarding without extra (process death) shows Login',
      (tester) async {
    final n = FakeAuthNotifier();
    final c = await _pump(tester, n);
    c.read(appRouterProvider).go(AppRoutes.googleOnboarding);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
