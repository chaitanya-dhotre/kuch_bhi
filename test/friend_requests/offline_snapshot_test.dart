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
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/friend_requests/providers/friend_request_provider.dart';
import 'package:kuch_bhi/infrastructure/repositories/friend_repository_impl.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:pocketbase/pocketbase.dart';

/// H3: "Open-while-offline with stale local cache renders last-good list when
/// available; error state only when nothing to show."
///
/// The page's two sources are network-first with a local-snapshot fallback:
/// a failed fetch renders the last-good snapshot; when there is no snapshot
/// either, the error propagates (the page then shows the B3 error state).
User _user({String name = 'Mira Joshi', String username = 'mira_j'}) => User(
  id: username,
  displayName: name,
  username: username,
  email: '$username@example.com',
  friendCode: 'ABC123',
  createdAt: DateTime(2026, 10, 20),
);

FriendRequest _request() => FriendRequest(
  id: 'request-1',
  fromUser: _user(),
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

class _FailingFriendRepo implements FriendRepository {
  Object error = StateError('offline');

  @override
  Future<List<FriendRequest>> getIncomingRequests() async => throw error;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _FailingMessageRepo implements MessageRepository {
  Object error = StateError('offline');

  @override
  Future<List<GroupInvite>> getIncomingGroupInvites() async => throw error;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _OkFriendRepo implements FriendRepository {
  List<FriendRequest> rows = [_request()];
  final List<String> declined = [];

  @override
  Future<List<FriendRequest>> getIncomingRequests() async => rows;

  @override
  Future<void> declineRequest(String requestId) async {
    declined.add(requestId);
  }

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
  // The reconnect watcher reads the connectivity signal, which needs a
  // platform binding (the test binding satisfies it).
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.test();
    await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'me');
  });

  tearDown(() async {
    await db.close();
  });

  test('a failed fetch renders the last-good snapshot (cold start offline)',
      () async {
    // 1. Online: the successful fetch writes the snapshot.
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        friendRepositoryProvider.overrideWithValue(_OkFriendRepo()),
        messageRepositoryProvider.overrideWithValue(_OkMessageRepo()),
        pocketbaseClientProvider.overrideWithValue(_offlineClient()),
      ],
    );
    addTearDown(container.dispose);

    final online = await container.read(incomingRequestsProvider.future);
    expect(online.length, 1);
    expect(online.first.fromUser.displayName, 'Mira Joshi');

    final invites = await container.read(incomingGroupInvitesProvider.future);
    expect(invites.length, 1);
    expect(invites.first.conversationName, 'Weekend Trekkers');

    // 2. Cold start offline: a FRESH container (no in-memory state) whose
    //    fetch fails must still render the snapshot.
    final offlineContainer = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        friendRepositoryProvider.overrideWithValue(_FailingFriendRepo()),
        messageRepositoryProvider.overrideWithValue(_FailingMessageRepo()),
        pocketbaseClientProvider.overrideWithValue(_offlineClient()),
      ],
    );
    addTearDown(offlineContainer.dispose);

    final cached = await offlineContainer.read(incomingRequestsProvider.future);
    expect(cached.length, 1);
    expect(cached.first.fromUser.displayName, 'Mira Joshi');
    expect(cached.first.fromUser.username, 'mira_j');

    final cachedInvites =
        await offlineContainer.read(incomingGroupInvitesProvider.future);
    expect(cachedInvites.length, 1);
    expect(cachedInvites.first.conversationName, 'Weekend Trekkers');
    expect(cachedInvites.first.invitedBy.displayName, 'Rohan');
  });

  test('with no snapshot the failure propagates so the page shows the error',
      () async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        friendRepositoryProvider.overrideWithValue(_FailingFriendRepo()),
        messageRepositoryProvider.overrideWithValue(_FailingMessageRepo()),
        pocketbaseClientProvider.overrideWithValue(_offlineClient()),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(incomingRequestsProvider.future),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      container.read(incomingGroupInvitesProvider.future),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'an empty last-good list renders the EMPTY state offline, not an error',
    () async {
      // A user with genuinely zero pending requests, opening the app
      // offline, must see "No pending requests" — not "Couldn't load
      // requests." An empty snapshot means "you have nothing pending";
      // only an ABSENT snapshot means "we could not determine".
      final emptyRepo = _OkFriendRepo()..rows = const [];
      final online = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          friendRepositoryProvider.overrideWithValue(emptyRepo),
          messageRepositoryProvider.overrideWithValue(_OkMessageRepo()..rows = const []),
          pocketbaseClientProvider.overrideWithValue(_offlineClient()),
        ],
      );
      addTearDown(online.dispose);

      await online.read(incomingRequestsProvider.future);
      await online.read(incomingGroupInvitesProvider.future);

      final offlineContainer = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          friendRepositoryProvider.overrideWithValue(_FailingFriendRepo()),
          messageRepositoryProvider.overrideWithValue(_FailingMessageRepo()),
          pocketbaseClientProvider.overrideWithValue(_offlineClient()),
        ],
      );
      addTearDown(offlineContainer.dispose);

      // An EMPTY snapshot is something to show — it settles, it does not throw.
      final rows = await offlineContainer.read(incomingRequestsProvider.future);
      expect(rows, isEmpty);

      final invites =
          await offlineContainer.read(incomingGroupInvitesProvider.future);
      expect(invites, isEmpty);
    },
  );

  test('a handled row never comes back from the snapshot', () async {
    // The server handled the row (declined), then the network dropped. The
    // snapshot must NOT resurrect it — the card would reappear and be
    // re-actionable.
    final repo = _OkFriendRepo();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        friendRepositoryProvider.overrideWithValue(repo),
        messageRepositoryProvider.overrideWithValue(_OkMessageRepo()),
        pocketbaseClientProvider.overrideWithValue(_offlineClient()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(incomingRequestsProvider.future);

    // The user declines while the network is about to drop.
    await container.read(incomingRequestsProvider.notifier).decline('request-1');

    final offlineContainer = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        friendRepositoryProvider.overrideWithValue(_FailingFriendRepo()),
        messageRepositoryProvider.overrideWithValue(_FailingMessageRepo()),
        pocketbaseClientProvider.overrideWithValue(_offlineClient()),
      ],
    );
    addTearDown(offlineContainer.dispose);

    // Offline: the declined row must be gone, so the snapshot is empty —
    // and an empty snapshot renders the empty state, not the declined card.
    final cached = await offlineContainer.read(incomingRequestsProvider.future);
    expect(cached, isEmpty);
  });

  test(
    'a new session never renders the previous user\'s rows (H3-3)',
    () async {
      // The request providers are not auto-disposed, so their in-memory state
      // survives a sign-out. A second user signing in on the same process
      // must NOT keep reading the FIRST user's rows out of that state.
      //
      // The fake repo answers per session (it reads the same
      // currentUserId the app uses), so a rebuild yields the NEW user's rows
      // and a stale in-memory value yields the OLD user's rows.
      final session = _AuthSession();
      final repo = _SessionAwareFriendRepo(db);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authProvider.overrideWith(() => _ControllableAuthNotifier(session)),
          friendRepositoryProvider.overrideWithValue(repo),
          messageRepositoryProvider.overrideWithValue(_OkMessageRepo()),
          pocketbaseClientProvider.overrideWithValue(_offlineClient()),
        ],
      );
      addTearDown(container.dispose);

      // Session A.
      await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'alice');
      session.user = _user(name: 'Alice', username: 'alice');
      await container.read(authProvider.future);
      final aliceRows = await container.read(incomingRequestsProvider.future);
      expect(aliceRows.single.fromUser.username, 'alice');

      // Sign out: the DB is wiped (mirrors AuthRepositoryImpl.signOut), so
      // currentUserId disappears and the session scope must rebuild.
      for (final table in db.allTables) {
        await db.delete(table).go();
      }
      session.user = null;
      container.invalidate(authProvider);
      await container.pump();

      // Session B — the provider must rebuild under the new session.
      await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'bob');
      session.user = _user(name: 'Bob', username: 'bob');
      container.invalidate(authProvider);
      await container.pump();
      await container.read(authProvider.future);
      await container.pump();

      final bobRows = await container.read(incomingRequestsProvider.future);
      expect(
        bobRows.single.fromUser.username,
        'bob',
        reason: 'user B must never see user A\'s request rows',
      );
    },
  );

  test(
    'a new session with a FAILING fetch never renders the previous user\'s rows',
    () async {
      // The dangerous variant of H3-3: user B's fetch FAILS. Riverpod's
      // `copyWithPrevious` retains the previous value inside the new
      // AsyncError, so without dropping the old state the screen would
      // render user A's rows to user B.
      final session = _AuthSession();
      final repo = _SessionAwareFriendRepo(db);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authProvider.overrideWith(() => _ControllableAuthNotifier(session)),
          friendRepositoryProvider.overrideWithValue(repo),
          messageRepositoryProvider.overrideWithValue(_FailingMessageRepo()),
          pocketbaseClientProvider.overrideWithValue(_offlineClient()),
        ],
      );
      addTearDown(container.dispose);

      // Session A.
      await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'alice');
      session.user = _user(name: 'Alice', username: 'alice');
      await container.read(authProvider.future);
      final aliceRows = await container.read(incomingRequestsProvider.future);
      expect(aliceRows.single.fromUser.username, 'alice');

      // Sign out (the DB is wiped, mirroring AuthRepositoryImpl.signOut).
      for (final table in db.allTables) {
        await db.delete(table).go();
      }
      session.user = null;
      container.invalidate(authProvider);
      await container.pump();

      // Session B — and B's fetch FAILS.
      await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'bob');
      session.user = _user(name: 'Bob', username: 'bob');
      container.invalidate(authProvider);
      await container.pump();
      await container.read(authProvider.future);
      await container.pump();

      repo.failNextFetch = true;
      Object? error;
      List<FriendRequest>? rows;
      try {
        rows = await container.read(incomingRequestsProvider.future);
      } catch (e) {
        error = e;
      }

      // Whatever the outcome, user A's rows must not be present.
      final rendered = rows ?? [];
      for (final row in rendered) {
        expect(
          row.fromUser.username,
          isNot('alice'),
          reason: 'user B must never see user A\'s request rows',
        );
      }
      expect(
        rows?.any((r) => r.fromUser.username == 'alice') ?? false,
        isFalse,
      );
      // The provider must not be holding a stale value alongside the error.
      expect(
        container.read(incomingRequestsProvider).valueOrNull
                ?.any((r) => r.fromUser.username == 'alice') ??
            false,
        isFalse,
        reason: 'the retained previous value must be dropped on a session '
            'change (error: ${error ?? 'none'})',
      );
    },
  );

  test('the snapshot never carries a handled (accepted/declined) row',
      () async {
    final repo = _OkFriendRepo()
      ..rows = [
        _request(),
        FriendRequest(
          id: 'request-2',
          fromUser: _user(name: 'Old', username: 'old'),
          toUser: _user(name: 'Me', username: 'me'),
          status: 'accepted',
          createdAt: DateTime(2026, 10, 19),
        ),
      ];
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        friendRepositoryProvider.overrideWithValue(repo),
        messageRepositoryProvider.overrideWithValue(_OkMessageRepo()),
        pocketbaseClientProvider.overrideWithValue(_offlineClient()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(incomingRequestsProvider.future);

    final offlineContainer = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        friendRepositoryProvider.overrideWithValue(_FailingFriendRepo()),
        messageRepositoryProvider.overrideWithValue(_FailingMessageRepo()),
        pocketbaseClientProvider.overrideWithValue(_offlineClient()),
      ],
    );
    addTearDown(offlineContainer.dispose);

    final cached = await offlineContainer.read(incomingRequestsProvider.future);
    expect(cached.length, 1);
    expect(cached.first.id, 'request-1');
  });
}

