import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/chat/screens/chat_screen.dart';
import 'package:kuch_bhi/features/mascot/capybara.dart';

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

    final mascot = tester.widget<Capybara>(find.byType(Capybara));
    expect(mascot.showKey, isTrue);
    expect(mascot.size, const Size(72, 65));
    expect(find.text("Couldn't load this chat."), findsOneWidget);

    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}
