import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/app_avatar.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/expiry_badge.dart';
import 'package:kuch_bhi/features/chat/widgets/message_bubble.dart';

/// A group sender's initial disc sits off the screen edge by the bubble's
/// near margin, with the bubble's own margin as the gap after it.
void main() {
  testWidgets('sender disc keeps the near margin from the screen edge',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        outboxStatusProvider.overrideWith((ref, c) => Stream.value(const [])),
        messageBodyProvider.overrideWith((ref, id) async => 'hello group'),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: ListView(children: [
            MessageBubble(
              message: Message(
                localId: 'l1',
                conversationId: 'c1',
                senderId: 's1',
                type: 'text',
                status: 'sent',
                createdAt: DateTime(2026, 10, 31),
              ),
              isMine: false,
              senderName: 'Avium',
              isGroup: true,
            ),
          ]),
        ),
      ),
    ));
    await tester.pump();

    final disc = tester.getTopLeft(find.byType(AppAvatar));
    expect(disc.dx, ChatBubbleGeometry.nearMargin);
  });
}
