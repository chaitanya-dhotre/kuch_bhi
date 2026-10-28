import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';
import 'package:kuch_bhi/domain/entities/friend_request.dart';
import 'package:kuch_bhi/domain/entities/group_invite.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/friend_repository.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/friend_requests/providers/friend_request_provider.dart';
import 'package:kuch_bhi/infrastructure/repositories/friend_repository_impl.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:pocketbase/pocketbase.dart';

/// Fencing an in-flight realtime refresh against an accept/decline (H3-1),
/// and preferring the live list over the snapshot when a refresh fails.
///
/// A realtime `_refresh()` and a card action race: the refresh's payload was
/// captured on the server BEFORE the user declined, so publishing it would
/// resurrect the handled row on screen. `_refresh` fences on the action
/// generation and discards such a payload; the action's own rebuild
/// refetches the truthful list.
FriendRequest _request({String id = 'request-1', String name = 'Mira Joshi'}) =>
    FriendRequest(
      id: id,
      fromUser: _user(name: name),
      toUser: _user(name: 'Me', username: 'me'),
      status: 'pending',
      createdAt: DateTime(2026, 10, 20),
    );

GroupInvite _invite() => GroupInvite(
      id: 'invite-1',
      conversationId: 'conversation-1',
      conversationName: 'Weekend Trekkers',
      invitedBy: _user(name: 'Rohan', username: 'rohan'),
      status: 'pending',
      createdAt: DateTime(2026, 10, 19),
    );

User _user({String name = 'Mira Joshi', String username = 'mira_j'}) => User(
      id: username,
      displayName: name,
      username: username,
      email: '$username@example.com',
      friendCode: 'ABC123',
      createdAt: DateTime(2026, 10, 20),
    );

class _GatedFriendRepo implements FriendRepository {
  _GatedFriendRepo(this.rows);

  List<FriendRequest> rows;

  /// Held open until the test releases it — the in-flight refresh.
  final Completer<void> gate = Completer<void>();

  int calls = 0;

  @override
  Future<List<FriendRequest>> getIncomingRequests() async {
    calls++;
    // The payload the SERVER produces for this request — captured now, so
    // the in-flight refresh keeps the row the user is about to decline.
    final payload = List<FriendRequest>.of(rows);
    if (calls == 2) {
      // The SECOND fetch is the realtime refresh, and ONLY it is held open:
      // the decline's own rebuild (call 3) runs normally and returns the
      // now-shorter server list, exactly as the real server would.
      await gate.future;
    }
    return payload;
  }

