/// Create Group: R11/R7 load states, the empty state + CTA, the empty-name
/// RangeError floor, both back behaviours, the J3 typed-error copy, the
/// offline disabled Create, and no setState after dispose
/// (checklist test gate: `create_group_screen_test.dart`).
///
/// The group service is FAKE here — no real key generation, no PocketBase
/// calls, no Drift writes (the flow is stopped at the key pre-validation).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/app_button.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/friendship.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/chat/message_offline_policy.dart';
import 'package:kuch_bhi/features/groups/screens/create_group_screen.dart';
import 'package:kuch_bhi/features/home/providers/friends_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/services/group_create_service.dart';
import 'package:pocketbase/pocketbase.dart';

const _genericFailure =
    "Couldn't create the group. Check your connection and try again.";
const _keyMissing =
    "can't be added yet. They need to open Kuch Bhi once to set up encryption.";

User _user({required String id, required String name, String username = ''}) =>
    User(
      id: id,
      displayName: name,
      username: username,
      email: '$id@example.com',
      friendCode: 'CODE01',
      createdAt: DateTime(2026, 1, 1),
    );

Friendship _friend(User friend) => Friendship(
      id: 'f_${friend.id}',
      friend: friend,
      createdAt: DateTime(2026, 1, 1),
    );

Friendship _alina() =>
    _friend(_user(id: 'u_a', name: 'Alina', username: 'alina'));

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

// ── auth fixture ──────────────────────────────────────────────────────

class _Auth extends AuthNotifier {
  _Auth(this.state_);

  final AuthState state_;

  @override
  Future<AuthState> build() async => state_;
}

// ── group service fixture (no PB, no key generation) ──────────────────

class _FakeGroupService extends GroupCreateService {
  _FakeGroupService({Map<String, String> keys = const {}})
      : _keys = keys,
        super(PocketBaseClient.forTest(PocketBase('http://localhost')));

  /// memberId → public key. An absent or empty value is the missing-key
  /// case that makes `_createGroup` throw `MemberKeyMissingError`.
  final Map<String, String> _keys;

  /// Set to hold the create flow right after `_creating` turns true.
  Completer<void>? gate;

  @override
  Future<RecordModel> getUserRecord(String userId) async {
    if (gate != null) await gate!.future;
    return RecordModel({'id': userId, 'public_key': _keys[userId] ?? ''});
  }
}

final _me = _user(id: 'u_me', name: 'Mira Joshi', username: 'mira');

Widget _host({
  required FriendshipsNotifier Function() friendships,
  bool online = true,
  AuthState auth = const AuthUnauthenticated(),
  _FakeGroupService? service,
  bool launch = false,
}) {
  return ProviderScope(
    overrides: [
      friendshipsProvider.overrideWith(friendships),
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
      authProvider.overrideWith(() => _Auth(auth)),
      appDatabaseProvider.overrideWithValue(AppDatabase.test()),
      pocketbaseClientProvider
          .overrideWithValue(PocketBaseClient.forTest(PocketBase('http://localhost'))),
      groupCreateServiceProvider
          .overrideWithValue(service ?? _FakeGroupService()),
    ],
    child: MaterialApp(
      theme: warmPopLight(),
      home: launch
          ? Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CreateGroupScreen(),
                    ),
                  ),
                  child: const Text('open-create'),
                ),
              ),
            )
          : const CreateGroupScreen(),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  // Resolve the session first: nothing watches `authProvider`, so without
  // this the very first read inside `_createGroup` would still be loading
  // and the screen would take the "not authenticated" branch.
  final scope = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  await scope.read(authProvider.future);
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

/// The screen's own PopScope (a raw `find.byType(PopScope)` misses it:
/// the modal route installs `PopScope<Object?>` too).
Finder _popScope(WidgetTester tester) => find.descendant(
      of: find.byType(CreateGroupScreen),
      matching: find.byWidgetPredicate((w) => w is PopScope),
    );

bool _canPop(WidgetTester tester) =>
    tester.widget<PopScope>(_popScope(tester)).canPop;

