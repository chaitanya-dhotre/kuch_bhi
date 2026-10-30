import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/core/widgets/app_avatar.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/reaction_bar.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/sheet_harness.dart';

class _Repo extends FakeMessageRepository {
  final removed = <String>[];
  Completer<void>? removeGate;
  var reads = 0;

  /// The real repository swallows a network failure and answers `[]`.
  var offline = false;

  @override
  Stream<String> get reactionsChanges => const Stream.empty();

  @override
  Future<List<ReactionGroup>> getReactions(String messageServerId) async {
    reads++;
    if (offline) return const [];
    return const [
      ReactionGroup(emoji: '❤️', count: 2, isMine: true, reactionId: 'r_me'),
    ];
  }

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
    reactionDetailProvider.overrideWith((ref, key) => answer());

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

  testWidgets('Remove, then the sheet is swiped away mid-write: no throw, '
      'the bar still refreshes', (tester) async {
    final repo = await _pump(tester, detail: [_detail(() async => _data)]);
    repo.removeGate = Completer<void>();
    await tester.longPress(_chip);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
    final before = repo.reads;

    repo.removeGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repo.removed, ['r_me']);
    expect(repo.reads, greaterThan(before), reason: 'reactions re-read');
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

  testWidgets('the real query gives up at 8s against a silent server',
      (tester) async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final pb = PocketBase(
      'http://pb.test',
      httpClientFactory: () =>
          MockClient((_) => Completer<http.Response>().future),
    );
    await _pump(tester, detail: [
      appDatabaseProvider.overrideWithValue(db),
      pocketbaseClientProvider.overrideWithValue(PocketBaseClient.forTest(pb)),
    ]);
    await tester.longPress(_chip);
    await tester.pump();
    await tester.pump(const Duration(seconds: 7));
    expect(find.byKey(const Key('reaction-detail-loading')), findsOneWidget);
    expect(find.text("Couldn't load reactions."), findsNothing);

    await tester.pump(const Duration(seconds: 1, milliseconds: 100));
    await tester.pump();
    expect(find.text("Couldn't load reactions."), findsOneWidget);
  });

  testWidgets('the real query reads the single expanded user (names shown)',
      (tester) async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final pb = PocketBase(
      'http://pb.test',
      httpClientFactory: () => MockClient((_) async => http.Response(
            jsonEncode({
              'page': 1,
              'perPage': 50,
              'totalItems': 1,
              'totalPages': 1,
              'items': [
                {
                  'id': 'r_m',
                  'collectionId': 'c',
                  'collectionName': 'reactions',
                  'user_id': 'u_mira',
                  'emoji': '❤️',
                  // A single relation expands to one object, not a list.
                  'expand': {
                    'user_id': {
                      'id': 'u_mira',
                      'collectionId': 'u',
                      'collectionName': 'users',
                      'display_name': 'Mira Joshi',
                      'avatar': '',
                    },
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    );
    await _pump(tester, detail: [
      appDatabaseProvider.overrideWithValue(db),
      pocketbaseClientProvider.overrideWithValue(PocketBaseClient.forTest(pb)),
    ]);
    await tester.longPress(_chip);
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load reactions."), findsNothing);
    expect(find.text('Mira Joshi'), findsOneWidget);
  });

  testWidgets('offline keeps the last reactions; back online reads again',
      (tester) async {
    final online = StreamController<bool>();
    addTearDown(online.close);
    final show = ValueNotifier(true);
    final repo = _Repo();
    online.add(true);
    await pumpHost(
      tester,
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, visible, __) => visible
              ? const ReactionBar(messageServerId: 'm9', isMine: false)
              : const SizedBox(),
        ),
      ),
      overrides: [
        messageRepositoryProvider.overrideWithValue(repo),
        isOnlineProvider.overrideWith((ref) => online.stream),
      ],
    );
    await tester.pumpAndSettle();
    final chip = find.byKey(const Key('reaction-chip-m9-❤️'));
    expect(chip, findsOneWidget);

    repo.offline = true;
    online.add(false);
    await tester.pumpAndSettle();
    // The chat list rebuilds its rows: the bar comes back while offline.
    show.value = false;
    await tester.pumpAndSettle();
    show.value = true;
    await tester.pumpAndSettle();
    expect(chip, findsOneWidget, reason: 'an offline read is not "no reactions"');

    repo.offline = false;
    final before = repo.reads;
    online.add(true);
    await tester.pumpAndSettle();
    expect(repo.reads, greaterThan(before), reason: 're-read on reconnect');
    expect(chip, findsOneWidget);
  });

  testWidgets('offline while open: Remove dimmed once, one hint',
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
    final dim = find.ancestor(
        of: find.text('Remove'), matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(dim).opacity, 0.38);
    expect(
      find.descendant(of: _sheet, matching: find.text('Available online')),
      findsOneWidget,
    );
  });
}
