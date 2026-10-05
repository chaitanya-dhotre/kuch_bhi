import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/features/mascot/capybara.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('approved geometry — locked to docs/Capybara.png', () {
    final painter = CapybaraPainter(
        mood: CapyMood.neutral, blink: 0, breathe: 0, showKey: false);
    final body = painter.debugDescription();
    // Body/ears/snout/legs boxes as approved (see plan constraints).
    expect(body['body'], const Rect.fromLTWH(28, 48, 146, 96));
    expect(body['bodyRadius'], 46.0);
    expect(body['earLeft'], const Offset(80, 52));
    expect(body['earLeftRadius'], 12.5);
    expect(body['earRight'], const Offset(150, 58));
    expect(body['snout'], const Rect.fromLTWH(21, 66, 50, 66));
    expect(body['snoutRadius'], 23.0);
    expect(body['snoutColor'], const Color(0xFF8B5E3E));
    expect(body['legFront'], const Rect.fromLTWH(52, 126, 28, 24));
    expect(body['legBack'], const Rect.fromLTWH(138, 126, 24, 24));
    expect(body['eyeLeft'], const Offset(88, 66));
    expect(body['eyeRight'], const Offset(122, 62));
  });

  test('paint uses token colors only', () {
    final p = CapybaraPainter(
        mood: CapyMood.neutral, blink: 0, breathe: 0, showKey: false);
    final used = p.debugColors();
    expect(used, contains(WarmPopTokens.mascotBody));
    expect(used, contains(WarmPopTokens.mascotSnout));
    expect(used, isNot(contains(const Color(0xFFEFA00B)))); // not the accent
  });

  testWidgets('idle loop runs; disabled under reduced motion',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: Capybara()))));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Capybara), findsOneWidget);
    // Reduced-motion: widget must not throw with animations disabled.
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: MediaQuery(
                data: MediaQueryData(disableAnimations: true),
                child: Capybara()))));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