/// A PocketBase client whose realtime handshake can never succeed — the
/// stand-in for "the device has no network at cold start". Pointed at the
/// closed local port so the SSE connect is refused immediately.
PocketBaseClient _offlineClient() =>
    PocketBaseClient.forTest(PocketBase('http://127.0.0.1:1'));

/// An auth provider whose session user the test controls.
///
/// The session user lives OUTSIDE the notifier (a plain holder) so a fresh
/// notifier instance is built for every auth transition — riverpod requires
/// a new instance per build, and this lets the test drive the transition.
class _AuthSession {
  User? user;
}

class _ControllableAuthNotifier extends AuthNotifier {
  _ControllableAuthNotifier(this.session);

  final _AuthSession session;

  @override
  Future<AuthState> build() async {
    final user = session.user;
    return user == null ? const AuthUnauthenticated() : AuthAuthenticated(user);
  }
}

/// A friend repo that answers per session, the way the server does — it
/// returns the rows belonging to the CURRENT user id.
class _SessionAwareFriendRepo implements FriendRepository {
  _SessionAwareFriendRepo(this.db);

  final AppDatabase db;

  /// When set, the next fetch fails — the case where riverpod would
  /// otherwise retain the previous value inside the new error state.
  bool failNextFetch = false;

  @override
  Future<List<FriendRequest>> getIncomingRequests() async {
    if (failNextFetch) {
      failNextFetch = false;
      throw StateError('offline');
    }
    final userId = await db.settingsDao.getSetting(
      AppSettingsKeys.currentUserId,
    );
    if (userId == null || userId.isEmpty) return const [];
    return [
      FriendRequest(
        id: '$userId-request',
        fromUser: _user(name: userId, username: userId),
        toUser: _user(name: 'Me', username: 'me'),
        status: 'pending',
        createdAt: DateTime(2026, 10, 20),
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}