/// Step 1 → select [name] → Next → type the group name → Create.
Future<void> _toStep2(WidgetTester tester, {required String name}) async {
  await tester.tap(find.text(name));
  await tester.pump();
  await tester.tap(find.text('Next'));
  await _settle(tester);
  expect(find.text('Create Group'), findsOneWidget);
  await tester.enterText(find.byType(TextField), 'Trek Crew');
  await tester.pump();
  expect(find.text('Trek Crew'), findsOneWidget, reason: 'name field took text');
}

void main() {
  testWidgets('step 1 loading renders the R11 rows with the New Group bar',
      (tester) async {
    await tester.pumpWidget(_host(friendships: _LoadingFriendships.new));
    await _settle(tester);

    expect(find.text('New Group'), findsOneWidget);
    expect(find.byType(Skeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('friends error shows R7 copy + Retry and never the exception',
      (tester) async {
    await tester.pumpWidget(_host(friendships: _ErrorFriendships.new));
    await _settle(tester);

    expect(find.text("Couldn't load friends."), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('boom'), findsNothing);
    expect(find.text('New Group'), findsOneWidget);
  });

  testWidgets('empty friends shows R7 empty + the Add a Friend CTA',
      (tester) async {
    await tester.pumpWidget(
      _host(friendships: () => _DataFriendships(const [])),
    );
    await _settle(tester);

    expect(find.text('No friends yet'), findsOneWidget);
    expect(find.text('Add a friend to start a group.'), findsOneWidget);
    expect(find.text('Add a Friend'), findsOneWidget);
  });

  testWidgets('an empty display name never RangeErrors in the list or chip',
      (tester) async {
    await tester.pumpWidget(
      _host(
        friendships: () => _DataFriendships([
          _friend(_user(id: 'u_blank', name: '   ')),
        ]),
      ),
    );
    await _settle(tester);

    // List row + avatar initials fall back instead of taking [0] of ''.
    expect(find.text('Unknown'), findsOneWidget);

    await tester.tap(find.text('Unknown'));
    await _settle(tester);

    // The chip renders the same fallback; no RangeError was thrown.
    expect(find.text('Unknown'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'system back on step 2 returns to step 1 with the selection kept',
      (tester) async {
    await tester.pumpWidget(
      _host(friendships: () => _DataFriendships([_alina()])),
    );
    await _settle(tester);

    await tester.tap(find.text('Alina'));
    await tester.pump();
    expect(find.text('Alina'), findsNWidgets(2)); // row + selected chip

    await tester.tap(find.text('Next'));
    await _settle(tester);
    expect(find.text('Create Group'), findsOneWidget);
    expect(find.text('Alina'), findsNothing); // step 2 has no list
    // Step 2 holds the system back (canPop false) and handles it itself.
    expect(_canPop(tester), isFalse);

    await tester.binding.handlePopRoute();
    await _settle(tester);

    expect(find.text('Create Group'), findsNothing);
    expect(find.text('Next'), findsOneWidget);
    // Row + chip = 2 → the selection survived the step change.
    expect(find.text('Alina'), findsNWidgets(2));
    expect(_canPop(tester), isTrue);
  });

  testWidgets('back is blocked while creating (PopScope, bar, field)',
      (tester) async {
    final service = _FakeGroupService(keys: {'u_me': 'pk-me'})
      ..gate = Completer<void>();
    await tester.pumpWidget(
      _host(
        friendships: () => _DataFriendships([_alina()]),
        auth: AuthAuthenticated(_me),
        service: service,
      ),
    );
    await _settle(tester);

    await _toStep2(tester, name: 'Alina');
    await tester.tap(find.widgetWithText(AppButton, 'Create Group'));
    await _settle(tester);

    // R3's busy slot replaces the 'Creating…' label with the 18px spinner,
    // so the busy state is asserted through the button itself.
    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.busy, isTrue, reason: 'Create shows its busy state');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_canPop(tester), isFalse);
    expect(
      tester.widget<TextField>(find.byType(TextField)).readOnly,
      isTrue,
    );
    final back = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.arrow_back),
        matching: find.byType(IconButton),
      ),
    );
    expect(back.onPressed, isNull);

    // System back is swallowed while the flow is in flight.
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.text('Group name'), findsOneWidget, reason: 'still step 2');
    expect(find.text('Next'), findsNothing);
    expect(
      tester.widget<AppButton>(find.byType(AppButton)).busy,
      isTrue,
    );

    // Release so the test does not end mid-flight.
    service.gate!.complete();
    await _settle(tester);
  });

  testWidgets('MemberKeyMissingError names the FRIEND, never the id',
      (tester) async {
    final service = _FakeGroupService(keys: {'u_me': 'pk-me'});
    await tester.pumpWidget(
      _host(
        friendships: () => _DataFriendships([_alina()]),
        auth: AuthAuthenticated(_me),
        service: service,
      ),
    );
    await _settle(tester);

    await _toStep2(tester, name: 'Alina');
    await tester.tap(find.widgetWithText(AppButton, 'Create Group'));
    await _settle(tester);

    expect(find.text('Alina $_keyMissing'), findsOneWidget);
    expect(find.textContaining('u_a'), findsNothing);
    expect(find.textContaining('u_me'), findsNothing);
    expect(find.textContaining('boom'), findsNothing);
    // The flow stopped before any server write: back on step 1's flow.
    expect(find.text('Creating…'), findsNothing);
  });

  testWidgets('any other failure shows the stable connection copy',
      (tester) async {
    // Signed out → `_createGroup` throws before touching the service.
    await tester.pumpWidget(
      _host(friendships: () => _DataFriendships([_alina()])),
    );
    await _settle(tester);

    await _toStep2(tester, name: 'Alina');
    await tester.tap(find.widgetWithText(AppButton, 'Create Group'));
    await _settle(tester);

    expect(find.text(_genericFailure), findsOneWidget);
    expect(find.textContaining('Not authenticated'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('offline: Create is disabled and the single hint shows',
      (tester) async {
    await tester.pumpWidget(
      _host(
        friendships: () => _DataFriendships([_alina()]),
        online: false,
      ),
    );
    await _settle(tester);

    expect(
      find.text("You're offline — actions are available when you're back."),
      findsOneWidget,
    );
    // Step 1 stays usable offline.
    await _toStep2(tester, name: 'Alina');

    final button =
        tester.widget<AppButton>(find.widgetWithText(AppButton, 'Create Group'));
    expect(button.onPressed, isNull);
    expect(find.text(kOfflineActionHint), findsOneWidget);
    // Exactly ONE dim on the surface, not nested ones.
    final opacities = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .where((o) => o.opacity == .38)
        .length;
    expect(opacities, 1);
  });

  testWidgets('no setState after dispose: the image picker resolves late',
      (tester) async {
    final gate = Completer<String?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/image_picker'),
      (call) => call.method == 'pickImage' ? gate.future : null,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        null,
      );
    });

    await tester.pumpWidget(
      _host(
        friendships: () => _DataFriendships([_alina()]),
        launch: true,
      ),
    );
    await _settle(tester);
    await tester.tap(find.text('open-create'));
    await _settle(tester);
    expect(find.text('New Group'), findsOneWidget);

    // Step 2 owns the photo target; leave the flow while the picker is open.
    await tester.tap(find.text('Alina'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await _settle(tester);
    await tester.tap(find.bySemanticsLabel('Add group photo'));
    await tester.pump();

    await tester.binding.handlePopRoute(); // step 2 → step 1
    await _settle(tester);
    expect(find.text('Next'), findsOneWidget,
        reason: 'first back must land on step 1');
    await tester.binding.handlePopRoute(); // step 1 → popped
    await _settle(tester);
    // The reverse transition out of the pushed route needs a little more
    // than one settle before the screen leaves the tree.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('New Group'), findsNothing);

    gate.complete('/tmp/late.jpg');
    await _settle(tester);

    expect(tester.takeException(), isNull);
  });
}
