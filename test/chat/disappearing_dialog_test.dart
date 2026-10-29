/// Registry C11: one disappearing-messages dialog for both entry points
/// (checklist test gate: `disappearing_dialog_test.dart`).
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/disappearing_dialog.dart';
import 'package:kuch_bhi/features/groups/providers/group_admin_provider.dart';
import 'package:kuch_bhi/features/groups/screens/group_settings_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

const _failedCopy = "Couldn't update. Try again.";

/// Seeds one group conversation whose persisted duration is 7 days.
Future<AppDatabase> _seedDb() async {
  final db = AppDatabase.test();
  await db.conversationsDao.upsertConversation(
    ConversationsTableCompanion.insert(
      id: 'conv-1',
      type: 'group',
      name: const Value('Weekend Trekkers'),
      createdById: 'u_me',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      disappearingDuration: const Value(604800),
    ),
  );
  return db;
}

class _FailingRepo implements MessageRepository {
  var writes = 0;

  @override
  Future<void> setDisappearingDuration(String cid, int seconds) async {
    writes += 1;
    throw StateError('boom write secret');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'MessageRepository.${invocation.memberName} not stubbed',
      );
}

/// Host for the shared dialog: a real Scaffold so the toast can present.
Widget _host(AppDatabase db, {MessageRepository? repo}) => ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        if (repo != null) messageRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () =>
                      showDisappearingDialog(context, ref, 'conv-1'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

/// title → whether the trailing checkmark is present.
Map<String, bool> _checks(WidgetTester tester) {
  final tiles = tester.widgetList<ListTile>(find.byType(ListTile));
  return {
    for (final tile in tiles)
      (tile.title! as Text).data!: tile.trailing != null,
  };
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

void main() {
  testWidgets('the checkmark sits on the persisted duration', (tester) async {
    final db = await _seedDb();
    await tester.pumpWidget(_host(db));
    await _settle(tester);

    await tester.tap(find.text('open'));
    await _settle(tester);

    expect(find.text('Disappearing Messages'), findsOneWidget);
    expect(
      _checks(tester),
      {'Off': false, '24 hours': false, '7 days': true, '30 days': false},
    );
  });

  testWidgets('the checkmark is ink, not accent', (tester) async {
    final db = await _seedDb();
    await tester.pumpWidget(_host(db));
    await _settle(tester);

    await tester.tap(find.text('open'));
    await _settle(tester);

    final tile = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .firstWhere((t) => (t.title! as Text).data == '7 days');
    final icon = tile.trailing! as Icon;
    final ctx = tester.element(find.byType(AlertDialog));
    final t = Theme.of(ctx).extension<ColorTokens>()!;
    final resolved = icon.color ?? IconTheme.of(ctx).color;
    expect(resolved, t.ink);
    expect(resolved, isNot(t.accent));
  });

  testWidgets('a failed write toasts the stable copy', (tester) async {
    final db = await _seedDb();
    final repo = _FailingRepo();
    await tester.pumpWidget(_host(db, repo: repo));
    await _settle(tester);

    await tester.tap(find.text('open'));
    await _settle(tester);
    await tester.tap(find.text('30 days'));
    await _settle(tester);

    expect(repo.writes, 1);
    expect(find.text(_failedCopy), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.text('Disappearing Messages'), findsNothing,
        reason: 'the dialog closes before the write resolves');
  });

  testWidgets('the Group Info row opens the same dialog', (tester) async {
    final db = await _seedDb();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          conversationStreamProvider.overrideWith(
            (ref, id) => Stream<Conversation?>.value(
              const Conversation(
                id: 'conv-1',
                type: 'group',
                name: 'Weekend Trekkers',
              ),
            ),
          ),
          groupMembersProvider.overrideWith(
            (ref, id) => Stream.value([
              User(
                id: 'u_me',
                displayName: 'Mira Joshi',
                username: 'mira',
                email: 'mira@example.com',
                friendCode: 'CODE01',
                createdAt: DateTime(2026, 1, 1),
                groupRole: 'admin',
              ),
            ]),
          ),
          currentUserIdProvider.overrideWith((ref) async => 'u_me'),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
          disappearingDurationProvider
              .overrideWith((ref, id) => Stream<int>.value(604800)),
          pendingInvitesProvider.overrideWith((ref, id) async => const []),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const GroupSettingsScreen(
            conversation: Conversation(
              id: 'conv-1',
              type: 'group',
              name: 'Weekend Trekkers',
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    await tester.ensureVisible(find.text('Disappearing Messages'));
    await _settle(tester);
    await tester.tap(find.text('Disappearing Messages'));
    await _settle(tester);

    // Same dialog, same checkmark placement as the shared entry point.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Disappearing Messages'),
      ),
      findsOneWidget,
    );    expect(_checks(tester),
      {'Off': false, '24 hours': false, '7 days': true, '30 days': false},
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('7 days'),
      ),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });

  test('both entry points call the shared dialog and keep no local copy', () {
    final chat =
        File('lib/features/chat/screens/chat_screen.dart').readAsStringSync();
    final info = File('lib/features/groups/screens/group_settings_screen.dart')
        .readAsStringSync();

    expect('showDisappearingDialog(context, ref, _cid)'.allMatches(chat),
        hasLength(1));
    expect('showDisappearingDialog(context, ref, _cid)'.allMatches(info),
        hasLength(1));
    // No second definition of the dialog or its label helper anywhere else.
    expect('String disappearingDurationLabel'.allMatches(chat), isEmpty);
    expect('String disappearingDurationLabel'.allMatches(info), isEmpty);
    expect('showDisappearingDialog(BuildContext'.allMatches(chat), isEmpty);
    expect('showDisappearingDialog(BuildContext'.allMatches(info), isEmpty);
  });
}
