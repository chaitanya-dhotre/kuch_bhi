// Calm-rest spec, part 2 test gates 8–9, plus the A7 one-clock check for
// Profile and About and the C3 copy tick.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/profile/screens/profile_screen.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:kuch_bhi/features/settings/providers/notification_status_provider.dart';
import 'package:kuch_bhi/features/settings/providers/theme_provider.dart';
import 'package:kuch_bhi/features/settings/screens/about_screen.dart';
import 'package:kuch_bhi/features/settings/screens/settings_screen.dart';
import 'package:kuch_bhi/infrastructure/repositories/auth_repository_impl.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../fakes/fake_auth_repository.dart';
import '../mascot/capy_test.dart' show FakeSource;
import 'package:kuch_bhi/features/mascot/capy.dart';

class _PendingAuth extends AuthNotifier {
  @override
  Future<AuthState> build() => Completer<AuthState>().future;
}

/// Every Skeleton on screen has exactly one SkeletonGroup above it, and
/// they all share the same one.
void _oneClock(WidgetTester tester) {
  final blocks = find.byType(Skeleton);
  expect(blocks, findsWidgets);
  final groups = <Element>{};
  for (final e in blocks.evaluate()) {
    final above = <Element>[];
    e.visitAncestorElements((a) {
      if (a.widget is SkeletonGroup) above.add(a);
      return true;
    });
    expect(above, hasLength(1));
    groups.add(above.single);
  }
  expect(groups, hasLength(1));
}

void main() {
  test('gate 8: the app cross-fades a theme change over motionBase', () {
    // Source check: mounting the whole app needs every service provider.
    final src = File('lib/app.dart').readAsStringSync();
    expect(src, contains('themeAnimationDuration: WarmPopTokens.motionBase'));
    expect(src, contains('themeAnimationCurve:    WarmPopTokens.curveMove'));
  });

  testWidgets('gate 9: no Settings row overflows at 200 % text on 360 dp',
      (tester) async {
    // Tall enough that the whole list is built.
    await tester.binding.setSurfaceSize(const Size(360, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final theme in [warmPopLight(), warmPopDark(amoled: true)]) {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const SettingsScreen()),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          themeModeProvider
              .overrideWith((ref) => Stream.value(AppThemeMode.amoled)),
          fontFamilyProvider
              .overrideWith((ref) => Stream.value(AppFont.system)),
          notificationsEnabledProvider.overrideWith((ref) async => true),
        ],
        child: MaterialApp.router(
          theme: theme,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('App lock'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('Profile placeholders share one SkeletonGroup', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(fakeUser())),
        authProvider.overrideWith(_PendingAuth.new),
      ],
      child: MaterialApp(theme: warmPopLight(), home: const ProfileScreen()),
    ));
    await tester.pump();
    _oneClock(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('About placeholder has one SkeletonGroup', (tester) async {
    CapyLoader.debugSource = FakeSource();
    addTearDown(() => CapyLoader.debugSource = null);
    PackageInfo.setMockInitialValues(
      appName: 'Kuch Bhi',
      packageName: 'com.chai.kuch_bhi',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    await tester.pumpWidget(
        MaterialApp(theme: warmPopLight(), home: const AboutScreen()));
    // First frame: the version future has not resolved yet.
    _oneClock(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('C3: copy turns into a tick for 1.5 s', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ProfileScreen()),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(fakeUser())),
      ],
      child: MaterialApp.router(theme: warmPopLight(), routerConfig: router),
    ));
    await tester.pump();
    await tester.pump();
    final copyBtn = find.byTooltip('Copy friend code');
    Finder icon(IconData d) =>
        find.descendant(of: copyBtn, matching: find.byIcon(d));
    expect(icon(Icons.copy_outlined), findsOneWidget);
    await tester.tap(copyBtn);
    await tester.pumpAndSettle();
    expect(icon(Icons.check), findsOneWidget);
    expect(icon(Icons.copy_outlined), findsNothing);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(icon(Icons.copy_outlined), findsOneWidget);
    expect(icon(Icons.check), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
