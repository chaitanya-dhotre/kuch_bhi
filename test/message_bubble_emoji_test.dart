import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/utils/emoji_utils.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/expiry_badge.dart';
import 'package:kuch_bhi/features/chat/widgets/message_bubble.dart';

Message _message(String localId) => Message(
  localId: localId,
  conversationId: 'c1',
  senderId: 'u1',
  type: 'text',
  status: 'sent',
  createdAt: DateTime(2026, 10, 18),
);

Future<ChatBubbleFrame> _pumpBubble(
  WidgetTester tester, {
  required String localId,
  required String body,
}) async {
  bodyCache.put(localId, body);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        messageBodyProvider.overrideWith((ref, id) async => body),
        outboxStatusProvider.overrideWith(
          (ref, conversationId) => Stream.value(const []),
        ),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: MessageBubble(message: _message(localId), isMine: false),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.widget<ChatBubbleFrame>(find.byType(ChatBubbleFrame));
}

void main() {
  setUp(bodyCache.clear);

  test(
    'emoji-only classification counts grapheme glyphs, not UTF-16 units',
    () {
      expect(isEmojiOnly('😀😀😀'), isTrue);
      expect(isEmojiOnly('😀😀😀😀'), isFalse);
      expect(isEmojiOnly('👨‍👩‍👧‍👦'), isTrue);
      expect(isEmojiOnly('😀 hello'), isFalse);
      expect(isEmojiOnly('😀!'), isFalse);
    },
  );

  testWidgets('three emoji glyphs use the chrome-less presentation', (
    tester,
  ) async {
    final frame = await _pumpBubble(
      tester,
      localId: 'emoji-three',
      body: '😀😀😀',
    );

    expect(frame.chrome, isFalse);
    expect(tester.widget<Text>(find.text('😀😀😀')).style?.fontSize, 40);
  });

  testWidgets('four emoji glyphs use the normal bubble', (tester) async {
    final frame = await _pumpBubble(
      tester,
      localId: 'emoji-four',
      body: '😀😀😀😀',
    );

    expect(frame.chrome, isTrue);
    expect(tester.widget<Text>(find.text('😀😀😀😀')).style?.fontSize, 15);
  });
}
