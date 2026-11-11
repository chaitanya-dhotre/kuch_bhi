/// X8 (mascot spec §G5): "Nothing found" looks around once, then gets
/// sleepy; no replay while you keep typing; replays after results or a clear.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/screens/chat_screen.dart';
import 'package:kuch_bhi/features/mascot/capy.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/presence_service.dart';

import '../core/sheet_harness.dart';
import '../mascot/capy_test.dart' show FakeRig, FakeSource;

final _rows = [
  for (final (i, id) in ['hello', 'lunch', 'later'].indexed)
    Message(
      localId: id,
      serverId: 's_$id',
      conversationId: 'c1',
      senderId: 'u_asha',
      type: 'text',
      status: 'read',
      createdAt: DateTime(2026, 10, 1, 10, i),
    ),
];

class _Pres implements PresenceService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Repo implements MessageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream.value(_rows);
  @override
  Stream<Conversation?> watchConversation(String conversationId) =>
      Stream.value(const Conversation(id: 'c1', type: 'direct'));
  @override
  Stream<List<User>> watchGroupMembers(String conversationId) =>
      Stream.value(const []);
  @override
  Stream<List<Message>> watchPinnedMessages(String conversationId) =>
      Stream.value(const []);
  @override
  Future<bool> hasUsableKey(String conversationId) async => true;
  @override
  Future<int> countUndecryptable(String conversationId) async => 0;
}

Future<void> _openSearch(WidgetTester tester, {required bool reduced}) async {
  // Opening settles with motion off (the composer's mic pulse never settles).
  final motionOff = ValueNotifier(true);
  addTearDown(motionOff.dispose);
  for (final m in _rows) {
    bodyCache.put(m.localId, m.localId);
  }
  await pumpHost(
    tester,
    SheetLauncher(
      (context, ref) => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => ValueListenableBuilder(
            valueListenable: motionOff,
            builder: (context, off, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: off),
              child: child!,
            ),
            child: const ChatScreen(
              conversation: Conversation(id: 'c1', type: 'direct'),
            ),
          ),
        ),
      ),
    ),
    overrides: [
      messageRepositoryProvider.overrideWithValue(_Repo()),
      presenceServiceProvider.overrideWithValue(_Pres()),
      currentUserIdProvider.overrideWith((ref) async => 'u_me'),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      messageBodyProvider.overrideWith((ref, id) async => id),
      outboxStatusProvider.overrideWith((ref, c) => Stream.value(const [])),
      reactionsProvider.overrideWith((ref, id) => Stream.value(const [])),
    ],
  );
  await tapOpen(tester);
  await tester.pump(const Duration(seconds: 2));
  motionOff.value = reduced;
  await tester.pump();
  await tester.tap(find.byTooltip('Search messages'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField).first, query);
  await tester.pump();
  // Past the 200 ms debounce and the body lookups.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
  await tester.pump();
}

void main() {
  late FakeSource capys;
  setUp(() {
    bodyCache.clear();
    CapyLoader.debugSource = capys = FakeSource();
  });
  tearDown(() {
    bodyCache.clear();
    CapyLoader.debugSource = null;
  });

  FakeRig x8() => capys.rigs[capys.views.lastIndexOf(CapyView.sit)];

  testWidgets('looks around once, sleepy after 1.6 s; no replay while typing; '
      'replays after results', (tester) async {
    await _openSearch(tester, reduced: false);
    await _type(tester, 'zz');
    expect(find.text('Nothing found'), findsOneWidget);
    final first = x8();
    expect(first.fired, ['lookAround']);
    expect(first.mood, CapyMood.active);
    expect(first.bools['still'], isTrue, reason: 'still + one-shot (F2)');
    await tester.pump(const Duration(milliseconds: 1600));
    expect(first.mood, CapyMood.sleepy);

    await _type(tester, 'zzq');
    expect(find.text('Nothing found'), findsOneWidget);
    final typing = x8();
    expect(typing.fired, isEmpty, reason: 'no replay while typing');
    expect(typing.mood, CapyMood.sleepy);

    await _type(tester, 'lunch');
    expect(find.text('Nothing found'), findsNothing);
    await _type(tester, 'lunchx');
    expect(find.text('Nothing found'), findsOneWidget);
    expect(x8().fired, ['lookAround'], reason: 'results → none replays');

    await _type(tester, '');
    await _type(tester, 'qq');
    expect(x8().fired, ['lookAround'], reason: 'clear and search again');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('reduced motion: sleepy at once, no trigger', (tester) async {
    await _openSearch(tester, reduced: true);
    await _type(tester, 'zz');
    expect(find.text('Nothing found'), findsOneWidget);
    expect(x8().fired, isEmpty);
    expect(x8().mood, CapyMood.sleepy);
    await tester.pump(const Duration(seconds: 2));
  });
}
