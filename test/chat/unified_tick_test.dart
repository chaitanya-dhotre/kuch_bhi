import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/features/chat/widgets/delivery_tick.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: warmPopLight(),
    home: Scaffold(body: child),
  );
}

void main() {
  group('DeliveryTick', () {
    testWidgets('queued uses the clock and inkFaint', (tester) async {
      await tester.pumpWidget(_host(const DeliveryTick(status: 'queued')));

      final icon = tester.widget<Icon>(find.byIcon(Icons.schedule));
      expect(icon.size, 13);
      expect(icon.color, WarmPopTokens.inkFaint);
    });

    testWidgets('legacy pending remains queued', (tester) async {
      await tester.pumpWidget(_host(const DeliveryTick(status: 'pending')));

      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('sending uses a token-colored spinner', (tester) async {
      await tester.pumpWidget(_host(const DeliveryTick(status: 'sending')));

      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.color, WarmPopTokens.inkFaint);
      expect(spinner.strokeWidth, 2);
      expect(
        tester.getSize(find.byType(CircularProgressIndicator)),
        const Size.square(13),
      );
    });

    testWidgets('sent uses one check and delivered uses a dimmed pair', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const DeliveryTick(status: 'sent')));

      final sent = tester.widget<Icon>(find.byIcon(Icons.check));
      expect(sent.size, 13);
      expect(sent.color, WarmPopTokens.inkSoft);
      expect(find.byIcon(Icons.done_all), findsNothing);

      await tester.pumpWidget(
        _host(const DeliveryTick(status: 'delivered', size: 17)),
      );
      final delivered = tester.widget<Icon>(find.byIcon(Icons.done_all));
      expect(delivered.size, 17);
      expect(delivered.color, WarmPopTokens.inkSoft.withValues(alpha: .54));
    });

    testWidgets('read uses an info-blue pair', (tester) async {
      await tester.pumpWidget(_host(const DeliveryTick(status: 'read')));

      final icon = tester.widget<Icon>(find.byIcon(Icons.done_all));
      expect(icon.color, WarmPopTokens.info);
    });

    testWidgets('failed uses the warning glyph and error token', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const DeliveryTick(status: 'failed')));

      final icon = tester.widget<Icon>(
        find.byIcon(Icons.warning_amber_rounded),
      );
      expect(icon.size, 13);
      expect(icon.color, WarmPopTokens.error);
    });
  });
}
