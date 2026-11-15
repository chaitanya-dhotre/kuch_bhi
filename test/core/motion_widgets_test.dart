// Motion spec test gates 2a (D2), 5 (L7), 7 (B2), 8 (B3) and 9 (E1).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/page_motion.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/core/widgets/app_avatar.dart';
import 'package:kuch_bhi/core/widgets/app_dialog.dart';
import 'package:kuch_bhi/core/widgets/app_sheet.dart';
import 'package:kuch_bhi/core/widgets/change_motion.dart';
import 'package:kuch_bhi/core/widgets/chat_tile.dart';
import 'package:kuch_bhi/core/widgets/press_scale.dart';
import 'package:kuch_bhi/features/app_lock/widgets/pin_pad.dart';
import 'package:kuch_bhi/features/chat/widgets/bubble_entrance.dart';

Widget _app(Widget home, {bool reduced = false}) => MaterialApp(
  theme: warmPopLight(),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: home,
    ),
  ),
);

void main() {
  group('gate 2a: D2 row slide', () {
    const h = 60.0;
    Widget rows(List<String> order, int gen, Map<String, int> prev) => _app(
      Scaffold(
        body: Column(
          children: [
            for (final (i, id) in order.indexed)
              ReorderSlide(
                key: ValueKey(id),
                slot: i,
                previousSlot: prev[id],
                generation: gen,
                child: SizedBox(height: h, child: Text(id)),
              ),
          ],
        ),
      ),
    );
    Map<String, int> slots(List<String> o) => {
      for (final (i, id) in o.indexed) id: i,
    };
    double topOf(WidgetTester t, String id) => t.getTopLeft(find.text(id)).dy;

    testWidgets('a reorder ends with every row at its slot', (tester) async {
      final a = ['a', 'b', 'c'];
      await tester.pumpWidget(rows(a, 0, const {}));
      final b = ['c', 'a', 'b'];
      await tester.pumpWidget(rows(b, 1, slots(a)));
      await tester.pump(const Duration(milliseconds: 60));
      // Mid-slide: c is still on its way up from slot 2.
      expect(topOf(tester, 'c'), greaterThan(0));
      await tester.pumpAndSettle();
      for (final (i, id) in b.indexed) {
        expect(topOf(tester, id), i * h, reason: id);
      }
    });

    testWidgets('two reorders 100 ms apart end correctly', (tester) async {
      final a = ['a', 'b', 'c'];
      await tester.pumpWidget(rows(a, 0, const {}));
      final b = ['c', 'a', 'b'];
      await tester.pumpWidget(rows(b, 1, slots(a)));
      await tester.pump(const Duration(milliseconds: 100));
      final c = ['b', 'c', 'a'];
      await tester.pumpWidget(rows(c, 2, slots(b)));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpAndSettle();
      for (final (i, id) in c.indexed) {
        expect(topOf(tester, id), i * h, reason: id);
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('gate 5 (L7): reduced motion starts no ticker in B–E', (
    tester,
  ) async {
    var trigger = 0;
    var gen = 0;
    late StateSetter set;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return Scaffold(
              body: ListView(
                children: [
                  PressScale(child: Text('press $trigger')),
                  PopOnChange(value: trigger, child: const Text('pop')),
                  FlashOnChange(
                    trigger: trigger,
                    builder: (_, f) => Text('flash $f'),
                  ),
                  ShakeOnChange(trigger: trigger, child: const Text('shake')),
                  ReorderSlide(
                    key: const ValueKey('r'),
                    slot: gen,
                    previousSlot: gen == 0 ? null : 0,
                    generation: gen,
                    child: const SizedBox(height: 40),
                  ),
                  for (final m in BubbleMotion.values)
                    BubbleEntrance(
                      motion: m,
                      flight: const SendFlight('x', Rect.zero),
                      child: Text('$m'),
                    ),
                  BubbleEntrance(
                    motion: null,
                    leaving: trigger > 0,
                    child: const Text('leaving'),
                  ),
                ],
              ),
            );
          },
        ),
        reduced: true,
      ),
    );
    await tester.pump();
    await tester.press(find.text('press 0'));
    set(() {
      trigger++;
      gen++;
    });
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    // The same information still shows.
    for (final m in BubbleMotion.values) {
      expect(find.text('$m'), findsOneWidget);
    }
  });

  testWidgets('gate 5 (L7): pages, sheets and dialogs fade in 150 ms', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    const b = WarmPopPageTransitionsBuilder();
    expect(b.transitionDuration, WarmPopTokens.motionFast);
    expect(b.reverseTransitionDuration, WarmPopTokens.motionFast);
    // The platform flag also makes Flutter run normal controllers at 5 %;
    // the sheet fade below is timed with only the MediaQuery flag on.
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    late BuildContext ctx;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
        reduced: true,
      ),
    );
    expect(dialogMotion(ctx).duration, WarmPopTokens.motionFast);
    expect(sheetMotion(ctx), AnimationStyle.noAnimation);
    unawaited(showAppSheet<void>(context: ctx, builder: (_) => const Text('s')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: find.text('s'), matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, closeTo(0.5, 0.05));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<FadeTransition>(
        find.ancestor(of: find.text('s'), matching: find.byType(FadeTransition)).first,
      ).opacity.value,
      1,
    );
  });

  group('gate 7: B2 page push', () {
    testWidgets('the theme builder drives a pushed route', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: warmPopLight(),
          navigatorKey: key,
          home: const Text('home'),
        ),
      );
      expect(
        Theme.of(tester.element(find.text('home')))
            .pageTransitionsTheme
            .builders[TargetPlatform.android],
        isA<WarmPopPageTransitionsBuilder>(),
      );
      unawaited(
        key.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const Text('page')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final dx = tester.getTopLeft(find.text('page')).dx;
      expect(dx, greaterThan(0), reason: 'mid-slide from the right');
      expect(dx, lessThan(24));
      await tester.pump(WarmPopTokens.motionPage);
      expect(tester.getTopLeft(find.text('page')).dx, 0);
    });

    testWidgets('pop completes while the leaving page waits on a future', (
      tester,
    ) async {
      final key = GlobalKey<NavigatorState>();
      final never = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          theme: warmPopLight(),
          navigatorKey: key,
          home: const Text('home'),
        ),
      );
      unawaited(
        key.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => FutureBuilder<void>(
              future: never.future,
              builder: (_, _) => const Text('page'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      key.currentState!.pop();
      // Nothing waits on the page's future: the pop runs its 240 ms and ends.
      await tester.pumpAndSettle();
      expect(find.text('page'), findsNothing);
    });
  });

  testWidgets('gate 8: B3 avatar with badge and name fly to the chat', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: warmPopLight(),
        navigatorKey: key,
        home: const Scaffold(
          body: ChatTile(
            title: 'New Group',
            subtitle: 'hi',
            isGroup: true,
            heroId: 'c1',
          ),
        ),
      ),
    );
    final tags = tester.widgetList<Hero>(find.byType(Hero)).map((h) => h.tag);
    expect(tags, containsAll(['chat-avatar-c1', 'chat-name-c1']));
    expect(find.text('NG'), findsOneWidget);
    unawaited(
      key.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: Row(
              children: [
                ChatHero(
                  tag: chatAvatarHeroTag('c1'),
                  child: AppAvatar(radius: 18, initials: nameInitials('New Group')),
                ),
                ChatHero(
                  tag: chatNameHeroTag('c1'),
                  child: const Text('New Group'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Mid-flight: the Home look, group badge included, is in the shuttle.
    expect(find.byIcon(Icons.group), findsWidgets);
    // No flying text falls back to the debug style (yellow underline).
    for (final p in tester.renderObjectList<RenderParagraph>(
      find.text('New Group'),
    )) {
      expect(p.text.style?.decoration, isNot(TextDecoration.underline));
    }
    await tester.pumpAndSettle();
    expect(find.text('NG'), findsOneWidget);
    final chat = File('lib/features/chat/screens/chat_screen.dart')
        .readAsStringSync();
    expect('tag: chatAvatarHeroTag(_cid)'.allMatches(chat), hasLength(1));
    expect('tag: chatNameHeroTag(_cid)'.allMatches(chat), hasLength(1));
    expect('nameInitials(conv.displayName)'.allMatches(chat), hasLength(2));
    final banner = File('lib/features/mascot/offline_bath_banner.dart')
        .readAsStringSync();
    expect(banner, contains('tag: offlineBannerHeroTag'));
  });

  testWidgets('gate 9: E1 a wrong PIN shakes once and ends at x = 0', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SingleChildScrollView(
            child: PinPad(title: 'PIN', onCompleted: (_) async => false),
          ),
        ),
      ),
    );
    final dots = find.byType(ShakeOnChange);
    double x() => tester
        .widget<Transform>(
          find.descendant(of: dots, matching: find.byType(Transform)).first,
        )
        .transform
        .getTranslation()
        .x;
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('1'));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 60));
    expect(x(), isNot(0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(x(), 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(x(), 0, reason: 'shook once, then rests');
  });
}
