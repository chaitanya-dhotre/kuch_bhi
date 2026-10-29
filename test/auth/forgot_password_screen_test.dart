import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/features/auth/screens/forgot_password_screen.dart';

import 'auth_harness.dart';

const _sentCopy = 'If an account exists for a@b.c, a reset link is on its way. '
    'It opens a web page where you choose a new password.';

Future<void> _send(WidgetTester tester, String email) async {
  await tester.enterText(fieldWithLabel('Email'), email);
  await tester.tap(find.text('Send link'));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('sends once with the trimmed email; sent view names it',
      (tester) async {
    final n = FakeAuthNotifier();
    await pumpAuth(tester, const ForgotPasswordScreen(), notifier: n);
    await _send(tester, '  a@b.c ');
    expect(n.calls, ['reset']);
    expect(n.args.single['email'], 'a@b.c');
    expect(find.text('Check your email'), findsOneWidget);
    expect(find.text(_sentCopy), findsOneWidget);
    // E3: the disc's icon is ink, never accent.
    final icon =
        tester.widget<Icon>(find.byIcon(Icons.mark_email_read_outlined));
    expect(icon.color, ColorTokens.light.ink);
    expectNoAccentOrErrorText(tester);
  });

  testWidgets('Send again returns to the form with the email kept',
      (tester) async {
    await pumpAuth(tester, const ForgotPasswordScreen());
    await _send(tester, 'a@b.c');
    await tester.tap(find.text('Send again'));
    await tester.pump();
    expect(find.text('Send link'), findsOneWidget);
    expect(find.text('a@b.c'), findsOneWidget);
  });

  testWidgets('failure: G1 toast, form stays filled', (tester) async {
    final n = FakeAuthNotifier()..resetError = "Couldn't send the link. Try again.";
    await pumpAuth(tester, const ForgotPasswordScreen(), notifier: n);
    await _send(tester, 'a@b.c');
    expect(find.text("Couldn't send the link. Try again."), findsOneWidget);
    expect(find.text('Check your email'), findsNothing);
    expect(find.text('a@b.c'), findsOneWidget);
  });

  testWidgets('invalid email: field error, no call', (tester) async {
    final n = FakeAuthNotifier();
    await pumpAuth(tester, const ForgotPasswordScreen(), notifier: n);
    await _send(tester, 'nope');
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(n.calls, isEmpty);
  });

  testWidgets('offline: Send link disabled + hint', (tester) async {
    await pumpAuth(tester, const ForgotPasswordScreen(), online: false);
    expect(buttonOf(tester, 'Send link').onPressed, isNull);
    expect(find.text('Available online'), findsOneWidget);
  });

  testWidgets('app bar title is a heading', (tester) async {
    await pumpAuth(tester, const ForgotPasswordScreen());
    final handle = tester.ensureSemantics();
    expect(tester.getSemantics(find.text('Reset password')),
        isSemantics(isHeader: true));
    handle.dispose();
  });

  testWidgets('360dp x 200% text: form and sent view, no overflow',
      (tester) async {
    await pumpAuth(tester, const ForgotPasswordScreen(), narrow: true);
    expect(tester.takeException(), isNull);
    await _send(tester, 'a@b.c');
    expect(find.text('Check your email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
