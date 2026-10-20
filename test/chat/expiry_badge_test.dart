import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/chat/widgets/expiry_badge.dart';

Widget _host(Widget child) => MaterialApp(
  theme: warmPopLight(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('expiry badge renders timer glyph and label', (tester) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 120,
          height: 80,
          child: Stack(children: [ExpiryBadge(label: '23h')]),
        ),
      ),
    );

    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.text('23h'), findsOneWidget);
  });

  testWidgets('expired placeholder renders supplied glyph and copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 200,
          height: 120,
          child: ExpiredPlaceholder(glyph: Icons.timer_off_outlined),
        ),
      ),
    );

    expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
    expect(find.text('Media expired'), findsOneWidget);
  });
}
