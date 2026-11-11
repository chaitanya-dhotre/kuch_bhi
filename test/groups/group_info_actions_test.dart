/// Group Info mutation outcomes: per-row busy locks, the 8s/30s UI bounds,
/// failure toasts, the settings matrix gates and the switch snap-back
/// (checklist test gate: `group_info_actions_test.dart`).
///
/// The REAL `GroupAdminNotifier` runs against a fake `MessageRepository`, so
/// the bounds, busy keys and invalidations under test are the production ones.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/mascot/capy.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/busy_spinner.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/group_invite.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/groups/providers/group_admin_provider.dart';
import 'package:kuch_bhi/features/groups/screens/group_settings_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import '../mascot/capy_test.dart' show FakeSource;

const _updateFailed = "Couldn't update. Try again.";
const _stillWorking = "Still working — this can take a moment.";

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

Conversation _conv({bool onlyAdmins = false}) => Conversation(
      id: 'conv-1',
      type: 'group',
      name: 'Weekend Trekkers',
      onlyAdminsCanMessage: onlyAdmins,
    );

class _Repo implements MessageRepository {
  _Repo({List<PendingGroupInvite> invites = const []}) : _invites = invites;

  final List<PendingGroupInvite> _invites;

  var promoteCalls = 0;
  var demoteCalls = 0;
  var removeCalls = 0;
  var leaveCalls = 0;
  var cancelCalls = 0;
  var reInviteCalls = 0;
  var switchCalls = 0;
  var renameCalls = 0;
  var photoCalls = 0;

  /// When set, every call hangs on it (a blackholed socket).
  Completer<void>? gate;

  Object? promoteError;
  Object? demoteError;
  Object? removeError;
  Object? leaveError;
  Object? cancelError;
  Object? reInviteError;
  Object? switchError;
  Object? renameError;
  Object? photoError;

  @override
  Future<void> promoteMemberToAdmin(String cid, String uid) async {
    promoteCalls++;
    await _count(promoteError);
  }

  @override
  Future<void> demoteAdminToMember(String cid, String uid) async {
    demoteCalls++;
    await _count(demoteError);
  }

  @override
  Future<void> removeMemberFromGroup(String cid, String uid) async {
    removeCalls++;
    await _count(removeError);
  }

  @override
  Future<void> leaveGroup(String cid) async {
    leaveCalls++;
    await _count(leaveError);
  }

  @override
  Future<void> cancelGroupInvite(String inviteId) async {
    cancelCalls++;
    await _count(cancelError);
  }

  @override
  Future<void> sendGroupInvite(String cid, String uid) async {
    reInviteCalls++;
    await _count(reInviteError);
  }

  @override
  Future<void> setOnlyAdminsCanMessage(String cid, bool value) async {
    switchCalls++;
    await _count(switchError);
  }

  @override
  Future<void> updateGroupInfo(String cid, {String? name, File? iconFile}) async {
    if (name != null) {
      renameCalls++;
      await _count(renameError);
    } else {
      photoCalls++;
      await _count(photoError);
    }
  }

  Future<void> _count(Object? error) async {
    if (gate != null) await gate!.future;
    if (error != null) throw error;
  }

  @override
  Future<List<PendingGroupInvite>> getPendingInvitesForConversation(
    String cid,
  ) async =>
      _invites;

  @override
  Future<Map<String, String>> getInviteStatusesForConversation(
    String cid,
  ) async =>
      const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'MessageRepository.${invocation.memberName} not stubbed',
      );
}

/// Same shape as the Requests harness: session, streams and connectivity are
/// pinned so the screen renders a deterministic admin view.
Future<void> _pumpInfo(
  WidgetTester tester, {
  required _Repo repo,
  List<User>? members,
  bool online = true,
  bool onlyAdmins = false,
}) async {
  final rows = members ??
      [
        _member(id: 'u_me', name: 'Mira Joshi', username: 'mira', role: 'admin'),
        _member(id: 'u_a', name: 'Alina', username: 'alina', role: 'member'),
        _member(id: 'u_b', name: 'Brody', username: 'brody', role: 'admin'),
      ];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        conversationStreamProvider
            .overrideWith((ref, id) => Stream.value(_conv(onlyAdmins: onlyAdmins))),
        groupMembersProvider.overrideWith((ref, id) => Stream.value(rows)),
        currentUserIdProvider.overrideWith((ref) async => 'u_me'),
        isOnlineProvider.overrideWith((ref) => Stream.value(online)),
        disappearingDurationProvider
            .overrideWith((ref, id) => Stream.value(0)),
        messageRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: GroupSettingsScreen(conversation: _conv(onlyAdmins: onlyAdmins)),
      ),
    ),
  );
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

