import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/screens/chat_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/presence_service.dart';

import '../core/sheet_harness.dart';

class _Repo extends FakeMessageRepository {
  final rows = StreamController<List<Message>>.broadcast();
  int reads = 0;

  @override
  Stream<List<Message>> watchMessages(String conversationId) => rows.stream;

  @override
  Stream<Conversation?> watchConversation(String conversationId) =>
      Stream.value(const Conversation(id: 'c1', type: 'direct'));

  @override
  Future<int> countUndecryptable(String conversationId) async => 0;

  @override
  Future<bool> hasUsableKey(String conversationId) async => true;

  @override
  Future<void> markConversationRead(String conversationId) async => reads++;
}

class _Presence implements PresenceService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

final _message = Message(
  localId: 'l1',
  conversationId: 'c1',
  senderId: 'u_peer',
  type: 'text',
  status: 'delivered',
  createdAt: DateTime.utc(2026, 11, 5),
);

/// A message landing while the app is in the background has not been read: a
/// mark-read here would start its disappearing clock and send a read receipt.
void main() {
  testWidgets('a chat left open in the background does not mark read',
      (tester) async {
    final repo = _Repo();
    addTearDown(repo.rows.close);
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
        messageRepositoryProvider.overrideWithValue(repo),
        presenceServiceProvider.overrideWithValue(_Presence()),
        currentUserIdProvider.overrideWith((ref) async => 'u_test'),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        messageBodyProvider.overrideWith((ref, id) async => null),
        outboxStatusProvider.overrideWith((ref, id) => Stream.value(const [])),
        reactionsProvider.overrideWith((ref, id) => Stream.value(const [])),
      ],
    );
    await tapOpen(tester);
    await tester.pump(const Duration(seconds: 2));

    void go(List<AppLifecycleState> states) {
      for (final s in states) {
        tester.binding.handleAppLifecycleStateChanged(s);
      }
    }

    go(const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    await tester.pump();
    final before = repo.reads;
    repo.rows.add([_message]);
    await tester.pump(const Duration(seconds: 2));
    expect(repo.reads, before, reason: 'nobody has seen it yet');

    go(const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    await tester.pump(const Duration(seconds: 2));
    expect(repo.reads, greaterThan(before), reason: 'resuming reads it');
  });
}
