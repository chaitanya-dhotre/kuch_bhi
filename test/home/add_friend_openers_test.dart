import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/friend_request.dart';
import 'package:kuch_bhi/domain/entities/friendship.dart';
import 'package:kuch_bhi/domain/entities/group_invite.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/friend_repository.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/friend_requests/providers/friend_request_provider.dart';
import 'package:kuch_bhi/features/friend_requests/screens/friend_requests_screen.dart';
import 'package:kuch_bhi/features/groups/screens/create_group_screen.dart';
import 'package:kuch_bhi/features/home/providers/friends_provider.dart';
import 'package:kuch_bhi/features/home/screens/add_friend_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/friend_repository_impl.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/sheet_harness.dart';

const _stale = 'No user found.';

class _NoUser implements FriendRepository {
  @override
  Future<User?> findUserByCode(String code) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _NoRequests extends IncomingRequestsNotifier {
  @override
  Future<List<FriendRequest>> build() async => const [];
}

class _NoInvites extends IncomingGroupInvitesNotifier {
  @override
  Future<List<GroupInvite>> build() async => const [];
}

class _NoFriends extends FriendshipsNotifier {
  @override
  Future<List<Friendship>> build() async => const [];
}

class _SignedOut extends AuthNotifier {
  @override
  Future<AuthState> build() async => const AuthUnauthenticated();
}

final _common = <Override>[
  friendRepositoryProvider.overrideWithValue(_NoUser()),
  isOnlineProvider.overrideWith((ref) => Stream.value(true)),
  currentUserIdProvider.overrideWith((ref) async => 'u_me'),
  friendshipsProvider.overrideWith(_NoFriends.new),
];

/// Leaves a stale error in the notifier, then taps the empty-state button.
Future<void> _staleThenOpen(WidgetTester tester) async {
  final container =
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  await container.read(addFriendProvider.notifier).searchByCode('ZZZZ99');
  expect(container.read(addFriendProvider).searchError, _stale);

  await tester.tap(find.text('Add a Friend'));
  // The empty-state mascot breathes forever: pump past the sheet's slide.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(AddFriendSheet), findsOneWidget);
  expect(find.text('Add a friend'), findsOneWidget, reason: 'sheet title');
  expect(find.text(_stale), findsNothing, reason: 'opened from a reset state');
  expect(container.read(addFriendProvider).searchError, isNull);
}

void main() {
  testWidgets('Requests empty state opens a fresh Add a friend sheet',
      (tester) async {
    await pumpHost(tester, const FriendRequestsScreen(), overrides: [
      ..._common,
      incomingRequestsProvider.overrideWith(_NoRequests.new),
      incomingGroupInvitesProvider.overrideWith(_NoInvites.new),
    ]);
    await tester.pump();
    await _staleThenOpen(tester);
  });

  testWidgets('Create Group empty state opens a fresh Add a friend sheet',
      (tester) async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    await pumpHost(tester, const CreateGroupScreen(), overrides: [
      ..._common,
      authProvider.overrideWith(_SignedOut.new),
      appDatabaseProvider.overrideWithValue(db),
      pocketbaseClientProvider.overrideWithValue(
          PocketBaseClient.forTest(PocketBase('http://localhost'))),
    ]);
    await tester.pump();
    await tester.pump();
    await _staleThenOpen(tester);
  });
}
