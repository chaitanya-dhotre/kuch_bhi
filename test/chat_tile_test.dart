import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/chat_tile.dart';

Widget host(Widget child) => MaterialApp(
  theme: warmPopLight(),
  home: Scaffold(body: ListView(children: [child])),
);

void main() {
  testWidgets('ChatTile renders title/subtitle/time, badge only when unread', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ChatTile(title: 'Aarav', subtitle: 'See you at 8', time: '13:33'),
      ),
    );
    expect(find.text('Aarav'), findsOneWidget);
    expect(find.text('See you at 8'), findsOneWidget);
    expect(find.text('13:33'), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('3'), findsNothing);
    await tester.pumpWidget(
      host(
        const ChatTile(title: 'Design Squad', subtitle: 'hi', unreadCount: 3),
      ),
    );
    expect(find.text('3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ChatTile runs onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      host(ChatTile(title: 'A', subtitle: 's', onTap: () => tapped = true)),
    );
    await tester.tap(find.byType(ListTile));
    expect(tapped, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('ChatTile fits at 200% text scale on a 360px screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: host(const ChatTile(
          title: 'An exceptionally long conversation name that must ellipsize',
          subtitle: 'A very long message preview that must ellipsize instead of overflowing',
        )),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'ChatTile renders pin, presence, unread clamp, and merged label',
    (tester) async {
      await tester.pumpWidget(
        host(
          const ChatTile(
            title: 'Aarav',
            subtitle: 'See you at 8',
            time: '09:42',
            unreadCount: 100,
            isPinned: true,
            isOnline: true,
          ),
        ),
      );

      expect(find.byIcon(Icons.push_pin), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Aarav.*Online.*100 unread.*pinned')),
        findsOneWidget,
      );
    },
  );

  testWidgets('ChatTile exposes one coherent semantics node', (tester) async {
    await tester.pumpWidget(
      host(
        ChatTile(
          title: 'Aarav',
          subtitle: 'See you at 8',
          onTap: () {},
          onLongPress: () {},
        ),
      ),
    );

    expect(find.bySemanticsLabel('Aarav, See you at 8'), findsOneWidget);
    expect(find.bySemanticsLabel('See you at 8'), findsNothing);
    expect(find.bySemanticsLabel('Aarav'), findsNothing);
  });
}
