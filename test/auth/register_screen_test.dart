import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/screens/register_screen.dart';

import 'auth_harness.dart';

/// Register is pushed from a stub Login so Back / Sign in can pop.
Future<void> _pump(WidgetTester tester,
    {FakeAuthNotifier? notifier, bool narrow = false}) async {
  await pumpAuth(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () => context.push('/r'),
        child: const Text('login-stub'),
      ),
    ),
    notifier: notifier,
    narrow: narrow,
    routes: [GoRoute(path: '/r', builder: (_, __) => const RegisterScreen())],
  );
  await tester.tap(find.text('login-stub'));
  await tester.pumpAndSettle();
}

Future<void> _fillValid(WidgetTester tester, {String username = 'Avni_R'}) async {
  await tester.enterText(fieldWithLabel('Display name'), 'Avni');
  await tester.enterText(fieldWithLabel('Username'), username);
  await tester.enterText(fieldWithLabel('Email'), 'a@b.c');
  await tester.enterText(fieldWithLabel('Password'), 'secret123');
  await tester.enterText(fieldWithLabel('Confirm password'), 'secret123');
}

final _createButton = find.descendant(
    of: find.bySubtype<ButtonStyleButton>(),
    matching: find.text('Create account'));

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(_createButton);
  await tester.tap(_createButton);
  await tester.pump();
  await tester.pump();
}

void main() {
  test('validators', () {
    expect(validateDisplayName(''), 'Enter your name');
    expect(validateDisplayName('A'), 'At least 2 characters');
    expect(validateDisplayName('Av'), isNull);
    expect(validateUsername(''), 'Enter a username');
    expect(validateUsername('ab'), 'At least 3 characters');
    expect(validateUsername('a b'), 'Letters, numbers and underscores only');
    expect(validateUsername('avni_1'), isNull);
  });

  testWidgets('email, password and confirm validators on submit',
      (tester) async {
    final n = FakeAuthNotifier();
    await _pump(tester, notifier: n);
    await tester.enterText(fieldWithLabel('Display name'), 'Avni');
    await tester.enterText(fieldWithLabel('Username'), 'avni');
    await tester.enterText(fieldWithLabel('Email'), 'nope');
    await tester.enterText(fieldWithLabel('Password'), 'short');
    await tester.enterText(fieldWithLabel('Confirm password'), 'other');
    await _submit(tester);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(find.text("Passwords don't match"), findsOneWidget);
    expect(n.calls, isEmpty);
  });

  testWidgets('sentence-case labels and helpers', (tester) async {
    await _pump(tester);
    expect(find.text('Create account'), findsNWidgets(2)); // app bar + button
    expect(find.text('Join Kuch Bhi'), findsOneWidget);
    expect(find.text(kUsernameHelper), findsOneWidget);
    expect(find.text('At least 8 characters.'), findsOneWidget);
    expect(find.text('@'), findsOneWidget);
  });

  testWidgets('username is submitted lower-cased', (tester) async {
    final n = FakeAuthNotifier();
    await _pump(tester, notifier: n);
    await _fillValid(tester);
    await _submit(tester);
    expect(n.calls, ['register']);
    expect(n.args.single['username'], 'avni_r');
  });

  testWidgets('username taken lands on the field and clears on edit',
      (tester) async {
    final n = FakeAuthNotifier()
      ..next = const AuthError(kUsernameTakenCopy, field: 'username');
    await _pump(tester, notifier: n);
    await _fillValid(tester);
    await _submit(tester);
    expect(find.text('That username is taken.'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing, reason: 'field, not toast');
    await tester.enterText(fieldWithLabel('Username'), 'avni_2');
    await tester.pump();
    expect(find.text('That username is taken.'), findsNothing);
  });

  testWidgets('email taken lands on the email field', (tester) async {
    final n = FakeAuthNotifier()
      ..next = const AuthError(kEmailTakenCopy, field: 'email');
    await _pump(tester, notifier: n);
    await _fillValid(tester);
    await _submit(tester);
    expect(find.text('An account with this email already exists.'),
        findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('other failures toast the G1 copy', (tester) async {
    final n = FakeAuthNotifier()
      ..next = const AuthError("Couldn't create your account. Try again.");
    await _pump(tester, notifier: n);
    await _fillValid(tester);
    await _submit(tester);
    expect(find.text("Couldn't create your account. Try again."),
        findsOneWidget);
  });

  testWidgets('Sign in pops back to Login', (tester) async {
    await _pump(tester);
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('login-stub'), findsOneWidget);
  });

  testWidgets('G4: an error from an action another screen started is not '
      'shown here', (tester) async {
    final n = FakeAuthNotifier()..next = const AuthError('from login');
    await _pump(tester, notifier: n);
    final c = ProviderScope.containerOf(
        tester.element(find.byType(RegisterScreen)));
    await c.read(authProvider.future);
    await n.signInWithEmailPassword(email: 'a', password: 'b');
    await tester.pump();
    await tester.pump();
    expect(find.text('from login'), findsNothing);
  });

  testWidgets('app bar title is a heading; no accent or error Text',
      (tester) async {
    await _pump(tester);
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.text('Create account').last),
        isSemantics(isHeader: true));
    handle.dispose();
    expectNoAccentOrErrorText(tester);
  });

  testWidgets('360dp x 200% text: no overflow, with errors', (tester) async {
    await _pump(tester, narrow: true);
    expect(tester.takeException(), isNull);
    await _submit(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('G5: offline, keyboard Done does not register', (tester) async {
    final n = FakeAuthNotifier();
    await pumpAuth(tester, const RegisterScreen(), notifier: n, online: false);
    await _fillValid(tester);
    await tester.showKeyboard(fieldWithLabel('Confirm password'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(n.calls, isEmpty);
  });
}
