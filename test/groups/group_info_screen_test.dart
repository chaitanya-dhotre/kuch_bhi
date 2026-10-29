/// Group Info — load states, member ordering, settings visibility matrix,
/// invites errors, offline single-dim, and merged row semantics
/// (checklist test gate: `group_info_screen_test.dart`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/group_invite.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/features/chat/message_offline_policy.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/groups/providers/group_admin_provider.dart';
import 'package:kuch_bhi/features/groups/screens/group_settings_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';

const _offlineCopy =
    "You're offline — actions are available when you're back.";

User _member({
  required String id,
  String name = '',
  String username = 'user',
  String role = 'member',
}) =>
    User(
      id: id,
      displayName: name,
      username: username,
      email: '$username@example.com',
      friendCode: 'CODE01',
      createdAt: DateTime(2026, 1, 1),
      groupRole: role,
    );

Conversation _conv({String name = 'Weekend Trekkers'}) => Conversation(
      id: 'conv-1',
      type: 'group',
      name: name,
      onlyAdminsCanMessage: false,
    );

PendingGroupInvite _invite({required String id, String status = 'pending'}) =>
    PendingGroupInvite(
      inviteId: id,
      user: _member(id: 'u_$id', name: 'Dee', username: 'dee'),
      status: status,
    );

/// Builds the screen with every provider it watches pinned to a fixture.
Widget _host({
  Conversation? conv,
  List<User>? members,
  bool membersError = false,
  bool membersLoading = false,
  bool invitesError = false,
  List<PendingGroupInvite> invites = const [],
  bool online = true,
  String myId = 'u_me',
}) {
  final convStream = Stream<Conversation?>.value(conv ?? _conv());
  final memberStream = membersLoading
      ? StreamController<List<User>>().stream
      : membersError
          ? Stream<List<User>>.error(Exception('boom members secret'))
          : Stream<List<User>>.value(members ?? [_member(id: myId, name: 'You')]);
  final inviteStream = Future<List<PendingGroupInvite>>.value(invites);

  return ProviderScope(
    overrides: [
      conversationStreamProvider.overrideWith((ref, id) => convStream),
      groupMembersProvider.overrideWith((ref, id) => memberStream),
      currentUserIdProvider.overrideWith((ref) async => myId),
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
      pendingInvitesProvider.overrideWith((ref, id) async {
        if (invitesError) throw Exception('boom invites secret');
        return inviteStream;
      }),
      disappearingDurationProvider.overrideWith((ref, id) => Stream<int>.value(0)),
    ],
    child: MaterialApp(
      theme: warmPopLight(),
      home: GroupSettingsScreen(conversation: conv ?? _conv()),
    ),
  );
}

