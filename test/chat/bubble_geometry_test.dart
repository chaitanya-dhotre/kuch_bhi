import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/chat/widgets/expiry_badge.dart';

Widget _host(Widget child) => MaterialApp(
  theme: warmPopLight(),
  home: Scaffold(
    body: MediaQuery(
      data: const MediaQueryData(size: Size(360, 800)),
      child: child,
    ),
  ),
);

void main() {
  test('shared geometry keeps the board-approved bubble law', () {
    expect(ChatBubbleGeometry.maxWidthFactor, 0.84);
    expect(ChatBubbleGeometry.nearMargin, 12);
    expect(ChatBubbleGeometry.farMargin, 64);
    expect(ChatBubbleGeometry.verticalMargin, 2);
    expect(
      ChatBubbleGeometry.margin(isMine: true),
      const EdgeInsets.only(left: 64, right: 12, top: 2, bottom: 2),
    );
    expect(
      ChatBubbleGeometry.margin(isMine: false),
      const EdgeInsets.only(left: 12, right: 64, top: 2, bottom: 2),
    );

    final mineEnd = ChatBubbleGeometry.radius(isMine: true, runEnd: true);
    expect(mineEnd.topLeft, const Radius.circular(18));
    expect(mineEnd.topRight, const Radius.circular(18));
    expect(mineEnd.bottomRight, const Radius.circular(6));
    expect(mineEnd.bottomLeft, const Radius.circular(18));

    final theirsMiddle = ChatBubbleGeometry.radius(
      isMine: false,
      runEnd: false,
    );
    expect(theirsMiddle.bottomLeft, const Radius.circular(18));
    expect(theirsMiddle.bottomRight, const Radius.circular(18));

    final theirsEnd = ChatBubbleGeometry.radius(isMine: false, runEnd: true);
    expect(theirsEnd.bottomLeft, const Radius.circular(6));
    expect(theirsEnd.bottomRight, const Radius.circular(18));
  });

  testWidgets('the shared frame owns width cap and mine-only shadow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 360,
          child: const ChatBubbleFrame(
            isMine: true,
            runEnd: true,
            child: SizedBox(width: 80, height: 20),
          ),
        ),
      ),
    );

    final mineContainer = tester.widget<Container>(
      find.descendant(
        of: find.byType(ChatBubbleFrame),
        matching: find.byType(Container),
      ),
    );
    expect(mineContainer.constraints!.maxWidth, closeTo(360 * 0.84, 0.01));
    final mineDecoration = mineContainer.decoration! as BoxDecoration;
    expect(mineDecoration.boxShadow, hasLength(1));

    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 360,
          child: const ChatBubbleFrame(
            isMine: false,
            runEnd: true,
            child: SizedBox(width: 80, height: 20),
          ),
        ),
      ),
    );
    final theirsContainer = tester.widget<Container>(
      find.descendant(
        of: find.byType(ChatBubbleFrame),
        matching: find.byType(Container),
      ),
    );
    final theirsDecoration = theirsContainer.decoration! as BoxDecoration;
    expect(theirsDecoration.boxShadow, isEmpty);
  });

  testWidgets('timestamp uses the shared 10.5px row and canonical tick', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ChatBubbleTimestamp(
          isMine: true,
          createdAt: DateTime(2026, 10, 18, 12, 34),
          status: 'delivered',
        ),
      ),
    );

    final timestamp = tester.widget<Text>(find.text('12:34'));
    expect(timestamp.style!.fontSize, 10.5);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
  });
}
