// Bug wave 1 §1.1 / §1.2: a send that fails before the optimistic row lands
// must reach the user, never vanish in a swallowed catch.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/message_input.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

class _RejectingRepo implements MessageRepository {
  @override
  Future<void> sendMessage({
    required String conversationId,
    required String plaintext,
    String? replyToLocalId,
  }) async => throw StateError('You are no longer a member of this group.');

  @override
  Future<void> sendMediaMessage({
    required String conversationId,
    required String mediaType,
    required File mediaFile,
    File? thumbnailFile,
    String? quality,
    int? durationSeconds,
    String? durationText,
    int? videoWidth,
    int? videoHeight,
  }) async => throw StateError('session not ready');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

ProviderContainer _container() {
  final c = ProviderContainer(
    overrides: [messageRepositoryProvider.overrideWithValue(_RejectingRepo())],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test(
    '§1.1 a rejected text send reaches the caller and clears busy',
    () async {
      final c = _container();
      await expectLater(
        c
            .read(sendMessageProvider.notifier)
            .send(conversationId: 'g1', text: 'hi'),
        throwsStateError,
      );
      expect(c.read(sendMessageProvider), isFalse);
    },
  );

  test('§1.2 a rejected media send reaches the caller', () async {
    final c = _container();
    await expectLater(
      c
          .read(sendMediaMessageProvider.notifier)
          .send(
            conversationId: 'g1',
            mediaType: 'voice',
            mediaFile: File('missing.m4a'),
          ),
      throwsStateError,
    );
  });

  testWidgets('§1.1 a failed send puts the text back and says so', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: warmPopLight(),
          home: Scaffold(
            body: MessageInput(
              conversationId: 'send-fail',
              onSend: (_) async {
                calls++;
                throw StateError('rejected');
              },
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'hello there');
    // Keyboard submit runs the same _send as the send button.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(calls, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'hello there',
    );
    expect(find.text("Couldn't send. Try again."), findsOneWidget);
  });
}
