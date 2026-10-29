/// Add-members sheet: the false-empty regression, friends load error, invite
/// status meta, the busy-while-sending contract, the three outcome toasts and
/// the invite invalidation (checklist test gate:
/// `add_members_sheet_test.dart`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/app_button.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/friendship.dart';
import 'package:kuch_bhi/domain/entities/group_invite.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/groups/providers/group_admin_provider.dart';
import 'package:kuch_bhi/features/groups/screens/group_settings_screen.dart';
import 'package:kuch_bhi/features/home/providers/friends_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

const _sheetKey = Key('add-members-sheet');

User _user({
  required String id,
  required String name,
  String? username,
  String role = 'member',
}) =>
    User(
      id: id,
      displayName: name,
      username: username ?? id,
      email: '$id@example.com',
      friendCode: 'CODE01',
      createdAt: DateTime(2026, 1, 1),
      groupRole: role,
    );

Friendship _friend(User friend) => Friendship(
      id: 'f_${friend.id}',
      friend: friend,
      createdAt: DateTime(2026, 1, 1),
    );

const _conv = Conversation(
  id: 'conv-1',
  type: 'group',
  name: 'Weekend Trekkers',
  onlyAdminsCanMessage: false,
);

// ── friendshipsProvider fixtures ──────────────────────────────────────

class _LoadingFriendships extends FriendshipsNotifier {
  @override
  Future<List<Friendship>> build() => Completer<List<Friendship>>().future;
}

class _ErrorFriendships extends FriendshipsNotifier {
  @override
  Future<List<Friendship>> build() async =>
      throw StateError('boom friends secret');
}

class _DataFriendships extends FriendshipsNotifier {
  _DataFriendships(this.friends);

  final List<Friendship> friends;

  @override
  Future<List<Friendship>> build() async => friends;
}

// ── repository fixture ────────────────────────────────────────────────

class _Repo implements MessageRepository {
  _Repo({this.statuses = const {}, Set<String> failFor = const {}})
      : _failFor = failFor;

  final Map<String, String> statuses;
  final Set<String> _failFor;

  /// Set to hold every send until the test releases it.
  Completer<void>? gate;

  var sendCalls = 0;
  var inviteFetches = 0;

  @override
  Future<void> sendGroupInvite(String cid, String uid) async {
    sendCalls += 1;
    if (gate != null) await gate!.future;
    if (_failFor.contains(uid)) throw StateError('boom send secret');
  }

  @override
  Future<List<PendingGroupInvite>> getPendingInvitesForConversation(
    String cid,
  ) async {
    inviteFetches += 1;
    return const [];
  }

  @override
  Future<Map<String, String>> getInviteStatusesForConversation(
    String cid,
  ) async =>
      statuses;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'MessageRepository.${invocation.memberName} not stubbed',
      );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester, {
  required _Repo repo,
  required FriendshipsNotifier Function() friendships,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        conversationStreamProvider
            .overrideWith((ref, id) => Stream.value(_conv)),
        groupMembersProvider.overrideWith((ref, id) => Stream.value([
          _user(id: 'u_me', name: 'Mira Joshi', username: 'mira', role: 'admin'),
          _user(id: 'u_zed', name: 'Zed', username: 'zed'),
        ])),
        currentUserIdProvider.overrideWith((ref) async => 'u_me'),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        disappearingDurationProvider
            .overrideWith((ref, id) => Stream<int>.value(0)),
        friendshipsProvider.overrideWith(friendships),
        pendingInvitesProvider.overrideWith((ref, id) async =>
            repo.getPendingInvitesForConversation(id)),
        messageRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: GroupSettingsScreen(conversation: _conv),
      ),
    ),
  );
  await _settle(tester);
}

/// A row inside the sheet — scoped so the identically-named member row
/// behind the modal is never the tap target.
Finder _row(String name) => find.descendant(
      of: find.byKey(_sheetKey),
      matching: find.text(name),
    );

/// Opens the Add-members sheet from the `＋ Add` chip.
Future<void> _openSheet(WidgetTester tester) async {
  await tester.ensureVisible(find.text('＋ Add'));
  await _settle(tester);
  await tester.tap(find.text('＋ Add'));
  await _settle(tester);
  expect(find.text('Add to group'), findsOneWidget);
}

/// Selects each [names] row and presses the matching Invite button.
Future<void> _send(WidgetTester tester, List<String> names) async {
  for (final name in names) {
    await tester.tap(_row(name));
    await tester.pump();
  }
  await tester.tap(find.text('Invite ${names.length}'));
  await _settle(tester);
}

/// The sheet's single Invite button (its label is swapped for a spinner
/// while busy, so it is addressed by type inside the sheet).
Finder _inviteButton() => find.descendant(
      of: find.byKey(_sheetKey),
      matching: find.byType(AppButton),
    );

