import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/features/settings/screens/about_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> _pump(WidgetTester tester,
    {String version = '1.0.0', String build = '1', double textScale = 1}) async {
  PackageInfo.setMockInitialValues(
    appName: 'Kuch Bhi',
    packageName: 'com.chai.kuch_bhi',
    version: version,
    buildNumber: build,
    buildSignature: '',
  );
  await tester.pumpWidget(MaterialApp(
    theme: warmPopLight(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const AboutScreen(),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('version row shows version (build)', (tester) async {
    await _pump(tester);
    expect(find.text('Version'), findsOneWidget);
    expect(find.text('1.0.0 (1)'), findsOneWidget);
    expect(find.textContaining('…'), findsNothing);
  });

  testWidgets('version value sits at the row end, not mid-row',
      (tester) async {
    await _pump(tester);
    // Screen 800 wide − 12 list inset − 16 tile padding (device finding 2026-10-29).
    expect(tester.getTopRight(find.text('1.0.0 (1)')).dx, 800 - 12 - 16);
  });

  testWidgets('G3: 200% text on a 360dp phone does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, version: '1.0.12', build: '34', textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('1.0.12 (34)'), findsOneWidget);
  });

  testWidgets('Open-source licences opens the licence page', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Open-source licences'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('copy present; no accent- or error-coloured Text',
      (tester) async {
    await _pump(tester);
    expect(find.text('Kuch Bhi'), findsOneWidget);
    expect(find.text('Private, end-to-end encrypted messaging'),
        findsOneWidget);
    expect(find.textContaining('Only you and the people you talk to'),
        findsOneWidget);
    final t = ColorTokens.light;
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      final c = w.style?.color;
      expect(c, isNot(t.accent), reason: w.data);
      expect(c, isNot(t.error), reason: w.data);
    }
  });
}
