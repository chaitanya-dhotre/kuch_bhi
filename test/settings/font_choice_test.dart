import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/app.dart';
import 'package:kuch_bhi/core/router/app_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/settings/providers/theme_provider.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/presence_service.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:kuch_bhi/features/settings/widgets/font_choice_group.dart';

import '../auth/auth_harness.dart';
import '../fakes/fake_message_repository.dart';

class _FakePresence implements PresenceService {
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class _FakeFont implements FontController {
  final calls = <AppFont>[];
  bool fail = false;

  @override
  Future<void> setFont(AppFont font) async {
    calls.add(font);
    if (fail) throw StateError('disk full');
  }
}

Future<void> _pump(WidgetTester tester,
    {AppFont font = AppFont.system, _FakeFont? c, double scale = 1}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      fontFamilyProvider.overrideWith((ref) => Stream.value(font)),
      fontControllerProvider.overrideWithValue(c ?? _FakeFont()),
    ],
    child: MaterialApp(
      theme: warmPopLight(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const Scaffold(body: SingleChildScrollView(child: FontChoiceGroup())),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  test('AppFont storage round-trip defaults to system', () {
    expect(AppFontX.fromStorage(null), AppFont.system);
    expect(AppFontX.fromStorage('garbage'), AppFont.system);
    expect(AppFontX.fromStorage('jakarta'), AppFont.jakarta);
    expect(AppFont.jakarta.storageValue, 'jakarta');
    expect(AppFont.system.label, 'System default');
    expect(AppFont.jakarta.label, 'Plus Jakarta Sans');
    expect(AppFont.system.fontFamily, isNull);
  });

  test('warmPop builders thread fontFamily into ThemeData', () {
    expect(warmPopLight(fontFamily: 'PlusJakartaSans')
        .textTheme.bodyMedium?.fontFamily, 'PlusJakartaSans');
    expect(warmPopDark(amoled: true, fontFamily: 'PlusJakartaSans')
        .textTheme.bodyMedium?.fontFamily, 'PlusJakartaSans');
    expect(warmPopLight().textTheme.bodyMedium?.fontFamily,
        isNot('PlusJakartaSans'), reason: 'P11 system default');
    expect(warmPopDark(amoled: true).scaffoldBackgroundColor, Colors.black,
        reason: 'AMOLED still composes with the font param');
  });

  testWidgets('KuchBhiApp: one stored jakarta re-themes the whole app',
      (tester) async {
    TextStyle? body;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) {
          body = Theme.of(context).textTheme.bodyMedium;
          return const SizedBox();
        },
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appRouterProvider.overrideWithValue(router),
        authProvider.overrideWith(() => FakeAuthNotifier()),
        presenceServiceProvider.overrideWithValue(_FakePresence()),
        messageRepositoryProvider.overrideWithValue(FakeMessageRepository()),
        themeModeProvider
            .overrideWith((ref) => Stream.value(AppThemeMode.amoled)),
        fontFamilyProvider.overrideWith((ref) => Stream.value(AppFont.jakarta)),
      ],
      child: const KuchBhiApp(),
    ));
    await tester.pump();
    await tester.pump();
    // MaterialApp lerps between themes (AnimatedTheme, 200ms).
    await tester.pump(const Duration(milliseconds: 300));
    expect(body?.fontFamily, 'PlusJakartaSans');
  });

  testWidgets('each row is drawn in its own font', (tester) async {
    await _pump(tester, font: AppFont.jakarta);
    TextStyle style(String s) => DefaultTextStyle.of(
            tester.element(find.text(s)))
        .style
        .merge(tester.widget<Text>(find.text(s)).style);
    expect(style('Plus Jakarta Sans').fontFamily, 'PlusJakartaSans');
    expect(style('System default').fontFamily, isNot('PlusJakartaSans'));
  });

  testWidgets('tap Plus Jakarta Sans writes it once; stored row is selected',
      (tester) async {
    final c = _FakeFont();
    await _pump(tester, c: c, font: AppFont.jakarta);
    await tester.tap(find.text('Plus Jakarta Sans'));
    await tester.pump();
    expect(c.calls, [AppFont.jakarta]);
    final handle = tester.ensureSemantics();
    expect(
        tester.getSemantics(find.text('Plus Jakarta Sans')),
        isSemantics(
            isSelected: true,
            hasSelectedState: true,
            isInMutuallyExclusiveGroup: true));
    expect(tester.getSemantics(find.text('System default')),
        isSemantics(isSelected: false, isInMutuallyExclusiveGroup: true));
    handle.dispose();
  });

  testWidgets('a failed write shows the fixed toast, nothing escapes',
      (tester) async {
    final c = _FakeFont()..fail = true;
    await _pump(tester, c: c);
    await tester.tap(find.text('Plus Jakarta Sans'));
    await tester.pump();
    await tester.pump();
    expect(find.text("Couldn't change the font. Try again."), findsOneWidget);
    expect(find.textContaining('disk full'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360dp x 200% text: no overflow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, scale: 2);
    expect(tester.takeException(), isNull);
  });
}
