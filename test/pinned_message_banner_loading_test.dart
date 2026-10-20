import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/pinned_message_banner.dart';

Message _message({required String state}) => Message(
  localId: 'pinned-message',
  conversationId: 'g1',
  senderId: 'u_peer',
  type: 'text',
  status: 'sent',
  createdAt: DateTime(2026, 10, 17),
  decryptState: state,
  ciphertextLength: 96,
);

Message _messageWithId(String id) => Message(
  localId: id,
  conversationId: 'g1',
  senderId: 'u_peer',
  type: 'image',
  status: 'sent',
  createdAt: DateTime(2026, 10, 17),
);

void main() {
  setUp(bodyCache.clear);

  testWidgets('terminal pinned body shows one explicit decrypt state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pinnedMessagesProvider(
            'g1',
          ).overrideWith((ref) => Stream.value([_message(state: 'failed')])),
          messageBodyProvider.overrideWith(
            (ref, id) => Completer<String?>().future,
          ),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const Scaffold(body: PinnedMessageBanner(conversationId: 'g1')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text("Can't decrypt"), findsOneWidget);
    expect(find.text('Ask them to resend'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('🔒 Encrypted'), findsNothing);
    expect(find.byKey(const ValueKey('body-skeleton-96')), findsNothing);
  });

  testWidgets('transient pinned body shows the neutral skeleton', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pinnedMessagesProvider(
            'g1',
          ).overrideWith((ref) => Stream.value([_message(state: 'pending')])),
          messageBodyProvider.overrideWith(
            (ref, id) => Completer<String?>().future,
          ),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const Scaffold(body: PinnedMessageBanner(conversationId: 'g1')),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('body-skeleton-96')), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(find.text("Can't decrypt"), findsNothing);
  });

  testWidgets('pinned counter stays in range when the list shrinks', (
    tester,
  ) async {
    final updates = StreamController<List<Message>>();
    addTearDown(updates.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pinnedMessagesProvider('g1').overrideWith((ref) => updates.stream),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const Scaffold(body: PinnedMessageBanner(conversationId: 'g1')),
        ),
      ),
    );

    updates.add([_messageWithId('first'), _messageWithId('second')]);
    await tester.pump();
    await tester.tap(find.byTooltip('Next pinned message'));
    await tester.pump();
    expect(find.text('Pinned · 2/2'), findsOneWidget);

    updates.add([_messageWithId('only')]);
    await tester.pump();
    expect(find.text('Pinned · 1/1'), findsOneWidget);
    expect(find.textContaining('Pinned · 2/1'), findsNothing);
  });
}
