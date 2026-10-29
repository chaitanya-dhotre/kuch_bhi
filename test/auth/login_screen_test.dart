import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/screens/login_screen.dart';

import 'auth_harness.dart';

Future<void> _fill(WidgetTester tester, String id, String pw) async {
  await tester.enterText(fieldWithLabel('Email or username'), id);
  await tester.enterText(fieldWithLabel('Password'), pw);
}

void main() {
  testWidgets('empty submit shows both field errors, no notifier call',
      (tester) async {
    final n = FakeAuthNotifier();
    await pumpAuth(tester, const LoginScreen(), notifier: n);
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter your email or username'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    // R13: the error line carries the icon, not error-red text.
    expect(find.byIcon(Icons.error_outline), findsNWidgets(2));
    expect(n.calls, isEmpty);
  });

  testWidgets('valid submit signs in once with the trimmed identity; '
      'a username (no @) is accepted', (tester) async {
    final n = FakeAuthNotifier();
    await pumpAuth(tester, const LoginScreen(), notifier: n);
    await _fill(tester, '  avni_r  ', 'pa ss ');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(n.calls, ['signIn']);
    expect(n.args.single['email'], 'avni_r');
    expect(n.args.single['password'], 'pa ss ', reason: 'sent as typed');
  });

  testWidgets('AuthError from this screen shows its copy in a toast',
      (tester) async {
    final n = FakeAuthNotifier()
      ..next = const AuthError('Wrong email, username or password.');
    await pumpAuth(tester, const LoginScreen(), notifier: n);
    await _fill(tester, 'a@b.c', 'x');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Wrong email, username or password.'), findsOneWidget);
  });

  testWidgets('only the tapped button is busy; the other is disabled',
      (tester) async {
    final n = FakeAuthNotifier()..gate = Completer<void>();
    await pumpAuth(tester, const LoginScreen(), notifier: n);
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    // Google busy: its label is replaced by the spinner; Sign in disabled.
    expect(find.text('Continue with Google'), findsNothing);
    expect(buttonOf(tester, 'Sign in').onPressed, isNull);
    expect(find.text('Sign in'), findsOneWidget, reason: 'Sign in not busy');
    n.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(buttonOf(tester, 'Sign in').onPressed, isNotNull);
  });

  testWidgets('offline: Sign in and Google disabled at one 38% dim + hint; '
      'fields still editable', (tester) async {
    await pumpAuth(tester, const LoginScreen(), online: false);
    expect(find.text('Available online'), findsOneWidget);
    expect(buttonOf(tester, 'Sign in').onPressed, isNull);
    expect(buttonOf(tester, 'Continue with Google').onPressed, isNull);
    final dims = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .where((o) => o.opacity == .38);
    expect(dims.length, 2, reason: 'one dim each, never stacked');
    await tester.enterText(fieldWithLabel('Email or username'), 'avni');
    expect(find.text('avni'), findsOneWidget);
    expect(buttonOf(tester, 'Forgot password?').onPressed, isNotNull);
  });

  testWidgets('Create account pushes /register', (tester) async {
    await pumpAuth(tester, const LoginScreen());
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('page:/register'), findsOneWidget);
  });

  testWidgets('Forgot password? pushes /forgot-password', (tester) async {
    await pumpAuth(tester, const LoginScreen());
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('page:/forgot-password'), findsOneWidget);
  });

  testWidgets('show-password tooltip flips', (tester) async {
    await pumpAuth(tester, const LoginScreen());
    expect(find.byTooltip('Show password'), findsOneWidget);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });

  testWidgets('title is a heading; no accent or error Text', (tester) async {
    await pumpAuth(tester, const LoginScreen());
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.text('Welcome back')),
        isSemantics(isHeader: true));
    handle.dispose();
    expectNoAccentOrErrorText(tester);
  });

  testWidgets('360dp x 200% text: no overflow', (tester) async {
    await pumpAuth(tester, const LoginScreen(), narrow: true);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'with field errors');
  });

  testWidgets('G5: offline, keyboard Done does not sign in', (tester) async {
    final n = FakeAuthNotifier();
    await pumpAuth(tester, const LoginScreen(), notifier: n, online: false);
    await _fill(tester, 'a@b.c', 'pw');
    await tester.showKeyboard(fieldWithLabel('Password'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(n.calls, isEmpty);
  });

  testWidgets('G4: while busy, Create account and Forgot are disabled',
      (tester) async {
    final n = FakeAuthNotifier()..gate = Completer<void>();
    await pumpAuth(tester, const LoginScreen(), notifier: n);
    await _fill(tester, 'a@b.c', 'pw');
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(buttonOf(tester, 'Create account').onPressed, isNull);
    expect(buttonOf(tester, 'Forgot password?').onPressed, isNull);
    n.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(buttonOf(tester, 'Create account').onPressed, isNotNull);
  });
}
