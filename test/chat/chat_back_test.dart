import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/screens/chat_screen.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/presence_service.dart';

import '../core/sheet_harness.dart';

class _Repo extends FakeMessageRepository {
  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream.value(const []);

  @override
  Stream<Conversation?> watchConversation(String conversationId) =>
      Stream.value(const Conversation(id: 'c1', type: 'direct'));

  @override
  Future<int> countUndecryptable(String conversationId) async => 0;

  @override
  Future<bool> hasUsableKey(String conversationId) async => true;

  @override
  Future<void> markConversationRead(String conversationId) async {}
}

/// A server that never answers the "left the chat" write (bad mobile data).
class _StuckPresence implements PresenceService {
  int leaveCalls = 0;

  @override
  Future<void> leaveChat(String conversationId) {
    leaveCalls++;
    return Completer<void>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

Future<_StuckPresence> _openChat(WidgetTester tester) async {
  final presence = _StuckPresence();
  await pumpHost(
    tester,
    SheetLauncher(
      (context, ref) => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const ChatScreen(
              conversation: Conversation(id: 'c1', type: 'direct'),
            ),
          ),
        ),
      ),
    ),
    overrides: [
      messageRepositoryProvider.overrideWithValue(_Repo()),
      presenceServiceProvider.overrideWithValue(presence),
      currentUserIdProvider.overrideWith((ref) async => 'u_test'),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      messageBodyProvider.overrideWith((ref, id) async => null),
      outboxStatusProvider.overrideWith((ref, id) => Stream.value(const [])),
      reactionsProvider.overrideWith((ref, id) => Stream.value(const [])),
    ],
  );
  await tapOpen(tester);
  await tester.pump(const Duration(seconds: 2));
  expect(find.byType(ChatScreen), findsOneWidget);
  return presence;
}

void main() {
  testWidgets('system back closes the chat while the presence write hangs', (
    tester,
  ) async {
    final presence = await _openChat(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ChatScreen), findsNothing);
    expect(presence.leaveCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('the back arrow closes the chat while the presence write hangs',
      (tester) async {
    final presence = await _openChat(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ChatScreen), findsNothing);
    expect(presence.leaveCalls, greaterThanOrEqualTo(1));
  });
}
