import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/chat/screens/chat_screen.dart';
import 'package:kuch_bhi/services/presence_service.dart';

void main() {
  testWidgets('chat Last seen subtitle fits at 200% text scale', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: warmPopLight(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            // The app bar gives the subtitle one line of height; a wrap overflows.
            body: SizedBox(
              width: 120,
              height: 40,
              child: Column(
                children: [
                  ChatPresenceSubtitle(
                    presence: OtherUserPresence(lastSeen: DateTime.utc(2000, 1, 1)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}
