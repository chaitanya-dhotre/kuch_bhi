import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/mascot/capy.dart';
import 'package:kuch_bhi/features/mascot/capy_spots.dart';

/// Records what the widget writes into the view model.
class FakeRig implements CapyRig {
  CapyMood? mood;
  CapyPose? pose;
  int queued = -1;
  double? lookX;
  final bools = <String, bool>{};
  final fired = <String>[];
  bool disposed = false;

  @override
  void setMood(CapyMood m) => mood = m;
  @override
  void setPose(CapyPose p) => pose = p;
  @override
  void setBool(String name, bool value) => bools[name] = value;
  @override
  void setQueued(int q) => queued = q;
  @override
  void setLookX(double x) => lookX = x;
  @override
  void fire(String trigger) => fired.add(trigger);
  @override
  Widget get view => const ColoredBox(color: Colors.brown);
  @override
  void dispose() => disposed = true;
}

class FakeSource implements CapySource {
  final rigs = <FakeRig>[];
  final views = <CapyView>[];

  @override
  CapyRig create(CapyView view) {
    views.add(view);
    return (rigs..add(FakeRig())).last;
  }
}

Widget host(Widget child, {bool reduced = false}) => MaterialApp(
  theme: warmPopLight(),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  late FakeSource source;
  setUp(() => CapyLoader.debugSource = source = FakeSource());
  tearDown(() => CapyLoader.debugSource = null);

  testWidgets('decorative: wrapped in ExcludeSemantics and RepaintBoundary', (
    tester,
  ) async {
    await tester.pumpWidget(host(const Capy(view: CapyView.sit, size: 90)));
    final capy = find.byType(Capy);
    expect(
      find.descendant(of: capy, matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: capy, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
    expect(tester.getSize(capy), const Size(90, 90));
    final rig = source.rigs.single;
    expect(source.views.single, CapyView.sit);
    expect(rig.mood, CapyMood.chill);
    expect(rig.bools['still'], isTrue, reason: 'not animated = still (F2)');
    expect(rig.bools['reducedMotion'], isFalse);
  });

  testWidgets('load failure leaves an empty box of the same size (F1)', (
    tester,
  ) async {
    CapyLoader.debugSource = null;
    await tester.pumpWidget(host(const Capy(view: CapyView.front, size: 72)));
    expect(tester.getSize(find.byType(Capy)), const Size(72, 72));
    final inside = find.descendant(
      of: find.byType(Capy),
      matching: find.byWidgetPredicate(
        (w) => w is GestureDetector || w is ColoredBox,
      ),
    );
    expect(inside, findsNothing);
  });

  testWidgets('reduced motion reaches the rig (F3)', (tester) async {
    await tester.pumpWidget(
      host(const Capy(view: CapyView.head, animated: true), reduced: true),
    );
    final rig = source.rigs.single;
    expect(rig.bools['reducedMotion'], isTrue);
    expect(rig.bools['still'], isFalse);
  });

  testWidgets('tap pets, long press holds until release (I3)', (tester) async {
    await tester.pumpWidget(host(const Capy(view: CapyView.sit)));
    final rig = source.rigs.single;
    await tester.tap(find.byType(Capy));
    expect(rig.fired, ['pet']);

    final g = await tester.startGesture(tester.getCenter(find.byType(Capy)));
    await tester.pump(const Duration(milliseconds: 700));
    expect(rig.bools['holding'], isTrue);
    await g.up();
    await tester.pump();
    expect(rig.bools['holding'], isFalse);
  });

  testWidgets('a tap on the capybara never reaches the control under it (F8)', (
    tester,
  ) async {
    var under = 0;
    await tester.pumpWidget(
      host(
        InkWell(
          onTap: () => under++,
          child: const Padding(
            padding: EdgeInsets.all(30),
            child: Capy(view: CapyView.onsen),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Capy));
    expect(source.rigs.single.fired, ['pet']);
    expect(under, 0);
    await tester.tapAt(
      tester.getTopLeft(find.byType(InkWell)) + const Offset(5, 5),
    );
    expect(under, 1);
  });

  testWidgets('hops, flushes and props sync on rebuild; wave fires on show', (
    tester,
  ) async {
    Widget capy(int hops, int flushes, int queued) => host(
      Capy(
        view: CapyView.onsen,
        mood: CapyMood.active,
        hops: hops,
        flushes: flushes,
        queued: queued,
        playOnShow: CapyOneShot.wave,
      ),
    );
    await tester.pumpWidget(capy(0, 0, 2));
    final rig = source.rigs.single;
    expect(rig.fired, ['wave']);
    expect(rig.queued, 2);
    await tester.pumpWidget(capy(1, 2, 1));
    expect(rig.fired, ['wave', 'flush', 'flush', 'hop']);
    expect(rig.queued, 1);
    expect(rig.mood, CapyMood.active);
    await tester.pumpWidget(const SizedBox());
    expect(rig.disposed, isTrue);
  });

  testWidgets('one celebrate per increase; playOnShow once per mount', (
    tester,
  ) async {
    Widget capy(int celebrates) => host(
      Capy(
        view: CapyView.front,
        celebrates: celebrates,
        playOnShow: CapyOneShot.swapKey,
      ),
    );
    await tester.pumpWidget(capy(0));
    final rig = source.rigs.single;
    expect(rig.fired, ['swapKey']);
    await tester.pumpWidget(capy(1));
    await tester.pumpWidget(capy(1));
    expect(rig.fired, ['swapKey', 'celebrate'], reason: 'no replay on rebuild');
    await tester.pumpWidget(capy(3));
    expect(rig.fired, ['swapKey', 'celebrate', 'celebrate', 'celebrate']);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(capy(0));
    expect(source.rigs.last.fired, ['swapKey'], reason: 'a new mount plays');
  });

  testWidgets('lookX reaches the rig, clamped, and is 0 under reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const Capy(view: CapyView.front, lookX: 0.6, animated: true)),
    );
    final rig = source.rigs.single;
    expect(rig.lookX, 0.6);
    await tester.pumpWidget(
      host(const Capy(view: CapyView.front, lookX: 3, animated: true)),
    );
    expect(rig.lookX, 1);
    await tester.pumpWidget(
      host(
        const Capy(view: CapyView.front, lookX: 0.6, animated: true),
        reduced: true,
      ),
    );
    expect(rig.lookX, 0, reason: 'nothing glides under reduced motion (F3)');
  });

  test('pinLookX: no digits looks at you, dot 1 = -1 … dot 6 = +1', () {
    expect(pinLookX(0), 0);
    expect(pinLookX(1), -1);
    expect(pinLookX(6), closeTo(1, 1e-9));
    expect(pinLookX(3), closeTo(-0.2, 1e-9));
    // Delete moves it back one dot.
    expect(pinLookX(4), lessThan(pinLookX(5)));
  });

  test('X1–X10 placement table matches the spec', () {
    String row(CapySpot s) =>
        '${s.view.name} ${s.mood.name} ${s.size.toInt()} ${s.animated ? 'anim' : 'still'}'
        '${s.pose == CapyPose.none ? '' : ' ${s.pose.name}'}${s.playOnShow == null ? '' : ' ${s.playOnShow!.name}'}';
    expect(capySpots.map((k, v) => MapEntry(k.split(' ').first, row(v))), {
      'X1': 'sit chill 112 still wave',
      'X2': 'sit chill 130 still',
      'X3': 'sit worried 120 still',
      'X4': 'sit chill 120 still',
      'X5': 'sit worried 120 still',
      'X6': 'sit chill 108 anim',
      'X7': 'front worried 72 still',
      'X8': 'sit active 72 still lookAround',
      'X9': 'front focused 72 still guard',
      'X10': 'sit chill 120 still',
    });
    // F2: E1 (the bath) + X6 are the only animated ones, and never > 2 a screen.
    expect(capySpots.values.where((s) => s.animated).length, 1);
  });
}