/// Bounded settling: routes (sheet, dialog) animate for ~300ms, but a
/// `pumpAndSettle` would spin forever against the repeating
/// `BusySpinner` ticker and burn >3s of fake time — which would also age
/// the SnackBar out before it can be asserted.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

/// Scrolls the body until [finder] is inside the 800x600 test viewport,
/// so the tap lands on the widget instead of outside the render tree.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _settle(tester);
}

Future<void> _action(
  WidgetTester tester,
  String rowName,
  String actionLabel, {
  String? confirmLabel,
}) async {
  await _reveal(tester, find.text(rowName));
  await tester.tap(find.text(rowName));
  await _settle(tester);
  await tester.tap(find.text(actionLabel));
  await _settle(tester);
  if (confirmLabel != null) {
    await tester.tap(find.text(confirmLabel));
    await _settle(tester);
  }
}

void main() {
  testWidgets(
      'per-row busy: spinner replaces the trailing area, a second tap no-ops, '
      'other rows stay live', (tester) async {
    final repo = _Repo()..gate = Completer<void>();
    await _pumpInfo(tester, repo: repo);

    await _action(tester, 'Alina', 'Make Admin');
    await tester.pump();

    expect(find.byType(BusySpinner), findsOneWidget);
    expect(repo.promoteCalls, 1);

    // Second tap on the busy row must not open the sheet again.
    await tester.tap(find.text('Alina'));
    await _settle(tester);
    expect(find.byKey(const Key('action-sheet')), findsNothing);

    // Another row is still live.
    await tester.tap(find.text('Brody'));
    await _settle(tester);
    expect(find.byKey(const Key('action-sheet')), findsOneWidget);
    expect(find.text('Remove Admin'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await _settle(tester);

    // Drain the 8s bound so no timer outlives the test body.
    await tester.pump(const Duration(seconds: 9));
  });

  testWidgets('promote failure toasts the stable copy, never the exception',
      (tester) async {
    final repo = _Repo()..promoteError = StateError('secret-promote');
    await _pumpInfo(tester, repo: repo);

    await _action(tester, 'Alina', 'Make Admin');

    expect(find.text(_updateFailed), findsOneWidget);
    expect(find.textContaining('secret-promote'), findsNothing);
    expect(find.byType(BusySpinner), findsNothing);
  });

  testWidgets('demote failure toasts the stable copy, never the exception',
      (tester) async {
    final repo = _Repo()..demoteError = StateError('secret-demote');
    await _pumpInfo(tester, repo: repo);

    await _action(tester, 'Brody', 'Remove Admin');

    expect(find.text(_updateFailed), findsOneWidget);
    expect(find.textContaining('secret-demote'), findsNothing);
  });

  testWidgets('remove failure toasts the stable copy, never the exception',
      (tester) async {
    final repo = _Repo()..removeError = StateError('secret-remove');
    await _pumpInfo(tester, repo: repo);

    await _action(
      tester,
      'Alina',
      'Remove from Group',
      confirmLabel: 'Remove',
    );

    expect(find.text(_updateFailed), findsOneWidget);
    expect(find.textContaining('secret-remove'), findsNothing);
    expect(find.textContaining('New group key made'), findsNothing);
  });

  testWidgets('promote success toasts "{name} is now an admin"', (tester) async {
    final repo = _Repo();
    await _pumpInfo(tester, repo: repo);

    await _action(tester, 'Alina', 'Make Admin');

    expect(find.text('Alina is now an admin'), findsOneWidget);
  });

  testWidgets('demote success toasts "{name} is no longer an admin"',
      (tester) async {
    final repo = _Repo();
    await _pumpInfo(tester, repo: repo);

    await _action(tester, 'Brody', 'Remove Admin');

    expect(find.text('Brody is no longer an admin'), findsOneWidget);
  });

  testWidgets('remove success toasts and announces "{name} removed"',
      (tester) async {
    final announcements = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/accessibility',
      (message) async {
        const codec = StandardMessageCodec();
        final decoded =
            message is ByteData ? codec.decodeMessage(message) : message;
        final args = (decoded as Map?) ?? {};
        if (args['type'] == 'announce') {
          final data = (args['data'] as Map?) ?? {};
          announcements.add('${data['message']}');
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMessageHandler('flutter/accessibility', null);
    });

    final repo = _Repo();
    await _pumpInfo(tester, repo: repo);

    await _action(
      tester,
      'Alina',
      'Remove from Group',
      confirmLabel: 'Remove',
    );

    expect(find.text('Alina removed'), findsOneWidget);
    expect(
      announcements.any((a) => a.contains('Alina') && a.contains('removed')),
      isTrue,
      reason: 'expected an announcement, got $announcements',
    );
  });

  testWidgets('a blackholed promote releases at 8s and is not retried',
      (tester) async {
    final repo = _Repo()..gate = Completer<void>();
    await _pumpInfo(tester, repo: repo);

    await _action(tester, 'Alina', 'Make Admin');
    await tester.pump();
    expect(find.byType(BusySpinner), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    expect(find.byType(BusySpinner), findsOneWidget,
        reason: 'still busy inside the 8s bound');
    expect(find.text(_updateFailed), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(BusySpinner), findsNothing);
    expect(find.text(_updateFailed), findsOneWidget);
    expect(repo.promoteCalls, 1);
  });

  testWidgets(
      'a blackholed remove releases at 30s with "Still working…" and the '
      'repository is NOT called again', (tester) async {
    final repo = _Repo()..gate = Completer<void>();
    await _pumpInfo(tester, repo: repo);

    await _action(
      tester,
      'Alina',
      'Remove from Group',
      confirmLabel: 'Remove',
    );
    await tester.pump();
    expect(find.byType(BusySpinner), findsOneWidget);
    expect(repo.removeCalls, 1);

    await tester.pump(const Duration(seconds: 25));
    expect(find.byType(BusySpinner), findsOneWidget);
    expect(find.text(_stillWorking), findsNothing);

    await tester.pump(const Duration(seconds: 10));
    expect(find.byType(BusySpinner), findsNothing);
    expect(find.text(_stillWorking), findsOneWidget);

    // The UI never cancels or retries the in-flight repository call.
    await tester.pump(const Duration(seconds: 60));
    expect(repo.removeCalls, 1);
    expect(find.textContaining('New group key made'), findsNothing);
  });

  testWidgets('K3: a successful remove shows the key card once; the toast '
      'still shows', (tester) async {
    final capys = FakeSource();
    CapyLoader.debugSource = capys;
    addTearDown(() => CapyLoader.debugSource = null);
    final repo = _Repo();
    await _pumpInfo(tester, repo: repo);
    expect(find.textContaining('New group key made'), findsNothing);
    expect(capys.rigs, isEmpty);

    await _action(
      tester,
      'Alina',
      'Remove from Group',
      confirmLabel: 'Remove',
    );

    expect(find.text('Alina removed'), findsOneWidget);
    expect(find.text("New group key made. Alina can't read new messages."),
        findsOneWidget);
    final rig = capys.rigs.single;
    expect(capys.views.single, CapyView.front);
    expect(rig.pose, CapyPose.guard);
    expect(rig.bools['still'], isTrue, reason: 'swaps once, then holds still');
    expect(rig.fired, ['swapKey']);
    await tester.pump(const Duration(seconds: 2));
    expect(rig.fired, ['swapKey'], reason: 'no replay on rebuilds');
  });

  testWidgets('"Remove Admin" is hidden when there is only one admin',
      (tester) async {
    final repo = _Repo();
    await _pumpInfo(tester, repo: repo, members: [
      _member(id: 'u_me', name: 'Mira Joshi', username: 'mira', role: 'admin'),
      _member(id: 'u_a', name: 'Alina', username: 'alina', role: 'member'),
    ]);

    await _reveal(tester, find.text('Alina'));
    await tester.tap(find.text('Alina'));
    await _settle(tester);

    expect(find.text('Make Admin'), findsOneWidget);
    expect(find.text('Remove Admin'), findsNothing);
    expect(find.text('Remove from Group'), findsOneWidget);
  });

  testWidgets('no actions on your own row', (tester) async {
    final repo = _Repo();
    await _pumpInfo(tester, repo: repo);

    await _reveal(tester, find.text('Mira Joshi'));
    await tester.tap(find.text('Mira Joshi'));
    await _settle(tester);

    expect(find.byKey(const Key('action-sheet')), findsNothing);
    expect(find.bySemanticsLabel('Options for Mira Joshi'), findsNothing);
  });

  testWidgets('switch failure toasts and snaps back to the stream value',
      (tester) async {
    final repo = _Repo()..switchError = StateError('secret-switch');
    await _pumpInfo(tester, repo: repo, onlyAdmins: false);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await _reveal(tester, find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await _settle(tester);

    expect(find.text(_updateFailed), findsOneWidget);
    expect(find.textContaining('secret-switch'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('rename failure toasts the stable copy', (tester) async {
    final repo = _Repo()..renameError = StateError('secret-rename');
    await _pumpInfo(tester, repo: repo);

    await _reveal(tester, find.text('Weekend Trekkers'));
    await tester.tap(find.text('Weekend Trekkers'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'Renamed Crew');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect(find.text(_updateFailed), findsOneWidget);
    expect(find.textContaining('secret-rename'), findsNothing);
    expect(repo.renameCalls, 1);
  });

  testWidgets('photo failure toasts the stable copy', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (call) async => call.method == 'pickImage' ? '/tmp/group_icon.jpg' : null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        null,
      );
    });

    final repo = _Repo()..photoError = StateError('secret-photo');
    await _pumpInfo(tester, repo: repo);

    await _reveal(tester, find.bySemanticsLabel('Change group photo'));
    await tester.tap(find.bySemanticsLabel('Change group photo'));
    await _settle(tester);

    expect(find.text(_updateFailed), findsOneWidget);
    expect(find.textContaining('secret-photo'), findsNothing);
    expect(repo.photoCalls, 1);
  });

  testWidgets('leave failure toasts the stable copy', (tester) async {
    final repo = _Repo()..leaveError = StateError('secret-leave');
    await _pumpInfo(tester, repo: repo);

    await _reveal(tester, find.text('Leave Group'));
    await tester.tap(find.text('Leave Group'));
    await _settle(tester);
    await tester.tap(find.text('Leave'));
    await _settle(tester);

    expect(find.text(_updateFailed), findsOneWidget);
    expect(find.textContaining('secret-leave'), findsNothing);
    expect(repo.leaveCalls, 1);
  });

  testWidgets('cancel invite failure toasts the stable copy', (tester) async {
    final repo = _Repo(
      invites: [
        PendingGroupInvite(
          inviteId: 'inv-1',
          user: _member(id: 'u_d', name: 'Dee', username: 'dee'),
          status: 'pending',
        ),
      ],
    )..cancelError = StateError('secret-cancel');
    await _pumpInfo(tester, repo: repo);

    await _reveal(tester, find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await _settle(tester);

    expect(find.text(_updateFailed), findsOneWidget);
    expect(find.textContaining('secret-cancel'), findsNothing);
    expect(repo.cancelCalls, 1);
  });

  testWidgets('re-invite failure toasts the stable copy', (tester) async {
    final repo = _Repo(
      invites: [
        PendingGroupInvite(
          inviteId: 'inv-2',
          user: _member(id: 'u_d', name: 'Dee', username: 'dee'),
          status: 'declined',
        ),
      ],
    )..reInviteError = StateError('secret-reinvite');
    await _pumpInfo(tester, repo: repo);

    await _reveal(tester, find.text('Re-invite'));
    await tester.tap(find.text('Re-invite'));
    await _settle(tester);

    expect(find.text(_updateFailed), findsOneWidget);
    expect(find.textContaining('secret-reinvite'), findsNothing);
    expect(repo.reInviteCalls, 1);
  });

  testWidgets('re-invite success toasts "Invite sent"', (tester) async {
    final repo = _Repo(
      invites: [
        PendingGroupInvite(
          inviteId: 'inv-2',
          user: _member(id: 'u_d', name: 'Dee', username: 'dee'),
          status: 'declined',
        ),
      ],
    );
    await _pumpInfo(tester, repo: repo);

    await _reveal(tester, find.text('Re-invite'));
    await tester.tap(find.text('Re-invite'));
    await _settle(tester);

    expect(find.text('Invite sent'), findsOneWidget);
  });
}
