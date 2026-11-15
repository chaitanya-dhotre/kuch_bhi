// Motion spec test gates 2, 2a (C1), 3, 4 and 6 (chat).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/bubble_entrance.dart';
import 'package:kuch_bhi/features/chat/widgets/expiry_badge.dart';
import 'package:kuch_bhi/features/chat/widgets/reaction_bar.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

Message _m(String id, {String from = 'me', String type = 'text'}) => Message(
  localId: id,
  conversationId: 'c1',
  senderId: from,
  type: type,
  status: 'sent',
  createdAt: DateTime(2026, 11, 15),
);

const _flight = SendFlight('hi', Rect.fromLTWH(60, 700, 280, 48));

void main() {
  group('gate 2 / 3: ChatEntrances (C1–C3)', () {
    test('history gets none; a new id gets one entrance, once', () {
      final e = ChatEntrances();
      addTearDown(e.dispose);
      final history = [_m('h2'), _m('h1', from: 'them')];
      e.observe(history, myId: 'me', atBottom: true);
      expect(e.take('h1'), isNull);
      expect(e.take('h2'), isNull);

      e.observe([_m('n1', from: 'them'), ...history], myId: 'me', atBottom: true);
      expect(e.take('n1'), BubbleMotion.arrive);
      // A re-emit of the same list (refetch, resync) replays nothing.
      e.observe([_m('n1', from: 'them'), ...history], myId: 'me', atBottom: true);
      expect(e.take('n1'), isNull);
    });

    test('older history paged in at the end never animates', () {
      final e = ChatEntrances();
      addTearDown(e.dispose);
      e.observe([_m('a'), _m('b')], myId: 'me', atBottom: true);
      e.observe([_m('a'), _m('b'), _m('old1'), _m('old2')],
          myId: 'me', atBottom: true);
      expect(e.take('old1'), isNull);
      expect(e.take('old2'), isNull);
    });

    test('2a: a short text send grows; long, media and scrolled-up rise', () {
      final e = ChatEntrances();
      addTearDown(e.dispose);
      e.observe(const [], myId: 'me', atBottom: true);

      e.sending(_flight);
      e.observe([_m('t1')], myId: 'me', atBottom: true);
      expect(e.take('t1'), BubbleMotion.grow);
      expect(e.takeFlight('t1'), _flight);

      e.sending(null); // > 4 lines: the screen passes no flight
      e.observe([_m('t2'), _m('t1')], myId: 'me', atBottom: true);
      expect(e.take('t2'), BubbleMotion.send);

      e.sending(_flight);
      e.observe([_m('p1', type: 'image'), _m('t2'), _m('t1')],
          myId: 'me', atBottom: true);
      expect(e.take('p1'), BubbleMotion.send);

      e.sending(_flight);
      e.observe([_m('t3'), _m('p1', type: 'image'), _m('t2'), _m('t1')],
          myId: 'me', atBottom: false);
      expect(e.take('t3'), BubbleMotion.send);
      expect(e.takeFlight('t3'), isNull);
    });

    test('2a: voice notes and stickers grow too', () {
      final e = ChatEntrances();
      addTearDown(e.dispose);
      e.observe(const [], myId: 'me', atBottom: true);
      const from = SendFlight(null, Rect.fromLTWH(0, 700, 300, 60));
      e.sending(from);
      e.observe([_m('v1', type: 'voice')], myId: 'me', atBottom: true);
      expect(e.take('v1'), BubbleMotion.grow);
      e.sending(from);
      e.observe([_m('s1', type: 'sticker'), _m('v1', type: 'voice')],
          myId: 'me', atBottom: true);
      expect(e.take('s1'), BubbleMotion.grow);
      expect(e.takeFlight('s1')!.text, isNull);
    });

    test('gate 3: scrolled up, theirs get no entrance and count below', () {
      final e = ChatEntrances();
      addTearDown(e.dispose);
      e.observe([_m('a')], myId: 'me', atBottom: true);
      final below = e.observe([_m('x', from: 'them'), _m('a')],
          myId: 'me', atBottom: false);
      expect(below, 1);
      expect(e.take('x'), isNull);
    });
  });

  Widget host(Widget child, {bool reduced = false}) => MaterialApp(
    theme: warmPopLight(),
    home: MediaQuery(
      data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduced),
      child: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    ),
  );

  Widget bubble(String text) => ChatBubbleFrame(isMine: true, child: Text(text));

  testWidgets('gate 2a: the send overlay lands on the bubble and is removed',
      (tester) async {
    await tester.pumpWidget(host(BubbleEntrance(
      motion: BubbleMotion.grow,
      flight: _flight,
      child: bubble('hi'),
    )));
    await tester.pump(); // the post-frame callback inserts the overlay
    expect(find.text('hi'), findsNWidgets(2), reason: 'real bubble + overlay');

    await tester.pump(const Duration(milliseconds: 290));
    final real = find.text('hi').first;
    final fly = find.text('hi').last;
    final bubbleBox = tester.getRect(find.ancestor(
      of: real,
      matching: find.byWidgetPredicate((w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color != null),
    ).first);
    final flyBox = tester.getRect(find.ancestor(
      of: fly,
      matching: find.byType(DecoratedBox),
    ).first);
    for (final (a, b) in [
      (flyBox.left, bubbleBox.left),
      (flyBox.top, bubbleBox.top),
      (flyBox.right, bubbleBox.right),
      (flyBox.bottom, bubbleBox.bottom),
    ]) {
      expect(a, closeTo(b, 1.0));
    }

    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('hi'), findsOneWidget, reason: 'overlay removed');
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: find.text('hi'), matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, 1, reason: 'the real bubble swapped in');
  });

  testWidgets('gate 2a: the flying text uses the app style, not the debug one',
      (tester) async {
    await tester.pumpWidget(host(BubbleEntrance(
      motion: BubbleMotion.grow,
      flight: const SendFlight('Happy birthday', Rect.fromLTWH(60, 700, 280, 48)),
      child: const ChatBubbleFrame(
        isMine: true,
        child: Text(
          'Happy birthday',
          style: TextStyle(fontSize: 15, height: 20 / 15),
        ),
      ),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final paragraphs =
        tester.renderObjectList<RenderParagraph>(find.text('Happy birthday'));
    expect(paragraphs, hasLength(2));
    for (final p in paragraphs) {
      expect(p.text.style?.decoration, isNot(TextDecoration.underline));
    }
    // One line, as in the bubble.
    final fly = paragraphs.last;
    expect(fly.size.height, paragraphs.first.size.height,
        reason: 'wraps exactly as the bubble does');
    await tester.pumpAndSettle();
  });

  testWidgets('gate 2a: an emoji or sticker flies a snapshot, then rests',
      (tester) async {
    await tester.pumpWidget(host(BubbleEntrance(
      motion: BubbleMotion.grow,
      flight: const SendFlight(null, Rect.fromLTWH(60, 700, 280, 48)),
      // A sticker: no fill, and a narrow box at the left (the swipe icon)
      // that must not be mistaken for the bubble.
      child: const Stack(
        children: [
          Positioned(left: 16, top: 0, child: SizedBox(width: 22, height: 22)),
          ChatBubbleFrame(
            isMine: true,
            chrome: false,
            padding: EdgeInsets.zero,
            child: SizedBox(width: 120, height: 120, child: Text('sticker')),
          ),
        ],
      ),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The flying copy is the size of the sticker, not the 22 dp icon.
    final fly = tester.getSize(find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_ShotPainter',
    ));
    expect(fly.width, greaterThan(40));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: find.text('sticker'), matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, 1);
  });

  testWidgets('gate 4 (L6): two sends 50 ms apart both end at rest',
      (tester) async {
    final snap = ValueNotifier(0);
    addTearDown(snap.dispose);
    Widget row(String id, {required bool second}) => BubbleEntrance(
      key: ValueKey(id),
      motion: BubbleMotion.grow,
      flight: _flight,
      snap: snap,
      child: bubble(id),
    );
    await tester.pumpWidget(host(Column(
      mainAxisSize: MainAxisSize.min,
      children: [row('one', second: false)],
    )));
    await tester.pump(const Duration(milliseconds: 50));
    snap.value++; // the second send
    await tester.pumpWidget(host(Column(
      mainAxisSize: MainAxisSize.min,
      children: [row('one', second: false), row('two', second: true)],
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    for (final o in tester.widgetList<FadeTransition>(find.byType(FadeTransition))) {
      expect(o.opacity.value, 1);
    }
  });

  testWidgets('C10: a leaving row closes, then reports gone', (tester) async {
    var gone = false;
    Widget row(bool leaving) => BubbleEntrance(
      key: const ValueKey('r'),
      motion: null,
      leaving: leaving,
      onLeft: () => gone = true,
      child: bubble('bye'),
    );
    await tester.pumpWidget(host(row(false)));
    await tester.pumpWidget(host(row(true)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(gone, isFalse);
    await tester.pumpAndSettle();
    expect(gone, isTrue);
  });

  group('gate 6: reactions (C5)', () {
    testWidgets('add, change count, remove: chips end at scale 1 or gone',
        (tester) async {
      final repo = _Repo([
        const ReactionGroup(emoji: '👍', count: 1, isMine: false),
      ]);
      addTearDown(repo.dispose);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          messageRepositoryProvider.overrideWithValue(repo),
          isOnlineProvider.overrideWith((ref) => Stream<bool>.value(true)),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const Scaffold(
            body: ReactionBar(messageServerId: 'm1', isMine: false),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('👍 1'), findsOneWidget);

      Future<void> emit(List<ReactionGroup> g) async {
        repo.groups = g;
        repo.changes.add('m1');
        await tester.pump();
        await tester.pump();
      }

      // Add: the new chip starts small and springs to 1.
      await emit(const [
        ReactionGroup(emoji: '👍', count: 1, isMine: false),
        ReactionGroup(emoji: '❤️', count: 1, isMine: true),
      ]);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_scaleOf(tester, '❤️'), lessThan(1));
      await tester.pumpAndSettle();
      expect(_scaleOf(tester, '❤️'), 1);

      // Count change rolls, then rests as one Text.
      await emit(const [
        ReactionGroup(emoji: '👍', count: 2, isMine: false),
        ReactionGroup(emoji: '❤️', count: 1, isMine: true),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('👍 2'), findsOneWidget);

      // Remove: shrinks, then is gone.
      await emit(const [ReactionGroup(emoji: '👍', count: 2, isMine: false)]);
      expect(find.byKey(const Key('reaction-chip-m1-❤️')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reaction-chip-m1-❤️')), findsNothing);
      expect(_scaleOf(tester, '👍'), 1);
    });
  });
}

double _scaleOf(WidgetTester tester, String emoji) {
  final chip = find.byKey(Key('reaction-chip-m1-$emoji'));
  final t = tester.widget<ScaleTransition>(
    find.ancestor(of: chip, matching: find.byType(ScaleTransition)).first,
  );
  return t.scale.value;
}

class _Repo extends FakeMessageRepository {
  _Repo(this.groups);
  List<ReactionGroup> groups;
  final changes = StreamController<String>.broadcast();

  @override
  Stream<String> get reactionsChanges => changes.stream;

  @override
  Future<List<ReactionGroup>> getReactions(String messageServerId) async =>
      groups;

  Future<void> dispose() => changes.close();
}
