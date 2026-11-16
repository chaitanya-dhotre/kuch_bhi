// Calm-rest spec, part 3 test gates 10–11, plus the A7 one-clock check for
// Requests, Group info and New group, and the D7 tab check.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/core/widgets/app_button.dart';
import 'package:kuch_bhi/core/widgets/app_chip.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/friend_request.dart';
import 'package:kuch_bhi/domain/entities/friendship.dart';
import 'package:kuch_bhi/domain/entities/group_invite.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/friend_requests/providers/friend_request_provider.dart';
import 'package:kuch_bhi/features/friend_requests/screens/friend_requests_screen.dart';
import 'package:kuch_bhi/features/friend_requests/widgets/request_card.dart';
import 'package:kuch_bhi/features/groups/providers/group_admin_provider.dart';
import 'package:kuch_bhi/features/groups/screens/create_group_screen.dart';
import 'package:kuch_bhi/features/groups/screens/group_settings_screen.dart';
import 'package:kuch_bhi/features/home/providers/friends_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:pocketbase/pocketbase.dart';

User _user(String id, String name, {String role = 'member'}) => User(
  id: id,
  displayName: name,
  username: id,
  email: '$id@example.com',
  friendCode: 'CODE01',
  createdAt: DateTime(2026, 1, 1),
  groupRole: role,
);

FriendRequest _request(String id, String name) => FriendRequest(
  id: id,
  fromUser: _user('u_$id', name),
  toUser: _user('me', 'Me'),
  status: 'pending',
  createdAt: DateTime(2026, 10, id == 'r1' ? 21 : 20), // r1 sorts first
);

class _Requests extends IncomingRequestsNotifier {
  _Requests({this.loading = false});
  final bool loading;

  @override
  Future<List<FriendRequest>> build() => loading
      ? Completer<List<FriendRequest>>().future
      : Future.value([_request('r1', 'Mira Joshi'), _request('r2', 'Arjun')]);

  @override
  Future<void> accept(String id) async {}
}

class _NoInvites extends IncomingGroupInvitesNotifier {
  @override
  Future<List<GroupInvite>> build() async => const [];
}

class _Friends extends FriendshipsNotifier {
  _Friends({this.loading = false});
  final bool loading;

  @override
  Future<List<Friendship>> build() => loading
      ? Completer<List<Friendship>>().future
      : Future.value([
          for (final n in ['Alina', 'Bela', 'Chirag', 'Dev'])
            Friendship(
              id: 'f_$n',
              friend: _user('u_$n', n),
              createdAt: DateTime(2026, 1, 1),
            ),
        ]);
}

class _NoAuth extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthUnauthenticated();
}

Widget _app(Widget home, List<Override> overrides, {bool reduced = false}) =>
    ProviderScope(
      overrides: [
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ...overrides,
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: home,
      ),
    );

Widget _requests({bool loading = false, bool reduced = false}) => _app(
  const FriendRequestsScreen(),
  [
    incomingRequestsProvider.overrideWith(() => _Requests(loading: loading)),
    incomingGroupInvitesProvider.overrideWith(_NoInvites.new),
  ],
  reduced: reduced,
);

const _conv = Conversation(
  id: 'conv-1',
  type: 'group',
  name: 'Weekend Trekkers',
  onlyAdminsCanMessage: false,
);

Widget _groupInfo(Stream<List<User>> members, {bool reduced = false}) => _app(
  const GroupSettingsScreen(conversation: _conv),
  [
    conversationStreamProvider.overrideWith(
      (ref, id) => Stream<Conversation?>.value(_conv),
    ),
    groupMembersProvider.overrideWith((ref, id) => members),
    currentUserIdProvider.overrideWith((ref) async => 'u_me'),
    pendingInvitesProvider.overrideWith((ref, id) async => const []),
    disappearingDurationProvider.overrideWith((ref, id) => Stream.value(0)),
  ],
  reduced: reduced,
);

Widget _newGroup({bool loading = false, bool reduced = false}) => _app(
  const CreateGroupScreen(),
  [
    friendshipsProvider.overrideWith(() => _Friends(loading: loading)),
    authProvider.overrideWith(_NoAuth.new),
    appDatabaseProvider.overrideWithValue(AppDatabase.test()),
    pocketbaseClientProvider.overrideWithValue(
      PocketBaseClient.forTest(PocketBase('http://localhost')),
    ),
  ],
  reduced: reduced,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 350)); // skeleton delay
  await tester.pump();
}

/// Every Skeleton on screen has exactly one SkeletonGroup above it, and
/// they all share the same one.
void _oneClock(WidgetTester tester) {
  final blocks = find.byType(Skeleton);
  expect(blocks, findsWidgets);
  final groups = <Element>{};
  for (final e in blocks.evaluate()) {
    final above = <Element>[];
    e.visitAncestorElements((a) {
      if (a.widget is SkeletonGroup) above.add(a);
      return true;
    });
    expect(above, hasLength(1));
    groups.add(above.single);
  }
  expect(groups, hasLength(1));
}

/// The fill of the nearest decorated box around [text].
Color? _pillFill(WidgetTester tester, String text) {
  final box = tester.widget<Container>(
    find.ancestor(of: find.text(text), matching: find.byType(Container)).first,
  );
  return (box.decoration! as ShapeDecoration).color;
}

final _members = [
  _user('u_me', 'Me', role: 'admin'),
  _user('u_a', 'Arjun'),
  _user('u_b', 'Meera'),
];

