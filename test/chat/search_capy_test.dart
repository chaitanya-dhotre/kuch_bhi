/// X8 (mascot spec §G5): "Nothing found" looks around once, then gets
/// sleepy; no replay while you keep typing; replays after results or a clear.
/// X8b (§H): while a search still runs, "…" and never 0/0; past the grace the
/// capybara holds the magnifying glass; "Nothing found" only once it is done.
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

/// Rows added for one test (body = local id, as for [_rows]).
var _extra = <Message>[];

/// Body lookups: held open while [_gate] is pending; [_throwFor] fails.
Completer<void>? _gate;
String? _throwFor;

class _Pres implements PresenceService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Repo implements MessageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      Stream.value([..._rows, ..._extra]);
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

Future<void> _openSearch(
  WidgetTester tester, {
  required bool reduced,
  bool held = false,
}) async {
  // Held from the start: the chat resolves (and caches) every body on open.
  if (held) _gate = Completer<void>();
  // Opening settles with motion off (the composer's mic pulse never settles).
  final motionOff = ValueNotifier(true);
  addTearDown(motionOff.dispose);
  for (final m in [..._rows, ..._extra]) {
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
      messageBodyProvider.overrideWith((ref, id) async {
        if (_gate case final g?) await g.future;
        if (id == _throwFor) throw StateError('lookup failed');
        return id;
      }),
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
    _gate = null;
    _throwFor = null;
    _extra = [];
    bodyCache.clear();
    CapyLoader.debugSource = capys = FakeSource();
  });
  tearDown(() {
    bodyCache.clear();
    CapyLoader.debugSource = null;
  });

  FakeRig x8() => capys.rigs[capys.views.lastIndexOf(CapyView.sit)];
  Finder counter(String text) => find.text(text);

  /// Lets the held lookups answer and drains their timers.
  Future<void> release(WidgetTester tester) async {
    _gate?.complete();
    _gate = null;
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

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

  testWidgets('X8b: a slow search shows "…", then the glass; never 0/0 or '
      'Nothing found while it runs; a match brings the list back',
      (tester) async {
    await _openSearch(tester, reduced: false, held: true);
    await tester.enterText(find.byType(TextField).first, 'lunch');
    await tester.pump();
    expect(counter('…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    expect(counter('…'), findsOneWidget, reason: 'search started, not done');
    expect(counter('0/0'), findsNothing);
    expect(find.text('Searching…'), findsNothing, reason: 'grace (decision 4)');
    expect(find.text('Nothing found'), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Searching…'), findsOneWidget);
    expect(find.text('Looking for “lunch”.'), findsOneWidget);
    expect(find.text('Nothing found'), findsNothing);
    expect(counter('0/0'), findsNothing);
    final busy = x8();
    expect(busy.pose, CapyPose.search);
    expect(busy.mood, CapyMood.focused);
    expect(busy.bools['still'], isFalse, reason: 'animated: the glass sweeps');

    await release(tester);
    expect(find.text('Searching…'), findsNothing);
    expect(counter('1/1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('X8b: ends empty → Nothing found looks around, no glass; typing '
      'on picks the glass straight back up, then no replay', (tester) async {
    await _openSearch(tester, reduced: false, held: true);
    await tester.enterText(find.byType(TextField).first, 'zz');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 550));
    expect(find.text('Searching…'), findsOneWidget);
    await release(tester);
    expect(find.text('Nothing found'), findsOneWidget);
    expect(counter('0/0'), findsOneWidget, reason: 'done: a real zero');
    expect(x8().fired, ['lookAround']);
    expect(x8().pose, CapyPose.none);
    await tester.pump(const Duration(milliseconds: 1600));

    await tester.enterText(find.byType(TextField).first, 'zzq');
    await tester.pump();
    expect(find.text('Searching…'), findsOneWidget,
        reason: 'from Nothing found: no chat-list flash');
    expect(x8().pose, CapyPose.search);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('Nothing found'), findsOneWidget);
    expect(x8().fired, isEmpty, reason: 'no replay while typing');
    expect(x8().mood, CapyMood.sleepy);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a sticker never matches, though its body holds the query '
      '(mascot §J2.5)', (tester) async {
    _extra = [
      Message(
        localId: 'Sticker: lunch', // its body (the resolver returns the id)
        serverId: 's_sticker',
        conversationId: 'c1',
        senderId: 'u_asha',
        type: 'sticker',
        status: 'read',
        createdAt: DateTime(2026, 10, 1, 10, 9),
      ),
    ];
    await _openSearch(tester, reduced: false);
    await _type(tester, 'lunch');
    expect(counter('1/1'), findsOneWidget, reason: 'the text only');
    await _type(tester, 'sticker');
    expect(find.text('Nothing found'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('X8b: a fast search never shows the glass', (tester) async {
    await _openSearch(tester, reduced: false);
    await tester.enterText(find.byType(TextField).first, 'lunch');
    await tester.pump();
    expect(counter('…'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Searching…'), findsNothing);
    }
    expect(counter('1/1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('X8b: a lookup that throws still lets the search finish',
      (tester) async {
    _throwFor = 'later'; // before open, so the lookup is not cached
    await _openSearch(tester, reduced: false);
    await _type(tester, 'zz');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Searching…'), findsNothing);
    expect(find.text('Nothing found'), findsOneWidget);
    expect(counter('…'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('X8b: clear and close drop the busy state and its timer',
      (tester) async {
    await _openSearch(tester, reduced: false, held: true);
    await tester.enterText(find.byType(TextField).first, 'zz');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Searching…'), findsNothing);
    expect(counter('0/0'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zz');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Close search').first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Searching…'), findsNothing);
    await release(tester);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('X8b reduced motion: the glass is held still', (tester) async {
    await _openSearch(tester, reduced: true, held: true);
    await tester.enterText(find.byType(TextField).first, 'zz');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 550));
    expect(find.text('Searching…'), findsOneWidget);
    expect(x8().pose, CapyPose.search);
    expect(x8().bools['reducedMotion'], isTrue);
    await release(tester);
    await tester.pump(const Duration(seconds: 2));
  });
}
