import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/reaction_bar.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

class _ReactionRepository extends FakeMessageRepository {
  _ReactionRepository(this.groups);

  List<ReactionGroup> groups;
  final added = <(String messageId, String emoji)>[];
  final removed = <String>[];
  final _changes = StreamController<String>.broadcast();

  @override
  Stream<String> get reactionsChanges => _changes.stream;

  @override
  Future<List<ReactionGroup>> getReactions(String messageServerId) async {
    return groups;
  }

  @override
  Future<void> addReaction(String messageServerId, String emoji) async {
    added.add((messageServerId, emoji));
  }

  @override
  Future<void> removeReaction(String reactionId) async {
    removed.add(reactionId);
  }

  Future<void> dispose() => _changes.close();
}

Widget _host(_ReactionRepository repo, {required bool online}) {
  return ProviderScope(
    overrides: [
      messageRepositoryProvider.overrideWithValue(repo),
      isOnlineProvider.overrideWith((ref) => Stream<bool>.value(online)),
    ],
    child: MaterialApp(
      theme: warmPopLight(),
      home: const Scaffold(
        body: ReactionBar(messageServerId: 'm1', isMine: false),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'chip tap toggles own reaction; long press remains detail action',
    (tester) async {
      final repo = _ReactionRepository([
        const ReactionGroup(
          emoji: '❤️',
          count: 2,
          isMine: true,
          reactionId: 'reaction-1',
        ),
      ]);
      addTearDown(repo.dispose);

      await tester.pumpWidget(_host(repo, online: true));
      await tester.pump();

      final chip = find.byKey(const Key('reaction-chip-m1-❤️'));
      final gesture = tester.widget<GestureDetector>(chip);
      expect(gesture.onTap, isNotNull);
      expect(gesture.onLongPress, isNotNull);

      await tester.tap(chip);
      await tester.pump();

      expect(repo.removed, ['reaction-1']);
      expect(repo.added, isEmpty);
    },
  );

  // Chat calm C8: the always-visible "+" chip is gone (long-press adds).
  testWidgets('no ghost add chip next to the reactions', (tester) async {
    final repo = _ReactionRepository([
      const ReactionGroup(emoji: '👍', count: 1, isMine: false),
    ]);
    addTearDown(repo.dispose);

    await tester.pumpWidget(_host(repo, online: true));
    await tester.pump();

    expect(find.text('👍 1'), findsOneWidget);
    expect(find.byKey(const Key('reaction-add-m1')), findsNothing);
    expect(find.text('＋'), findsNothing);
  });

  testWidgets('reaction controls stay live offline (queued), no hint', (
    tester,
  ) async {
    final repo = _ReactionRepository([
      const ReactionGroup(emoji: '👍', count: 1, isMine: false),
    ]);
    addTearDown(repo.dispose);

    await tester.pumpWidget(_host(repo, online: false));
    await tester.pump();

    final chip = find.byKey(const Key('reaction-chip-m1-👍'));
    expect(find.ancestor(of: chip, matching: find.byType(Opacity)),
        findsNothing);
    expect(find.text('Available online'), findsNothing);
    await tester.tap(chip);
    await tester.pump();
    expect(repo.added, [('m1', '👍')]);
  });
}
