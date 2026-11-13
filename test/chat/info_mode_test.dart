/// K2 C1 (mascot spec §K2): the app-bar capybara toggles info mode: every
/// bubble of a run shows its time and ticks; still; off on every chat open.
library;

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
import 'package:kuch_bhi/features/chat/widgets/expiry_badge.dart';
import 'package:kuch_bhi/features/chat/widgets/selection_bar.dart';
import 'package:kuch_bhi/features/mascot/capy.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/presence_service.dart';

import '../core/sheet_harness.dart';
import '../mascot/capy_test.dart' show FakeRig, FakeSource;

/// One run: same sender, a minute apart.
final _rows = [
  for (final (i, id) in ['one', 'two', 'three'].indexed)
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

Future<void> _open(WidgetTester tester, {bool large = false}) async {
  for (final m in _rows) {
    bodyCache.put(m.localId, m.localId);
  }
  await pumpHost(
    tester,
    large: large,
    SheetLauncher(
      (context, ref) => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          // Motion off: the composer's mic pulse never settles.
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

  FakeRig buddy() => capys.rigs[capys.views.lastIndexOf(CapyView.head)];
  Finder times() => find.byType(ChatBubbleTimestamp);
  IconButton button(WidgetTester tester) => tester.widget<IconButton>(
    find.ancestor(of: find.byType(Capy), matching: find.byType(IconButton)),
  );

  testWidgets('tap shows every time; tap again → run ends only; still', (
    tester,
  ) async {
    await _open(tester);
    expect(find.byTooltip('Show message times'), findsOneWidget);
    expect(times(), findsOneWidget, reason: 'off: only the run end');
    expect(button(tester).isSelected, isFalse);
    expect(buddy().mood, CapyMood.chill);
    expect(buddy().bools['still'], isTrue, reason: 'V5: never animated');

    await tester.tap(find.byTooltip('Show message times'));
    await tester.pump();
    expect(times(), findsNWidgets(3));
    expect(find.byTooltip('Hide message times'), findsOneWidget);
    expect(button(tester).isSelected, isTrue);
    expect(buddy().mood, CapyMood.active);
    expect(buddy().fired, isEmpty, reason: 'not pettable, no one-shot');

    await tester.tap(find.byTooltip('Hide message times'));
    await tester.pump();
    expect(times(), findsOneWidget);
    expect(buddy().mood, CapyMood.chill);
  });

  testWidgets('reopening the chat starts with info mode off', (tester) async {
    await _open(tester);
    await tester.tap(find.byTooltip('Show message times'));
    await tester.pump();
    expect(times(), findsNWidgets(3));
    Navigator.of(tester.element(find.byType(ChatScreen))).pop();
    await tester.pumpAndSettle();
    await tapOpen(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byTooltip('Show message times'), findsOneWidget);
    expect(times(), findsOneWidget);
  });

  testWidgets('not in the search bar', (tester) async {
    await _open(tester);
    await tester.tap(find.byTooltip('Search messages'));
    await tester.pump();
    expect(find.byTooltip('Show message times'), findsNothing);
  });

  testWidgets('not in the selection bar', (tester) async {
    await _open(tester);
    await tester.longPress(find.text('two'));
    await tester.pump(const Duration(milliseconds: 500));
    // Long press opens the menu; Select enters selection mode.
    await tester.tap(find.text('Select').first);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(SelectionBar), findsOneWidget);
    expect(find.byTooltip('Show message times'), findsNothing);
  });

  testWidgets('360×640 at 200%: the app bar fits', (tester) async {
    await _open(tester, large: true);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Show message times'), findsOneWidget);
  });
}