void main() {
  testWidgets('friends still loading never flashes "Everyone\'s here"',
      (tester) async {
    final repo = _Repo();
    await _pump(tester, repo: repo, friendships: _LoadingFriendships.new);

    await _openSheet(tester);

    expect(find.text("Everyone's here"), findsNothing);
    expect(
      find.text('All your friends are already in this group.'),
      findsNothing,
    );
    expect(find.byType(Skeleton), findsWidgets);
  });

  testWidgets(
      'friends error shows the banner + Retry and hides the empty state',
      (tester) async {
    final repo = _Repo();
    await _pump(tester, repo: repo, friendships: _ErrorFriendships.new);

    await _openSheet(tester);

    expect(find.text("Couldn't load friends."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text("Everyone's here"), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('status meta shows invite status ahead of the handle',
      (tester) async {
    final repo = _Repo(statuses: {
      'u_pending': 'pending',
      'u_declined': 'declined',
    });
    await _pump(
      tester,
      repo: repo,
      friendships: () => _DataFriendships([
        _friend(_user(id: 'u_pending', name: 'Priya', username: 'priya')),
        _friend(_user(id: 'u_declined', name: 'Dev', username: 'dev')),
        _friend(_user(id: 'u_plain', name: 'Sam', username: 'sam')),
      ]),
    );

    await _openSheet(tester);

    expect(find.text('Invite pending'), findsOneWidget);
    expect(find.text('Declined — invite again?'), findsOneWidget);
    expect(find.text('@sam'), findsOneWidget);
  });

  testWidgets('the sheet stays open and busy while the send is in flight',
      (tester) async {
    final repo = _Repo()..gate = Completer<void>();
    await _pump(
      tester,
      repo: repo,
      friendships: () => _DataFriendships([
        _friend(_user(id: 'u_a', name: 'Alina', username: 'alina')),
      ]),
    );

    await _openSheet(tester);
    await _send(tester, ['Alina']);

    // Sending: the sheet is still mounted, the button is busy, the rows are
    // inert and dimmed, and no toast has been shown yet.
    expect(find.text('Add to group'), findsOneWidget);
    expect(repo.sendCalls, 1);
    final button = tester.widget<AppButton>(_inviteButton());
    expect(button.busy, isTrue);
    expect(
      tester
          .widgetList<IgnorePointer>(find.byType(IgnorePointer))
          .any((w) => w.ignoring),
      isTrue,
    );
    expect(find.text('Invite sent'), findsNothing);

    repo.gate!.complete();
    await _settle(tester);

    expect(find.text('Invite sent'), findsOneWidget);
    expect(find.text('Add to group'), findsNothing);
  });

  testWidgets('sending invalidates the pending-invites list', (tester) async {
    final repo = _Repo();
    await _pump(
      tester,
      repo: repo,
      friendships: () => _DataFriendships([
        _friend(_user(id: 'u_a', name: 'Alina', username: 'alina')),
      ]),
    );

    await _openSheet(tester);
    final before = repo.inviteFetches;
    expect(before, greaterThan(0), reason: 'screen watched invites on build');

    await _send(tester, ['Alina']);

    expect(find.text('Invite sent'), findsOneWidget);
    expect(
      repo.inviteFetches,
      greaterThan(before),
      reason: 'pendingInvitesProvider must refetch after a send',
    );
  });

  testWidgets('one invite sends → "Invite sent"', (tester) async {
    final repo = _Repo();
    await _pump(
      tester,
      repo: repo,
      friendships: () => _DataFriendships([
        _friend(_user(id: 'u_a', name: 'Alina', username: 'alina')),
      ]),
    );

    await _openSheet(tester);
    await _send(tester, ['Alina']);

    expect(find.text('Invite sent'), findsOneWidget);
    expect(find.text('1 invites sent'), findsNothing);
  });

  testWidgets('two invites → "{n} invites sent"', (tester) async {
    final repo = _Repo();
    await _pump(
      tester,
      repo: repo,
      friendships: () => _DataFriendships([
        _friend(_user(id: 'u_a', name: 'Alina', username: 'alina')),
        _friend(_user(id: 'u_b', name: 'Brody', username: 'brody')),
      ]),
    );

    await _openSheet(tester);
    await _send(tester, ['Alina', 'Brody']);

    expect(find.text('2 invites sent'), findsOneWidget);
    expect(find.text('Invite sent'), findsNothing);
  });

  testWidgets('partial failure toasts "{ok} sent, {failed} failed. Try again."',
      (tester) async {
    final repo = _Repo(failFor: {'u_b'});
    await _pump(
      tester,
      repo: repo,
      friendships: () => _DataFriendships([
        _friend(_user(id: 'u_a', name: 'Alina', username: 'alina')),
        _friend(_user(id: 'u_b', name: 'Brody', username: 'brody')),
      ]),
    );

    await _openSheet(tester);
    await _send(tester, ['Alina', 'Brody']);

    expect(find.text('1 sent, 1 failed. Try again.'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
  });
}