void main() {
  final t = warmPopLight().extension<ColorTokens>()!;

  group('gate 10: request card', () {
    testWidgets('Accept is tonal, Decline secondary', (tester) async {
      await tester.pumpWidget(_requests());
      await _settle(tester);
      AppButtonVariant of(String label) => tester
          .widget<AppButton>(find.widgetWithText(AppButton, label).first)
          .variant;
      expect(of('Accept'), AppButtonVariant.tonal);
      expect(of('Decline'), AppButtonVariant.secondary);
    });

    testWidgets('accepting removes the card after motionExit, rest move up',
        (tester) async {
      await tester.pumpWidget(_requests());
      await _settle(tester);
      final firstTop = tester.getTopLeft(find.byType(RequestCard).first).dy;

      await tester.tap(find.widgetWithText(AppButton, 'Accept').first);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Mira Joshi'), findsOneWidget, reason: 'still leaving');

      await tester.pump(WarmPopTokens.motionExit);
      await tester.pump();
      expect(find.text('Mira Joshi'), findsNothing);
      expect(tester.getTopLeft(find.byType(RequestCard)).dy, firstTop);
      await tester.pump(const Duration(seconds: 4)); // toast timer
    });

    testWidgets('under reduced motion the card is removed at once',
        (tester) async {
      await tester.pumpWidget(_requests(reduced: true));
      await _settle(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Accept').first);
      await tester.pump();
      await tester.pump();
      expect(find.text('Mira Joshi'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('gate 11: group info and new group', () {
    testWidgets('Add is tonal and the Admin pill has no accent',
        (tester) async {
      await tester.pumpWidget(_groupInfo(Stream.value(_members)));
      await _settle(tester);
      expect(_pillFill(tester, '＋ Add'), t.bubbleMine);
      expect(_pillFill(tester, 'Admin'), t.surface2);
      expect(tester.widget<Text>(find.text('Admin')).style!.color, t.inkSoft);
    });

    testWidgets('D5: a removed member leaves over motionExit',
        (tester) async {
      final members = StreamController<List<User>>();
      addTearDown(members.close);
      await tester.pumpWidget(_groupInfo(members.stream));
      members.add(_members);
      await _settle(tester);
      expect(find.text('Meera'), findsOneWidget);

      members.add(_members.sublist(0, 2));
      await tester.pump();
      await tester.pump();
      expect(find.text('Meera'), findsOneWidget, reason: 'still leaving');
      await tester.pump(const Duration(milliseconds: 16)); // first tick
      await tester.pump(WarmPopTokens.motionExit);
      await tester.pump();
      expect(find.text('Meera'), findsNothing);
      expect(find.text('Arjun'), findsOneWidget);
    });

    testWidgets('D5: under reduced motion the member is removed at once',
        (tester) async {
      final members = StreamController<List<User>>();
      addTearDown(members.close);
      await tester.pumpWidget(_groupInfo(members.stream, reduced: true));
      members.add(_members);
      await _settle(tester);
      members.add(_members.sublist(0, 2));
      await tester.pump();
      await tester.pump();
      expect(find.text('Meera'), findsNothing);
    });

    testWidgets('New group: a chip per ticked person, gone on untick',
        (tester) async {
      await tester.pumpWidget(_newGroup());
      await _settle(tester);
      expect(find.byType(AppChip), findsNothing);

      for (final n in ['Alina', 'Bela', 'Chirag']) {
        await tester.tap(find.text(n).last);
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 1)); // springs settle
      expect(find.byType(AppChip), findsNWidgets(3));
      expect(
        tester.widgetList<AppChip>(find.byType(AppChip)).any((c) => c.selected),
        isFalse,
        reason: 'D6: the R4 unselected look',
      );

      await tester.tap(find.text('Bela').last); // the list row unticks
      await tester.pump();
      expect(find.byType(AppChip), findsNWidgets(3), reason: 'still leaving');
      await tester.pump(const Duration(milliseconds: 16)); // first tick
      await tester.pump(WarmPopTokens.motionPress);
      await tester.pump();
      expect(find.byType(AppChip), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('A7: one clock per loading layout', () {
    testWidgets('Requests', (tester) async {
      await tester.pumpWidget(_requests(loading: true));
      await _settle(tester);
      _oneClock(tester);
    });

    testWidgets('Group info', (tester) async {
      final never = StreamController<List<User>>();
      addTearDown(never.close);
      await tester.pumpWidget(_groupInfo(never.stream));
      await _settle(tester);
      _oneClock(tester);
    });

    testWidgets('New group', (tester) async {
      await tester.pumpWidget(_newGroup(loading: true));
      await _settle(tester);
      _oneClock(tester);
      await tester.pumpWidget(const SizedBox());
    });

    test('no Skeleton passes its own duration', () {
      for (final f in [
        'lib/features/friend_requests/screens/friend_requests_screen.dart',
        'lib/features/groups/screens/group_settings_screen.dart',
        'lib/features/groups/screens/create_group_screen.dart',
      ]) {
        expect(File(f).readAsStringSync(), isNot(contains('duration: _')));
        expect(File(f).readAsStringSync(), isNot(contains('1400')));
      }
    });
  });

  test('D7: Add a friend takes its tabs from the shared tabBarTheme', () {
    final src = File(
      'lib/features/home/screens/add_friend_screen.dart',
    ).readAsStringSync();
    expect(src, isNot(contains('indicator:')));
    expect(src, isNot(contains('labelColor:')));
  });
}