  @override
  Future<void> declineRequest(String requestId) async {
    rows = rows.where((r) => r.id != requestId).toList();
    gate.complete();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _FailingFriendRepo implements FriendRepository {
  Object error = StateError('offline');

  @override
  Future<List<FriendRequest>> getIncomingRequests() async => throw error;

  @override
  Future<void> declineRequest(String requestId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// A repository whose calls NEVER complete — the "wifi up, no internet"
/// blackhole. Used to prove the actions are bounded.
class _BlackholedFriendRepo implements FriendRepository {
  static const _never = Duration(days: 1);

  @override
  Future<List<FriendRequest>> getIncomingRequests() =>
      Future<List<FriendRequest>>.delayed(_never, () => []);

  @override
  Future<void> declineRequest(String requestId) =>
      Future<void>.delayed(_never, () {});

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _OkMessageRepo implements MessageRepository {
  List<GroupInvite> rows = [_invite()];

  @override
  Future<List<GroupInvite>> getIncomingGroupInvites() async => rows;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.test();
    await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'me');
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'a stale in-flight refresh cannot resurrect a DECLINED row (H3-1)',
    () async {
      final repo = _GatedFriendRepo([_request()]);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          friendRepositoryProvider.overrideWithValue(repo),
          messageRepositoryProvider.overrideWithValue(_OkMessageRepo()),
          pocketbaseClientProvider.overrideWithValue(_offlineClient()),
        ],
      );
      addTearDown(container.dispose);

      // Record only publishes made AFTER the decline. The bug is transient
      // — the action's own rebuild settles on the truthful list shortly
      // after — so reading the final state alone would miss the resurrection
      // flash the stale refresh publishes.
      final published = <List<String>>[];
      var declined = false;
      container.listen(incomingRequestsProvider, (_, next) {
        if (!declined) return;
        // Only a settled DATA publish counts. `AsyncLoading` keeps the
        // previous value (that is what F2 renders during a refresh), so it
        // must not be mistaken for the stale publish being tested.
        if (next is! AsyncData || next.isLoading) return;
        published.add(next.valueOrNull?.map((r) => r.id).toList() ?? const []);
      });

      await expectLater(
        container.read(incomingRequestsProvider.future),
        completion(isNotEmpty),
      );

      // The realtime refresh starts while the fetch is still held open.
      unawaited(
        container.read(incomingRequestsProvider.notifier).refreshForTest(),
      );
      await pumpEventQueue();

      declined = true;
      await container.read(incomingRequestsProvider.notifier).decline(
            'request-1',
          );
      await container.read(incomingRequestsProvider.future);
      await pumpEventQueue();

      // The stale refresh resolves AFTER the decline and must never publish
      // the row again — not even for one frame the user could see.
      expect(
        published,
        isNot(anyElement(contains('request-1'))),
        reason: 'a payload fetched before the decline must not republish the row',
      );

      final live = container.read(incomingRequestsProvider).valueOrNull;
      expect(
        live?.map((r) => r.id),
        isNot(contains('request-1')),
        reason: 'the declined row must stay gone from the live list',
      );

      // Nor may it be snapshotted, or the next cold start (which renders the
      // snapshot offline) resurrects it all over again.
      final snapshot =
          await container.read(requestSnapshotCacheProvider).readRequests('me');
      expect(
        snapshot?.map((r) => r.id),
        isNot(contains('request-1')),
        reason: 'the stale payload must not overwrite the snapshot',
      );
    },
  );

  test(
    'a FAILED refresh keeps the live list, it does not shrink to the snapshot',
    () async {
      // Live: 2 rows (one just arrived via a successful rebuild). The
      // snapshot write failed, so the snapshot holds only the older 1. A
      // failed refresh must not make the newer row vanish.
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          friendRepositoryProvider.overrideWithValue(_FailingFriendRepo()),
          messageRepositoryProvider.overrideWithValue(_OkMessageRepo()),
          pocketbaseClientProvider.overrideWithValue(_offlineClient()),
        ],
      );
      addTearDown(container.dispose);

      // Seed a snapshot of ONE row, then put TWO rows in live state.
      await container
          .read(requestSnapshotCacheProvider)
          .writeRequests('me', [_request()]);
      container.read(incomingRequestsProvider.notifier).state = AsyncData([
        _request(),
        _request(id: 'request-2', name: 'Dev Patel'),
      ]);

      await container.read(incomingRequestsProvider.notifier).refreshForTest();
      await pumpEventQueue();

      final live = container.read(incomingRequestsProvider).valueOrNull;
      expect(live!.map((r) => r.id), ['request-1', 'request-2']);
    },
  );

  test(
    'a BLACKHOLED accept/decline releases the card instead of locking it forever',
    () async {
      // PocketBase's HTTP client has no request timeout, so a blackholed
      // socket ("wifi up, no internet") never completes an accept/decline.
      // The card's busy lock is only released in the handler's finally, so an
      // unbounded call left the card dead until the app restarted.
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          friendRepositoryProvider.overrideWithValue(_BlackholedFriendRepo()),
          messageRepositoryProvider.overrideWithValue(_OkMessageRepo()),
          pocketbaseClientProvider.overrideWithValue(_offlineClient()),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(incomingRequestsProvider.future),
        throwsA(isA<TimeoutException>()),
        reason: 'the row count never arrives, so the source must settle',
      );

      // The action itself must reject (not hang) so the caller's catch shows
      // the failure toast and unlocks the card.
      await expectLater(
        container.read(incomingRequestsProvider.notifier).decline('request-1'),
        throwsA(isA<TimeoutException>()),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

/// A PocketBase client whose realtime handshake can never succeed — the
/// stand-in for "the device has no network at cold start".
PocketBaseClient _offlineClient() =>
    PocketBaseClient.forTest(PocketBase('http://127.0.0.1:1'));
