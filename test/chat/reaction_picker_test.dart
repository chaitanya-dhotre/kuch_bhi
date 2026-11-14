import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/message_context_menu.dart';
import 'package:kuch_bhi/features/chat/widgets/reaction_bar.dart';
import 'package:kuch_bhi/features/chat/widgets/reaction_picker.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import '../core/sheet_harness.dart';

class _Repo extends FakeMessageRepository {
  final added = <(String, String)>[];

  @override
  Stream<String> get reactionsChanges => const Stream.empty();

  @override
  Future<List<ReactionGroup>> getReactions(String messageServerId) async =>
      const [ReactionGroup(emoji: '👍', count: 1, isMine: false)];

  @override
  Future<void> addReaction(String messageServerId, String emoji) async =>
      added.add((messageServerId, emoji));
}

/// Opens the picker; the returned getter gives its result future.
Future<Future<String?> Function()> _openPicker(WidgetTester tester) async {
  Future<String?>? result;
  await pumpHost(
    tester,
    SheetLauncher((context, _) => result = showReactionPicker(context)),
  );
  await tapOpen(tester);
  return () => result!;
}

void main() {
  test('kReactionEmojis is the 32, in order', () {
    expect(kReactionEmojis, [
      '👍', '👎', '❤️', '🔥', '😂', '😮', '😢', '🙏', '🎉', '💯', '😍', '🤔', //
      '😡', '👏', '🤣', '😊', '💪', '🫡', '✅', '❌', '⭐', '💎', '🚀', '😴', //
      '🥹', '🫶', '😎', '🤯', '🥳', '👀', '💀', '🫠',
    ]);
    expect(kQuickReactions, ['👍', '❤️', '😂', '😮', '😢']);
    expect(kQuickReactions.every(kReactionEmojis.contains), isTrue);
  });

  testWidgets('picking returns the emoji', (tester) async {
    final result = await _openPicker(tester);
    expect(find.text('Add a reaction'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reaction-picker-🔥')));
    await tester.pumpAndSettle();
    expect(await result(), '🔥');
  });

  testWidgets('dismiss returns null', (tester) async {
    final result = await _openPicker(tester);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reaction-picker')), findsNothing);
    expect(await result(), isNull);
  });

  testWidgets('cells are ≥48 and 6 across at 360dp; buttons named by emoji',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _openPicker(tester);

    for (final emoji in ['👍', '🫠']) {
      final size = tester.getSize(find.byKey(ValueKey('reaction-picker-$emoji')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    final first = tester.getTopLeft(find.byKey(const Key('reaction-picker-👍')));
    final sixth = tester.getTopLeft(find.byKey(const Key('reaction-picker-😮')));
    final seventh =
        tester.getTopLeft(find.byKey(const Key('reaction-picker-😢')));
    expect(sixth.dy, first.dy, reason: '6 in the first row');
    expect(seventh.dy, greaterThan(first.dy));
    expect(
      tester.getSemantics(find.byKey(const Key('reaction-picker-😂'))),
      isSemantics(label: '😂', isButton: true, hasTapAction: true),
    );
    semantics.dispose();
  });

  testWidgets('the message menu ＋ opens the picker (C8: no bubble chip)',
      (tester) async {
    final repo = _Repo();
    final message = Message(
      localId: 'loc1',
      serverId: 'srv1',
      conversationId: 'c1',
      senderId: 'u_other',
      type: 'text',
      decryptedBody: 'hi',
      status: 'sent',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await pumpHost(
      tester,
      Column(
        children: [
          Expanded(
            child: SheetLauncher((context, ref) => showMessageMenu(
                  context: context,
                  ref: ref,
                  message: message,
                  isMine: false,
                  senderName: 'Ada',
                )),
          ),
          const Material(
              child: ReactionBar(messageServerId: 'srv1', isMine: false)),
        ],
      ),
      overrides: [
        messageRepositoryProvider.overrideWithValue(repo),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    await tester.pump();

    await tapOpen(tester);
    await tester.tap(find.byKey(const Key('message-menu-reaction-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reaction-picker')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reaction-picker-🎉')));
    await tester.pumpAndSettle();
    expect(repo.added, [('srv1', '🎉')]);
    expect(find.byKey(const Key('message-context-menu')), findsNothing);
    // Chat calm C8: long-press is the only way in; no "+" chip on the bubble.
    expect(find.byKey(const Key('reaction-add-srv1')), findsNothing);
  });
}
