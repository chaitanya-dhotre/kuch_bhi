import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/chat/widgets/message_input.dart';

/// The mic records only on a hold. A quick tap must say so, above the button,
/// without covering the composer (a toast floated over it).
void main() {
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: warmPopLight(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MessageInput(conversationId: 'c1', onSend: (_) {}),
            ),
          ),
        ),
      ));

  final mic = find.byKey(const ValueKey('mic-action'));

  testWidgets('a quick tap on the mic shows "Hold to record" above it',
      (tester) async {
    await pump(tester);
    await tester.tap(mic);
    await tester.pump(const Duration(milliseconds: 200));

    final hint = find.text('Hold to record');
    expect(hint, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.getBottomLeft(hint).dy,
        lessThanOrEqualTo(tester.getTopLeft(mic).dy));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the mic tells a screen reader to hold it', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    expect(
        tester.getSemantics(find.bySemanticsLabel('Record voice message')),
        isSemantics(
            label: 'Record voice message',
            hint: 'Hold to record',
            isButton: true));
    semantics.dispose();
  });
}
