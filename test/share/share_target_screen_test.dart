// 12.1 C18 / D1–D12, G1–G3: the Send to picker.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/router/app_router.dart';
import 'package:kuch_bhi/core/widgets/chat_tile.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/features/share/share_payload.dart';
import 'package:kuch_bhi/services/share_in_service.dart';

import 'share_harness.dart';

final _convs = [
  groupChat('g1', 'Weekend crew', adminsOnly: true),
  direct('c1', 'Asha'),
  direct('c2', 'Rohan'),
  groupChat('g2', 'Family', members: 8),
];

final _five = shareMap([
  ('image/jpeg', '1.jpg'),
  ('image/jpeg', '2.jpg'),
  ('image/jpeg', '3.jpg'),
  ('video/mp4', '4.mp4'),
  ('video/mp4', '5.mp4'),
]);

Future<ShareHarness> _open(
  WidgetTester tester, {
  Map<String, Object?>? share,
  List<Conversation>? convs,
  GroupRuleRepo? repo,
  double textScale = 1,
  String? font,
  bool reduceMotion = false,
}) async {
  final h = await pumpShareApp(
    tester,
    initial: AppRoutes.home,
    share: share ?? _five,
    convs: convs ?? _convs,
    repo: repo,
    textScale: textScale,
    font: font,
    reduceMotion: reduceMotion,
  );
  await h.start();
  await tester.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('bar, summary, rows in conversationsProvider order; group '
      'subtitle is its member count, no time or badge', (tester) async {
    await _open(tester);
    expect(find.text('Send to'), findsOneWidget);
    expect(find.text('3 photos and 2 videos'), findsOneWidget);
    expect(find.text('Search chats'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    final titles = [
      for (final t in tester.widgetList<ChatTile>(find.byType(ChatTile)))
        t.title,
    ];
    expect(titles, ['Weekend crew', 'Asha', 'Rohan', 'Family']);
    expect(find.text('5 members'), findsOneWidget);
    expect(find.text('8 members'), findsOneWidget);
    for (final t in tester.widgetList<ChatTile>(find.byType(ChatTile))) {
      expect((t.time, t.unreadCount), (null, 0));
      if (!t.isGroup) expect(t.subtitle, '');
    }
  });

  testWidgets('search filters by name; no match line', (tester) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'as');
    await tester.pump();
    expect(find.byType(ChatTile), findsOneWidget);
    expect(find.text('Asha'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zoya');
    await tester.pump();
    expect(find.byType(ChatTile), findsNothing);
    expect(find.text('No chats match ‘zoya’.'), findsOneWidget);
  });

  testWidgets('no chats → empty state, no mascot', (tester) async {
    await _open(tester, convs: const []);
    expect(find.text('No chats yet'), findsOneWidget);
    expect(find.text('Add a friend first, then share again.'), findsOneWidget);
  });

  testWidgets('a chat you can\'t send in → toast, picker stays, no copy',
      (tester) async {
    final h = await _open(tester, repo: GroupRuleRepo(roles: {'g1': 'member'}));
    await tester.tap(find.text('Weekend crew'));
    await tester.pumpAndSettle();
    expect(find.text("You can't send messages in this chat."), findsOneWidget);
    expect(find.text('Send to'), findsOneWidget);
    expect(h.copies, 0);
  });

  testWidgets('tap → one copy per kept item, only now, with "Opening 2 of 5"; '
      'then the chat replaces the picker holding the share', (tester) async {
    final h = await _open(tester);
    expect(h.copies, 0);
    final gates = [for (var i = 0; i < 5; i++) Completer<void>()];
    h.onCopy = (call, n) async {
      await gates[n - 1].future;
      return '/cache/share_in/$n/${call.arguments['name']}';
    };
    await tester.tap(find.text('Asha'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Opening 1 of 5'), findsOneWidget);
    gates[0].complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('Opening 2 of 5'), findsOneWidget);
    expect(h.copies, 2);
    for (final g in gates.skip(1)) {
      g.complete();
    }
    await tester.pumpAndSettle();

    expect(h.copies, 5);
    final args = h.calls.where((c) => c.method == 'copyShared').first.arguments;
    expect(args['maxBytes'], 100 * 1024 * 1024);
    expect(find.text('Send to'), findsNothing);
    expect(find.text('chat c1'), findsOneWidget);
    final ready = h.container.read(chatShareProvider('c1'))!;
    expect(ready.chatName, 'Asha');
    expect(ready.files.map((f) => f.kind), [
      SharedKind.photo, SharedKind.photo, SharedKind.photo, //
      SharedKind.video, SharedKind.video,
    ]);
    expect(h.container.read(pendingShareProvider), isNull);

    // Back from the chat goes where Back from the picker would have.
    h.router.pop();
    await tester.pumpAndSettle();
    expect(find.text('at /home'), findsOneWidget);
  });

  testWidgets('a second tap during the send check starts nothing', (
    tester,
  ) async {
    final h = await _open(tester);
    await tester.tap(find.text('Family'));
    await tester.tap(find.text('Family'));
    await tester.pumpAndSettle();
    expect(h.copies, 5, reason: 'one copy loop');
    expect(h.methods.where((m) => m == 'clearShared'), hasLength(1),
        reason: 'only the start-up clear; the hand-off is never wiped');
    expect(h.container.read(chatShareProvider('g2'))!.files, hasLength(5));
  });

  testWidgets('one copy fails → left-out toast; too big counts as too big',
      (tester) async {
    final h = await _open(tester);
    h.onCopy = (call, n) => switch (n) {
      2 => throw PlatformException(code: 'unreadable'),
      _ => '/cache/share_in/$n/x.jpg',
    };
    await tester.tap(find.text('Rohan'));
    await tester.pumpAndSettle();
    expect(find.text("1 item couldn't be opened and was left out."),
        findsOneWidget);
    expect(h.container.read(chatShareProvider('c2'))!.files, hasLength(4));

    await h.arrive(shareMap([('image/jpeg', 'a.jpg'), ('video/mp4', 'b.mp4')]));
    await tester.pumpAndSettle();
    h.onCopy = (call, n) => n.isEven
        ? throw PlatformException(code: 'too_big')
        : '/cache/share_in/$n/a.jpg';
    await tester.tap(find.text('Rohan'));
    await tester.pumpAndSettle();
    expect(find.text('1 item is over 100 MB and was left out.'), findsOneWidget);
  });

  testWidgets('nothing copies → "Couldn\'t open…", picker stays',
      (tester) async {
    final h = await _open(tester);
    h.onCopy = (call, n) => throw PlatformException(code: 'unreadable');
    await tester.tap(find.text('Asha'));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't open what was shared."), findsOneWidget);
    expect(find.text('Send to'), findsOneWidget);
    expect(h.methods.last, 'clearShared');
  });

  testWidgets('✕ during the copy → no further copies, share_in/ cleared',
      (tester) async {
    final h = await _open(tester);
    final gate = Completer<void>();
    h.onCopy = (call, n) async {
      await gate.future;
      return '/cache/share_in/$n/x';
    };
    await tester.tap(find.text('Asha'));
    await tester.pump();
    await tester.pump();
    expect(h.copies, 1);
    await tester.tap(find.byTooltip('Cancel sharing'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(h.copies, 1, reason: 'stopped');
    expect(h.methods, contains('clearShared'));
    expect(find.text('Send to'), findsNothing);
    expect(find.text('chat c1'), findsNothing);
    expect(h.container.read(chatShareProvider('c1')), isNull);
  });

  testWidgets('already in that chat → the picker just pops, no second chat',
      (tester) async {
    final h = await pumpShareApp(tester, convs: _convs);
    h.router.go(AppRoutes.chat, extra: _convs[1]);
    await tester.pumpAndSettle();
    await h.start();
    await h.arrive(shareMap([], text: 'hi'));
    await tester.pumpAndSettle();
    expect(find.text('Text'), findsOneWidget);
    await tester.tap(find.text('Asha'));
    await tester.pumpAndSettle();
    expect(find.text('Send to'), findsNothing);
    expect(find.text('chat c1'), findsOneWidget);
    expect(h.router.routerDelegate.currentConfiguration.matches, hasLength(1));
    expect(h.container.read(chatShareProvider('c1'))!.text, 'hi');
    expect(h.copies, 0);
  });

  testWidgets('semantics: header, Cancel sharing button, live region',
      (tester) async {
    final handle = tester.ensureSemantics();
    final h = await _open(tester);
    expect(
      tester.getSemantics(find.text('Send to')),
      matchesSemantics(label: 'Send to', isHeader: true),
    );
    expect(find.bySemanticsLabel('3 photos and 2 videos'), findsOneWidget);
    expect(
      tester.getSemantics(find.byTooltip('Cancel sharing')),
      isSemantics(tooltip: 'Cancel sharing', isButton: true),
    );
    final gate = Completer<void>();
    h.onCopy = (call, n) async {
      await gate.future;
      return '/x/$n/y';
    };
    await tester.tap(find.text('Asha'));
    await tester.pump();
    await tester.pump();
    final live = tester.getSemantics(find.text('Opening 1 of 5'));
    expect(live.flagsCollection.isLiveRegion, isTrue);
    gate.complete();
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('reduced motion: the picker is up after one frame',
      (tester) async {
    final h = await pumpShareApp(
      tester,
      initial: AppRoutes.home,
      share: _five,
      convs: _convs,
      reduceMotion: true,
    );
    await h.start();
    await tester.pump();
    final route = ModalRoute.of(tester.element(find.text('Send to')))!;
    expect(route.transitionDuration, Duration.zero);
  });

  for (final font in [null, 'PlusJakartaSans']) {
    testWidgets('360×640 at 200% (${font ?? 'system'}): bar, rows, empty '
        'state and scrim fit', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = await _open(tester, textScale: 2, font: font);
      expect(tester.takeException(), isNull);
      final gate = Completer<void>();
      h.onCopy = (call, n) async {
        await gate.future;
        return '/x/$n/y';
      };
      await tester.tap(find.text('Asha'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Opening 1 of 5'), findsOneWidget);
      expect(tester.takeException(), isNull);
      gate.complete();
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox());
      await _open(tester, convs: const [], textScale: 2, font: font);
      expect(find.text('No chats yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
