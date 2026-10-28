import 'dart:async';
import 'dart:io';

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

/// R3-S3: PocketBase's HTTP client has NO request timeout.
///
/// A blackholed socket — the "wifi up but no internet" / captive-portal
/// case — accepts the TCP connection and then never answers. A fetch against
/// it never completes, so the page would sit on its skeleton FOREVER even
/// with a perfectly good snapshot on disk.
///
/// The fix bounds the fetch, so a blackholed network degrades to the offline
/// path: the snapshot renders (H3), or — with no snapshot — the error state.
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
    'a fetch that never completes still settles (bounded by the fetch timeout)',
    () async {
      // A socket that accepts the connection and then goes silent — the
      // blackhole. The fetch hangs; the page must not.
      final blackhole = await _BlackholeServer.start();
      addTearDown(blackhole.close);

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          friendRepositoryProvider.overrideWithValue(_BlackholeFriendRepo()),
          messageRepositoryProvider.overrideWithValue(_BlackholeMessageRepo()),
          pocketbaseClientProvider.overrideWithValue(
            PocketBaseClient.forTest(PocketBase(blackhole.url)),
          ),
        ],
      );
      addTearDown(container.dispose);

      final stopwatch = Stopwatch()..start();
      // The provider must SETTLE — data or error, never hang.
      Object? error;
      List<FriendRequest>? rows;
      try {
        rows = await container.read(incomingRequestsProvider.future);
      } catch (e) {
        error = e;
      }
      stopwatch.stop();

      expect(
        rows ?? error,
        isNotNull,
        reason: 'the provider must settle rather than hang forever',
      );
      expect(
        stopwatch.elapsed.inSeconds,
        lessThan(30),
        reason: 'the fetch must be bounded — it settled in '
            '${stopwatch.elapsed.inMilliseconds}ms',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('with a snapshot, a blackholed fetch still renders the snapshot',
      () async {
    // First: a successful fetch writes the snapshot.
    final online = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        friendRepositoryProvider.overrideWithValue(_OkFriendRepo()),
        messageRepositoryProvider.overrideWithValue(_OkMessageRepo()),
        pocketbaseClientProvider.overrideWithValue(_offlineClient()),
      ],
    );
    addTearDown(online.dispose);
    await online.read(incomingRequestsProvider.future);

    // Then: the network blackholes and the fetch hangs. The page must fall
    // back to the snapshot rather than staying on the skeleton.
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        friendRepositoryProvider.overrideWithValue(_BlackholeFriendRepo()),
        messageRepositoryProvider.overrideWithValue(_BlackholeMessageRepo()),
        pocketbaseClientProvider.overrideWithValue(_offlineClient()),
      ],
    );
    addTearDown(container.dispose);

    final rows = await container.read(incomingRequestsProvider.future);
    expect(rows.length, 1);
    expect(rows.first.fromUser.displayName, 'Mira Joshi');
  });
}

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

PocketBaseClient _offlineClient() =>
    PocketBaseClient.forTest(PocketBase('http://127.0.0.1:1'));

/// A repository whose fetch never completes — the blackhole.
class _BlackholeFriendRepo implements FriendRepository {
  @override
  Future<List<FriendRequest>> getIncomingRequests() =>
      Completer<List<FriendRequest>>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _BlackholeMessageRepo implements MessageRepository {
  @override
  Future<List<GroupInvite>> getIncomingGroupInvites() =>
      Completer<List<GroupInvite>>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _OkFriendRepo implements FriendRepository {
  @override
  Future<List<FriendRequest>> getIncomingRequests() async => [_request()];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

class _OkMessageRepo implements MessageRepository {
  @override
  Future<List<GroupInvite>> getIncomingGroupInvites() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

/// A TCP server that accepts connections and never answers.
class _BlackholeServer {
  _BlackholeServer._(this._server);

  static Future<_BlackholeServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      // Accept the connection, never respond.
    });
    return _BlackholeServer._(server);
  }

  final HttpServer _server;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> close() async {
    await _server.close(force: true);
  }
}
