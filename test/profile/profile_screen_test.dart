import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/core/router/app_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/core/widgets/app_avatar.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/profile/screens/profile_screen.dart';
import 'package:kuch_bhi/infrastructure/repositories/auth_repository_impl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../fakes/fake_auth_repository.dart';

class _PendingAuth extends AuthNotifier {
  @override
  Future<AuthState> build() => Completer<AuthState>().future;
}

Future<FakeAuthRepository> _pump(
  WidgetTester tester, {
  User? user,
  bool pending = false,
}) async {
  final repo = FakeAuthRepository(user ?? fakeUser());
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const ProfileScreen()),
    GoRoute(
        path: AppRoutes.editProfile,
        builder: (_, __) => const Text('edit-page')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      if (pending) authProvider.overrideWith(_PendingAuth.new),
    ],
    child: MaterialApp.router(theme: warmPopLight(), routerConfig: router),
  ));
  await tester.pump();
  await tester.pump();
  return repo;
}

void main() {
  testWidgets('null user renders a skeleton, no spinner', (tester) async {
    await _pump(tester, pending: true);
    expect(find.byType(Skeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Profile'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('avatarUrl is the photo; initials stay underneath as fallback',
      (tester) async {
    await _pump(tester, user: fakeUser(avatarUrl: 'https://x.test/a.png'));
    final avatar = tester.widget<AppAvatar>(find.byType(AppAvatar));
    expect(avatar.url, 'https://x.test/a.png');
    final circle = tester.widget<CircleAvatar>(
      find.descendant(
          of: find.byType(AppAvatar), matching: find.byType(CircleAvatar)),
    );
    expect(circle.foregroundImage, isNotNull);
    // Device bug 2026-10-29: a photo that 404s left an empty disc.
    expect(find.text('A'), findsOneWidget);
    tester.takeException(); // network image cannot load in tests
  });

  testWidgets('app bar sits on the page colour, not a separate band',
      (tester) async {
    await _pump(tester, user: fakeUser());
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    final bar = tester.widget<AppBar>(find.byType(AppBar));
    expect(bar.backgroundColor, scaffold.backgroundColor);
    expect(bar.scrolledUnderElevation, 0);
  });

  testWidgets('empty display name does not crash, initials are ?',
      (tester) async {
    await _pump(tester, user: fakeUser(displayName: ''));
    expect(tester.takeException(), isNull);
    expect(find.text('?'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
  });

  testWidgets('about shows when non-empty', (tester) async {
    await _pump(tester, user: fakeUser(about: 'line about me'));
    expect(find.text('line about me'), findsOneWidget);
  });

  testWidgets('about is absent when empty', (tester) async {
    await _pump(tester);
    expect(find.text('line about me'), findsNothing);
    expect(find.byWidgetPredicate((w) => w is Text && w.maxLines == 4),
        findsNothing);
  });

  testWidgets('Edit profile pushes /edit-profile', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.text('edit-page'), findsOneWidget);
  });

  testWidgets('copy toasts Friend code copied', (tester) async {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await _pump(tester);
    expect(find.text('YOUR FRIEND CODE'), findsOneWidget);
    await tester.tap(find.byTooltip('Copy friend code'));
    await tester.pump();
    expect(find.text('Friend code copied'), findsOneWidget);
  });

  testWidgets('QR eyes and modules are ink', (tester) async {
    await _pump(tester);
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.eyeStyle.color, WarmPopTokens.ink);
    expect(qr.dataModuleStyle.color, WarmPopTokens.ink);
    expect(find.text('Scan to add me on Kuch Bhi'), findsOneWidget);
  });

  testWidgets('Sign out: Cancel does not sign out, confirm does once',
      (tester) async {
    final repo = await _pump(tester);
    await tester.scrollUntilVisible(find.text('Sign out'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.signOutCalls, 0);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Sign out')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.signOutCalls, 1);
    await tester.pumpWidget(const SizedBox()); // signed-out skeleton shimmers
  });

  testWidgets('no accent- or error-coloured Text on the screen',
      (tester) async {
    await _pump(tester, user: fakeUser(about: 'hi'));
    final t = ColorTokens.light;
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      final c = w.style?.color;
      expect(c, isNot(t.accent), reason: w.data);
      expect(c, isNot(t.error), reason: w.data);
    }
  });
}