/// Pumps past the async `currentUserIdProvider` round-trip so the screen
/// sees the session id on the frame under test.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('loading renders the R11 skeleton with the app bar, no spinner',
      (tester) async {
    await tester.pumpWidget(_host(membersLoading: true));
    await _settle(tester);

    expect(find.text('Group Info'), findsOneWidget);
    expect(find.byType(Skeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'members stream error shows the R12 banner — not "0 members" and no '
      'admin affordances', (tester) async {
    await tester.pumpWidget(_host(membersError: true));
    await _settle(tester);

    expect(find.text("Couldn't load members."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('0 members'), findsNothing);
    expect(find.text('＋ Add'), findsNothing);
    // The header still renders from the conversation.
    expect(find.text('Weekend Trekkers'), findsOneWidget);
    // The exception text never reaches the screen.
    expect(find.textContaining('boom'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('members are ordered you → admins A→Z → members A→Z',
      (tester) async {
    await tester.pumpWidget(_host(members: [
      _member(id: 'u_zoe', name: 'zoe', username: 'zoe', role: 'member'),
      _member(id: 'u_brody', name: 'Brody', username: 'brody', role: 'admin'),
      _member(id: 'u_amy', name: 'Amy', username: 'amy', role: 'member'),
      _member(id: 'u_alina', name: 'Alina', username: 'alina', role: 'admin'),
      _member(id: 'u_me', name: 'Mira Joshi', username: 'mira', role: 'member'),
    ]));
    await _settle(tester);

    final order = [
      'Mira Joshi',
      'Alina',
      'Brody',
      'Amy',
      'zoe',
    ];
    final ys = [
      for (final name in order) tester.getTopLeft(find.text(name)).dy,
    ];
    expect(ys, List.of(ys)..sort(), reason: 'expected $order on screen');
    expect(find.text('1 member'), findsNothing);
    expect(find.text('5 members'), findsOneWidget);
  });

  testWidgets('a single member renders the singular count', (tester) async {
    await tester.pumpWidget(
      _host(members: [_member(id: 'u_me', name: 'Mira Joshi')]),
    );
    await _settle(tester);

    expect(find.text('1 member'), findsOneWidget);
    expect(find.text('1 members'), findsNothing);
  });

  testWidgets('empty group name and empty member name never crash',
      (tester) async {
    await tester.pumpWidget(
      _host(
        conv: _conv(name: ''),
        members: [
          _member(id: 'u_me', name: '   '),
          _member(id: 'u_ghost', name: '', username: 'ghost'),
        ],
      ),
    );
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('Unknown'), findsNWidgets(2));
  });

  testWidgets('visibility matrix: admin sees every settings row', (tester) async {
    await tester.pumpWidget(_host(members: [
      _member(id: 'u_me', name: 'Mira Joshi', role: 'admin'),
      _member(id: 'u_a', name: 'Alina', role: 'admin'),
    ]));
    await _settle(tester);

    expect(find.text('Only Admins Can Message'), findsOneWidget);
    expect(find.text('Disappearing Messages'), findsOneWidget);
    expect(find.text('Media & Docs'), findsOneWidget);
    expect(find.text('Leave Group'), findsOneWidget);
    expect(find.text('＋ Add'), findsOneWidget);
  });

  testWidgets('visibility matrix: member loses admin-only affordances',
      (tester) async {
    await tester.pumpWidget(_host(members: [
      _member(id: 'u_me', name: 'Mira Joshi', role: 'member'),
      _member(id: 'u_a', name: 'Alina', role: 'admin'),
    ]));
    await _settle(tester);

    expect(find.text('Only Admins Can Message'), findsNothing);
    expect(find.text('＋ Add'), findsNothing);
    expect(find.text('Disappearing Messages'), findsOneWidget);
    expect(find.text('Media & Docs'), findsOneWidget);
    expect(find.text('Leave Group'), findsOneWidget);
  });

  testWidgets('visibility matrix: a left member sees Media & Docs only',
      (tester) async {
    await tester.pumpWidget(_host(members: [
      _member(id: 'u_me', name: 'Mira Joshi', role: 'left'),
      _member(id: 'u_a', name: 'Alina', role: 'admin'),
    ]));
    await _settle(tester);

    expect(find.text("You're no longer in this group."), findsOneWidget);
    expect(find.text('Media & Docs'), findsOneWidget);
    expect(find.text('Disappearing Messages'), findsNothing);
    expect(find.text('Leave Group'), findsNothing);
    expect(find.text('Only Admins Can Message'), findsNothing);
    expect(find.text('＋ Add'), findsNothing);
  });

  testWidgets('an invites fetch failure shows the R12 banner + Retry',
      (tester) async {
    await tester.pumpWidget(_host(
      members: [_member(id: 'u_me', name: 'Mira Joshi', role: 'admin')],
      invitesError: true,
    ));
    await _settle(tester);

    expect(find.text("Couldn't load invites."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
  });

  testWidgets('invites render rows and hide accepted ones', (tester) async {
    await tester.pumpWidget(_host(
      members: [_member(id: 'u_me', name: 'Mira Joshi', role: 'admin')],
      invites: [
        _invite(id: 'i1', status: 'pending'),
        _invite(id: 'i2', status: 'declined'),
        _invite(id: 'i3', status: 'accepted'),
      ],
    ));
    await _settle(tester);

    expect(find.text('Invite pending'), findsOneWidget);
    expect(find.text('Declined'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Re-invite'), findsOneWidget);
  });

  testWidgets(
      'offline: strip copy, exactly one hint, and no nested dim layers',
      (tester) async {
    await tester.pumpWidget(_host(
      online: false,
      members: [
        _member(id: 'u_me', name: 'Mira Joshi', role: 'admin'),
        _member(id: 'u_a', name: 'Alina', role: 'admin'),
      ],
    ));
    await _settle(tester);

    expect(find.text(_offlineCopy), findsOneWidget);
    expect(find.text(kOfflineActionHint), findsOneWidget);

    final dims = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .where((o) => o.opacity == 0.38)
        .toList();
    expect(dims, isNotEmpty, reason: 'each disabled surface dims once');
    for (final dim in dims) {
      final nested = tester
          .widgetList<Opacity>(find.descendant(
            of: find.byWidget(dim),
            matching: find.byType(Opacity),
          ))
          .where((o) => o.opacity == 0.38);
      expect(nested, isEmpty, reason: 'double dim is a FAIL (chat L3 law)');
    }

    // Hidden while offline: invites + admin actions.
    expect(find.text('＋ Add'), findsOneWidget);
  });

  testWidgets('online: no offline strip and no hint', (tester) async {
    await tester.pumpWidget(_host());
    await _settle(tester);

    expect(find.text(_offlineCopy), findsNothing);
    expect(find.text(kOfflineActionHint), findsNothing);
  });

  testWidgets(
      'member row carries one merged label + admin viewer hint; ⋮ is labelled',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(members: [
      _member(id: 'u_me', name: 'Mira Joshi', username: 'mira', role: 'admin'),
      _member(
        id: 'u_a',
        name: 'Alina',
        username: 'alina',
        role: 'member',
      ),
    ]));
    await _settle(tester);

    expect(find.bySemanticsLabel('Mira Joshi, admin, you'), findsOneWidget);
    expect(find.bySemanticsLabel('Alina, @alina'), findsOneWidget);
    expect(find.bySemanticsLabel('Options for Alina'), findsOneWidget);
    expect(find.bySemanticsLabel('Change group photo'), findsOneWidget);
    expect(find.bySemanticsLabel('Edit group name'), findsOneWidget);
    handle.dispose();
  });
}
