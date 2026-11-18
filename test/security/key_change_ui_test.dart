/// Key-change warning UI (spec D2–D5, D9, E1): the change card, the
/// security code screen's three modes, and the own-key screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/data/local/database/contact_key_store.dart';
import 'package:kuch_bhi/features/auth/screens/own_key_changed_screen.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart'
    show currentUserIdProvider;
import 'package:kuch_bhi/features/chat/widgets/key_change_card.dart';
import 'package:kuch_bhi/features/security/key_change_providers.dart';
import 'package:kuch_bhi/data/local/secure_storage/secure_storage_service.dart';
import 'package:kuch_bhi/features/security/security_code_screen.dart';
import 'package:kuch_bhi/services/security_code.dart';

import '../offline/char_harness.dart' show FakeSecureStorage;

const _k1 = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=';
const _k2 = '//79/Pv6+fj39vX08/Lx8O/u7ezr6uno5+bl5OPi4eA=';

Widget _app(Widget child, {bool dark = false, double scale = 1}) => MaterialApp(
  theme: dark ? warmPopDark() : warmPopLight(),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(360, 780),
      textScaler: TextScaler.linear(scale),
    ),
    child: Scaffold(body: child),
  ),
);

void main() {
  group('C21 change card', () {
    for (final dark in [false, true]) {
      testWidgets('copy and buttons (${dark ? 'dark' : 'light'})', (
        tester,
      ) async {
        var compared = 0;
        var accepted = 0;
        await tester.pumpWidget(
          _app(
            dark: dark,
            KeyChangeCard(
              name: 'Bob',
              onCompare: () => compared++,
              onAccept: () => accepted++,
            ),
          ),
        );
        expect(find.text("Bob's security code changed"), findsOneWidget);
        expect(find.textContaining('reinstalls kuch bhi'), findsOneWidget);
        await tester.tap(find.text('Compare codes'));
        await tester.tap(find.text('Accept'));
        expect((compared, accepted), (1, 1));
      });
    }

    testWidgets('200 % text at 360 dp: buttons stack, nothing overflows', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          scale: 2,
          KeyChangeCard(name: 'Bob', onCompare: () {}, onAccept: () {}),
        ),
      );
      expect(tester.takeException(), isNull);
      final compare = tester.getTopLeft(find.text('Compare codes'));
      final accept = tester.getTopLeft(find.text('Accept'));
      expect(accept.dy, greaterThan(compare.dy));
    });
  });

  group('C22 security code screen', () {
    Widget screen(ContactKey pin, {String? myKey = _k2}) {
      final storage = FakeSecureStorage();
      if (myKey != null) storage.put('local_public_key', myKey);
      return ProviderScope(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
          contactKeyProvider.overrideWith((ref, id) => Stream.value(pin)),
          currentUserIdProvider.overrideWith((ref) async => 'me'),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const SecurityCodeScreen(userId: 'bob', name: 'Bob'),
        ),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pump();
      // The code is worked out in an isolate (compute).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 800)),
      );
      await tester.pumpAndSettle();
    }

    String digits(WidgetTester tester) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('security-code-digits')),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .join();

    testWidgets('pinned: 60 digits, scan + mark as verified', (tester) async {
      await tester.pumpWidget(
        screen(const ContactKey(userId: 'bob', key: _k1)),
      );
      await settle(tester);
      expect(digits(tester), securityCode('me', _k2, 'bob', _k1));
      // D1: 3 rows of 4 groups (the M52 wrapped 7 + 5 before).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('security-code-digits')),
          matching: find.byType(Row),
        ),
        findsNWidgets(3),
      );
      expect(find.text("Scan Bob's code"), findsOneWidget);
      expect(find.text('Mark as verified'), findsOneWidget);
      expect(find.text('Accept new code'), findsNothing);
    });

    testWidgets('pending: the NEW key\'s code, note, accept', (tester) async {
      await tester.pumpWidget(
        screen(const ContactKey(userId: 'bob', key: _k1, pendingKey: _k2)),
      );
      await settle(tester);
      expect(digits(tester), securityCode('me', _k2, 'bob', _k2));
      expect(find.textContaining('These are the new numbers'), findsOneWidget);
      expect(find.text('Accept new code'), findsOneWidget);
    });

    testWidgets('verified: tick and clear', (tester) async {
      await tester.pumpWidget(
        screen(const ContactKey(userId: 'bob', key: _k1, verified: true)),
      );
      await settle(tester);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Clear verified'), findsOneWidget);
    });

    testWidgets('no key on this phone: says so, no wrong code', (tester) async {
      await tester.pumpWidget(
        screen(const ContactKey(userId: 'bob', key: _k1), myKey: null),
      );
      await settle(tester);
      expect(find.textContaining("isn't available yet"), findsOneWidget);
    });
  });

  testWidgets('E1 own-key screen copy and buttons', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: warmPopLight(),
          home: const OwnKeyChangedScreen(),
        ),
      ),
    );
    expect(find.text('Your security code changed'), findsOneWidget);
    expect(find.textContaining("this phone didn't make"), findsOneWidget);
    expect(find.text("Keep this phone's code"), findsOneWidget);
    expect(find.text('Restore with recovery key'), findsOneWidget);

    await tester.tap(find.text('Restore with recovery key'));
    await tester.pumpAndSettle();
    expect(find.text('Use the new code?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Use the new code?'), findsNothing);
  });
}
