import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/message_bubble.dart';

Message _message({String decryptState = 'ready'}) => Message(
  localId: 'a11y-message',
  conversationId: 'conversation',
  senderId: 'sender',
  type: 'text',
  status: 'sent',
  createdAt: DateTime(2026, 10, 6, 13, 42),
  decryptState: decryptState,
  ciphertextLength: 42,
);

Widget _host({required Message message, required String? body}) =>
    ProviderScope(
      overrides: [
        outboxStatusProvider.overrideWith((ref, _) => Stream.value(const [])),
        messageBodyProvider.overrideWith((ref, _) async => body),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: MessageBubble(
            message: message,
            isMine: false,
            senderName: 'Ada',
          ),
        ),
      ),
    );

void main() {
  testWidgets('message row exposes one composed label without duplicate body', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(message: _message(), body: 'hello there'));
    await tester.pump();

    try {
      expect(
        find.bySemanticsLabel(
          'From Ada. hello there. Time 13:42. Status sent.',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('hello there'), findsNothing);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('unresolved rows expose a safe decrypt label', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(message: _message(decryptState: 'key_missing'), body: null),
    );
    await tester.pump();

    try {
      expect(
        find.bySemanticsLabel(
          "From Ada. Can't decrypt. Time 13:42. Status sent.",
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('cipher')), findsNothing);
    } finally {
      semantics.dispose();
    }
  });
}
