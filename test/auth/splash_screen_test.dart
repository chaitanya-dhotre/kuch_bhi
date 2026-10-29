import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/core/widgets/app_logo_tile.dart';
import 'package:kuch_bhi/core/widgets/busy_spinner.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/screens/splash_screen.dart';

import 'auth_harness.dart';

/// Auth that never resolves: the splash stays up.
class _Hanging extends FakeAuthNotifier {
  @override
  Future<AuthState> build() => Completer<AuthState>().future;
}

void main() {
  testWidgets('logo + name on the page colour; spinner only after 1s',
      (tester) async {
    await pumpAuth(tester, const SplashScreen(), notifier: _Hanging());
    expect(find.byType(AppLogoTile), findsOneWidget);
    expect(find.text('Kuch Bhi'), findsOneWidget);
    expect(find.byType(BusySpinner), findsNothing);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        ColorTokens.light.bg);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(BusySpinner), findsOneWidget);
  });

  testWidgets('signed out goes to /login', (tester) async {
    await pumpAuth(tester, const SplashScreen(), initial: '/');
    await tester.pumpAndSettle();
    expect(find.text('page:/login'), findsOneWidget);
  });

  testWidgets('360dp x 200% text: no overflow', (tester) async {
    await pumpAuth(tester, const SplashScreen(),
        notifier: _Hanging(), narrow: true);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
