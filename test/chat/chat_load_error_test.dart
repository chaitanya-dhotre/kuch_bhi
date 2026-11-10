import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/chat/screens/chat_screen.dart';
import 'package:kuch_bhi/features/mascot/capy.dart';

void main() {
  testWidgets('chat load error uses the key mascot and keeps retry', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(body: ChatLoadError(onRetry: () => retried = true)),
      ),
    );

    final mascot = tester.widget<Capy>(find.byType(Capy));
    expect(mascot.view, CapyView.front);
    expect(mascot.pose, CapyPose.guard);
    expect(mascot.size, 72);
    expect(find.text("Couldn't load this chat."), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
