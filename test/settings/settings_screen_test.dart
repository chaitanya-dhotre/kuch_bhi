import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kuch_bhi/core/router/app_router.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:kuch_bhi/features/settings/providers/notification_status_provider.dart';
import 'package:kuch_bhi/features/settings/providers/theme_provider.dart';
import 'package:kuch_bhi/features/settings/screens/settings_screen.dart';

class _FakeController implements ThemeController {
  final calls = <AppThemeMode>[];
  bool fail = false;

  @override
  Future<void> setTheme(AppThemeMode mode) async {
    calls.add(mode);
    if (fail) throw StateError('disk full');
  }

  @override
  Future<AppThemeMode> current() async => AppThemeMode.system;
}

Future<void> _pump(
  WidgetTester tester, {
  AppThemeMode mode = AppThemeMode.system,
  _FakeController? controller,
  bool? notifications = true,
  Future<bool> Function()? opener,
}) async {
  // L4: the Font section makes the list taller than the default 800x600.
  await tester.binding.setSurfaceSize(const Size(800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const SettingsScreen()),
    GoRoute(path: AppRoutes.about, builder: (_, __) => const Text('about-page')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      themeModeProvider.overrideWith((ref) => Stream.value(mode)),
      fontFamilyProvider.overrideWith((ref) => Stream.value(AppFont.system)),
      themeControllerProvider
          .overrideWithValue(controller ?? _FakeController()),
      notificationsEnabledProvider.overrideWith((ref) async {
        if (notifications == null) throw StateError('no status');
        return notifications;
      }),
      openSystemSettingsProvider
          .overrideWithValue(opener ?? () async => true),
    ],
    child: MaterialApp.router(theme: warmPopLight(), routerConfig: router),
  ));
  await tester.pump();
  await tester.pump();
}

final _selected = find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.selected == true);

void main() {
  testWidgets('sections in order; no Backup PIN row', (tester) async {
    await _pump(tester);
    // `.first` = the section header ("Notifications" is also the row title).
    double y(String s) => tester.getTopLeft(find.text(s).first).dy;
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Notifications'), findsNWidgets(2));
    expect(y('Appearance') < y('System default'), isTrue);
    expect(y('AMOLED (true black)') < y('Font'), isTrue);
    expect(y('Font') < y('Plus Jakarta Sans'), isTrue);
    expect(y('Plus Jakarta Sans') < y('Notifications'), isTrue);
    expect(y('Notifications') < y('About'), isTrue);
    expect(find.textContaining('Backup PIN'), findsNothing);
    expect(find.byType(RadioListTile<AppThemeMode>), findsNothing);
  });

  testWidgets('only the stored mode is ticked and selected', (tester) async {
    await _pump(tester, mode: AppThemeMode.dark);
    expect(_selected, findsNWidgets(2)); // L4: theme + font
    expect(find.descendant(of: _selected, matching: find.text('Dark')),
        findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2)); // L4: theme + font
    expect(find.descendant(of: _selected, matching: find.byIcon(Icons.check)),
        findsNWidgets(2));
    final groups = find.byWidgetPredicate((w) =>
        w is Semantics && w.properties.inMutuallyExclusiveGroup == true);
    expect(groups,
        findsNWidgets(AppThemeMode.values.length + AppFont.values.length));
    // The flags must reach the real semantics tree, not just exist as widgets.
    final handle = tester.ensureSemantics();
    expect(
        tester.getSemantics(find.text('Dark')),
        isSemantics(
            isSelected: true,
            hasSelectedState: true,
            isInMutuallyExclusiveGroup: true));
    expect(tester.getSemantics(find.text('Light')),
        isSemantics(isSelected: false, isInMutuallyExclusiveGroup: true));
    expect(tester.getSemantics(find.text('Notifications').last),
        isSemantics(hint: 'Opens system settings'));
    handle.dispose();
  });

  testWidgets('tapping Dark writes dark once', (tester) async {
    final c = _FakeController();
    await _pump(tester, controller: c);
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(c.calls, [AppThemeMode.dark]);
  });

  testWidgets('a failed theme write shows the fixed toast, nothing escapes',
      (tester) async {
    final c = _FakeController()..fail = true;
    await _pump(tester, controller: c);
    await tester.tap(find.text('Light'));
    await tester.pump();
    await tester.pump();
    expect(find.text("Couldn't change the theme. Try again."), findsOneWidget);
    expect(find.textContaining('disk full'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notifications granted reads On', (tester) async {
    await _pump(tester, notifications: true);
    expect(find.text('On'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
  });

  testWidgets('notifications denied reads Off with the way back',
      (tester) async {
    await _pump(tester, notifications: false);
    expect(find.text('Off. Turn them on in system settings.'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
  });

  testWidgets('status check failing shows no subtitle, row still works',
      (tester) async {
    var calls = 0;
    await _pump(tester, notifications: null, opener: () async {
      calls++;
      return true;
    });
    expect(find.text('On'), findsNothing);
    expect(find.textContaining('Off.'), findsNothing);
    await tester.tap(find.text('Notifications').last);
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('row opens system settings once; a refusal shows the toast',
      (tester) async {
    var calls = 0;
    await _pump(tester, opener: () async {
      calls++;
      return false;
    });
    await tester.tap(find.text('Notifications').last);
    await tester.pump();
    await tester.pump();
    expect(calls, 1);
    expect(find.text("Couldn't open system settings."), findsOneWidget);
  });

  testWidgets('About pushes /about', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('about-page'), findsOneWidget);
  });

  testWidgets('no accent- or error-coloured Text on the screen',
      (tester) async {
    await _pump(tester, notifications: false);
    final t = ColorTokens.light;
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      final c = w.style?.color;
      expect(c, isNot(t.accent), reason: w.data);
      expect(c, isNot(t.error), reason: w.data);
    }
  });
}
