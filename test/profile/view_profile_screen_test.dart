import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/profile/screens/view_profile_screen.dart';

import '../fakes/fake_auth_repository.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: warmPopLight(), home: child);

void main() {
  testWidgets('header, about and friend code row', (tester) async {
    await tester.pumpWidget(_host(ViewProfileScreen(
        user: fakeUser(about: 'hello there'))));
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Avni R.'), findsOneWidget);
    expect(find.text('@avni'), findsOneWidget);
    expect(find.text('hello there'), findsOneWidget);
    expect(find.text('Friend code'), findsOneWidget);
    expect(find.text('KB7Q2X'), findsOneWidget);
  });

  testWidgets('empty name falls back to Unknown with ? initials, no dot',
      (tester) async {
    await tester.pumpWidget(
        _host(ViewProfileScreen(user: fakeUser(displayName: ''))));
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
    // The old presence dot was a 10x10 circle.
    final dots = tester.widgetList<Container>(find.byType(Container)).where(
        (c) =>
            c.constraints?.maxWidth == 10 &&
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).shape == BoxShape.circle);
    expect(dots, isEmpty);
  });

  testWidgets('copy puts the code on the clipboard and toasts',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(_host(ViewProfileScreen(user: fakeUser())));
    await tester.tap(find.byTooltip('Copy friend code'));
    await tester.pump();
    expect(copied, 'KB7Q2X');
    expect(find.text('Friend code copied'), findsOneWidget);
  });

  testWidgets('bad route extra shows Profile unavailable, no crash',
      (tester) async {
    await tester.pumpWidget(_host(viewProfileFromExtra('not a user')));
    expect(find.text('Profile unavailable'), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
