// Chat calm (spec docs/design/pages/chat-calm.md) gates 1 and 2: sizing (A)
// and corners (B1).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/chat/widgets/expiry_badge.dart';

void main() {
  group('gate 1: A1 / A2 / A3', () {
    // W → (A1 text max, A2 attachment width). 360 is below A2's floor.
    final table = {
      360.0: (280.8, 240.0),
      384.0: (299.52, 253.44),
      411.0: (320.58, 271.26),
      554.0: (420.0, 340.0),
    };
    table.forEach((w, expected) {
      test('W = $w', () {
        expect(ChatBubbleGeometry.textMaxWidth(w), closeTo(expected.$1, .01));
        final a2 = ChatBubbleGeometry.attachmentWidth(w);
        expect(a2, closeTo(expected.$2, .01));
        // A3 for 3:1, 16:9, 1:1, 9:16: width ÷ aspect, clamped to
        // 0.56 × width … 1.25 × width.
        expect(ChatBubbleGeometry.mediaHeight(a2, 3), closeTo(0.56 * a2, .01));
        expect(
          ChatBubbleGeometry.mediaHeight(a2, 16 / 9),
          closeTo(a2 * 9 / 16, .01),
        );
        expect(ChatBubbleGeometry.mediaHeight(a2, 1), closeTo(a2, .01));
        expect(
          ChatBubbleGeometry.mediaHeight(a2, 9 / 16),
          closeTo(1.25 * a2, .01),
        );
        // A5: album tiles.
        expect(ChatBubbleGeometry.albumTileHeight(a2), closeTo(0.72 * a2, .01));
      });
    });

    test('A4: an unknown aspect falls back to 4:3', () {
      expect(ChatBubbleGeometry.mediaHeight(300, 0), closeTo(225, .01));
    });

    test('A7 + C1/C2/C4/C5: margins and spacing', () {
      expect(
        ChatBubbleGeometry.margin(isMine: true),
        const EdgeInsets.only(right: 12),
      );
      expect(
        ChatBubbleGeometry.margin(isMine: false),
        const EdgeInsets.only(left: 12),
      );
      expect(ChatBubbleGeometry.runGap, 2);
      expect(ChatBubbleGeometry.newRunGap, 12);
      expect(
        ChatBubbleGeometry.contentPadding,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      );
      expect(ChatBubbleGeometry.attachmentPadding, const EdgeInsets.all(10));
      expect(ChatBubbleGeometry.leadingSize, 40);
    });
  });

  group('gate 2: B1 corners', () {
    const r18 = Radius.circular(18);
    const r6 = Radius.circular(6);
    // Corner table: (topLeft, topRight, bottomLeft, bottomRight).
    // "start" = lone or first of a run; later bubbles share one shape.
    final cases = <(String, bool), (Radius, Radius, Radius, Radius)>{
      ('mine', true): (r18, r18, r18, r6),
      ('mine', false): (r18, r6, r18, r6),
      ('theirs', true): (r18, r18, r6, r18),
      ('theirs', false): (r6, r18, r6, r18),
    };
    cases.forEach((key, c) {
      test('${key.$1}, ${key.$2 ? 'first or lone' : 'middle or last'}', () {
        final r = ChatBubbleGeometry.radius(
          isMine: key.$1 == 'mine',
          runStart: key.$2,
        );
        expect(r.topLeft, c.$1);
        expect(r.topRight, c.$2);
        expect(r.bottomLeft, c.$3);
        expect(r.bottomRight, c.$4);
      });
    });
  });

  testWidgets('B5: the time line is 11/14 inkSoft with the canonical tick', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: ChatBubbleTimestamp(
            isMine: true,
            createdAt: DateTime(2026, 10, 18, 12, 34),
            status: 'delivered',
            starred: true,
          ),
        ),
      ),
    );
    final timestamp = tester.widget<Text>(find.text('12:34'));
    expect(timestamp.style!.fontSize, 11);
    expect(timestamp.style!.height, closeTo(14 / 11, .001));
    expect(timestamp.style!.color, const Color(0xFF6E655A));
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget, reason: 'B4');
  });
}
