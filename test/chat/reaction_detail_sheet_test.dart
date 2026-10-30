import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/core/widgets/app_avatar.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/reaction_bar.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import '../core/sheet_harness.dart';

class _Repo extends FakeMessageRepository {
  final removed = <String>[];
  Completer<void>? removeGate;
  var reads = 0;
  var refreshes = 0;

  @override
  Stream<String> get reactionsChanges => const Stream.empty();

  @override
  Future<List<ReactionGroup>> getReactions(String messageServerId) async {
    reads++;
    return const [
      ReactionGroup(emoji: '❤️', count: 2, isMine: true, reactionId: 'r_me'),
    ];
  }

  @override
  Future<void> refreshReactions(String messageServerId) async => refreshes++;

  @override
  Future<void> removeReaction(String reactionId) async {
    await removeGate?.future;
    removed.add(reactionId);
  }
}

typedef _Detail = ({String myId, List<Reactor> reactors});

const _data = (
  myId: 'u_me',
  reactors: <Reactor>[
    (name: 'Chai', userId: 'u_me', reactionId: 'r_me', avatarUrl: null),
    (name: 'Mira Joshi', userId: 'u_mira', reactionId: 'r_m', avatarUrl: null),
  ],
);

final _chip = find.byKey(const Key('reaction-chip-m1-❤️'));

Future<_Repo> _pump(
  WidgetTester tester, {
  required List<Override> detail,
  Stream<bool>? online,
}) async {
  final repo = _Repo();
  await pumpHost(
    tester,
    const Scaffold(
      body: Center(child: ReactionBar(messageServerId: 'm1', isMine: false)),
    ),
    overrides: [
      messageRepositoryProvider.overrideWithValue(repo),
      isOnlineProvider.overrideWith((ref) => online ?? Stream.value(true)),
      ...detail,
    ],
  );
  await tester.pump();
  return repo;
}

Override _detail(Future<_Detail> Function() answer) =>
    reactionDetailProvider
        .overrideWith((ref, key) => Stream.fromFuture(answer()));

final _sheet = find.byType(BottomSheet);

void main() {
  testWidgets('opens at once: title + 3 skeleton rows on the first frame',
      (tester) async {
    final pending = Completer<_Detail>();
    await _pump(tester, detail: [_detail(() => pending.future)]);

    await tester.longPress(_chip);
    await tester.pump();
    expect(find.text('❤️ 2 reactions'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byKey(const Key('reaction-detail-loading')),
          matching: find.byType(Skeleton)),
      findsNWidgets(6),
      reason: '3 rows × (40 disc + 14 bar)',
    );
    pending.complete(_data);
    await tester.pumpAndSettle();
  });

  testWidgets('data: R1 avatars, "You" on mine, Remove in ink',
      (tester) async {
    await _pump(tester, detail: [_detail(() async => _data)]);
    await tester.longPress(_chip);
    await tester.pumpAndSettle();
    final t = tokens(tester);

    for (final uid in ['u_me', 'u_mira']) {
      expect(find.byKey(ValueKey('reaction-detail-user-$uid')), findsOneWidget);
      final avatar = find.byKey(ValueKey('reaction-detail-avatar-$uid'));
      expect(tester.widget(avatar), isA<AppAvatar>());
      expect(tester.widget<AppAvatar>(avatar).radius, 20);
    }
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(paintedColor(tester, find.text('Remove')), t.ink);
    expectNoTextIn(tester, [t.error, t.accent, t.success], _sheet);
  });

  testWidgets('Remove: same write, invalidate and pop', (tester) async {
    final repo = await _pump(tester, detail: [_detail(() async => _data)]);
    await tester.longPress(_chip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(repo.removed, ['r_me']);
    expect(_sheet, findsNothing);
  });

  testWidgets('Remove, then the sheet is swiped away mid-write: no throw',
      (tester) async {
    final repo = await _pump(tester, detail: [_detail(() async => _data)]);
    repo.removeGate = Completer<void>();
    await tester.longPress(_chip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);

    repo.removeGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repo.removed, ['r_me']);
  });

  testWidgets("error: Couldn't load reactions. + Retry re-reads",
      (tester) async {
    var calls = 0;
    await _pump(tester, detail: [
      _detail(() async {
        calls++;
        if (calls == 1) throw StateError('secret-boom');
        return _data;
      }),
    ]);
    await tester.longPress(_chip);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load reactions."), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Mira Joshi'), findsOneWidget);
    expect(find.text("Couldn't load reactions."), findsNothing);
  });

  testWidgets('reads the local store: cached names, no network', (tester) async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final at = DateTime.utc(2026, 1, 1);
    await tester.runAsync(() async {
      await db.settingsDao.setSetting('current_user_id', 'u_me');
      await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId: 'loc1',
        conversationId: 'g1',
        senderId: 'u_mira',
        type: 'text',
        encryptedBody: 'x',
        iv: '',
        serverId: const Value('m1'),
        createdAt: at,
        updatedAt: at,
      ));
      await db.usersDao.upsertUser(UsersTableCompanion.insert(
          id: 'u_mira',
          displayName: 'Mira Joshi',
          username: 'mira',
          friendCode: 'MIRA01',
          createdAt: at,
          updatedAt: at));
      for (final (id, uid) in [('r_m', 'u_mira'), ('r_x', 'u_gone')]) {
        await db.into(db.reactionsTable).insert(ReactionsTableCompanion.insert(
              id: id,
              messageLocalId: 'loc1',
              conversationId: 'g1',
              userId: uid,
              emoji: '❤️',
              createdAt: at,
            ));
      }
    });
    await _pump(tester, detail: [appDatabaseProvider.overrideWithValue(db)]);
    await tester.longPress(_chip);
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Mira Joshi'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget,
        reason: 'a reactor with no cached profile');
    expect(find.text("Couldn't load reactions."), findsNothing);
    // Drift's watch keeps a stream open; close it before the db.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  testWidgets('coming back online asks the server again', (tester) async {
    final online = StreamController<bool>();
    addTearDown(online.close);
    online.add(false);
    final repo = await _pump(tester,
        detail: [_detail(() async => _data)], online: online.stream);
    await tester.pumpAndSettle();
    final before = repo.refreshes;

    online.add(true);
    await tester.pumpAndSettle();
    expect(repo.refreshes, greaterThan(before));
    expect(_chip, findsOneWidget, reason: 'no blink while it re-reads');
  });

  testWidgets('offline while open: Remove stays live (queued), no hint',
      (tester) async {
    final online = StreamController<bool>();
    addTearDown(online.close);
    online.add(true);
    await _pump(tester,
        detail: [_detail(() async => _data)], online: online.stream);
    await tester.longPress(_chip);
    await tester.pumpAndSettle();

    online.add(false);
    await tester.pump();
    await tester.pump();
    expect(
        find.ancestor(of: find.text('Remove'), matching: find.byType(Opacity)),
        findsNothing);
    expect(
      find.descendant(of: _sheet, matching: find.text('Available online')),
      findsNothing,
    );
  });
}
