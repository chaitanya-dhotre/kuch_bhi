import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:cryptography/cryptography.dart' show X25519;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/core/decrypt/decrypt_pass.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/providers/encryption_sync_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/auth_repository_impl.dart';
import 'package:kuch_bhi/services/encryption_service.dart';
import 'package:pocketbase/pocketbase.dart' show PocketBase;

import 'char_harness.dart';

/// P6 (user report 2026-10-11): an OFFLINE cold start with an already-set-up
/// encryption key must NOT route to the Backup-PIN setup screen.
///
/// Root cause: `EncryptionSyncStatus` read `hasPocketBaseBackup()` — a NETWORK
/// call whose catch-all returns `false` on ANY error. Offline, "backup check
/// failed" was indistinguishable from "no backup exists", so a user with a
/// perfectly good LOCAL key fell through to `needsSetup`. This file pins the
/// tri-state contract: the check must distinguish "confirmed absent" from
/// "could not check", and a local key + unknown backup state = keyOk.
class _KeyedSecureStorage extends FakeSecureStorage {
  _KeyedSecureStorage();

  @override
  Future<String?> getPrivateKey() async => 'ZmFrZS1wcml2YXRlLWtleQ==';
}

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override
  Future<AuthState> build() async => _fixed;
}

User _user() => User(
      id: 'u_test',
      displayName: 'Test',
      username: 'test',
      email: 'test@example.com',
      friendCode: 'FRIEND1',
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// PB client whose every request dies like a network-down condition.
http.Client Function() _networkDownFactory() => () =>
    MockClient((_) async => throw http.ClientException('network down'));

/// PB client whose users/one record carries an encrypted private key
/// (= backup confirmed on server).
http.Client Function() _backupExistsFactory() => () => MockClient((req) async {
      if (req.url.path.contains('/collections/users/records/u_test')) {
        return http.Response(
          jsonEncode({
            'id': 'u_test',
            'collectionId': 'users',
            'collectionName': 'users',
            'created': '2026-01-01T00:00:00.000Z',
            'updated': '2026-01-01T00:00:00.000Z',
            'fields': <String, dynamic>{},
            'private_key_encrypted': 'ENCRYPTED_BLOB',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"message":"not found"}', 404,
          headers: {'content-type': 'application/json'});
    });

const _json = {'content-type': 'application/json'};

Map<String, dynamic> _userRecord(String backup) => {
      'id': 'u_test',
      'collectionId': 'users',
      'collectionName': 'users',
      'created': '2026-01-01T00:00:00.000Z',
      'updated': '2026-01-01T00:00:00.000Z',
      'public_key': backup.isEmpty ? '' : 'BACKED_UP_PUB',
      'private_key_encrypted': backup,
      'private_key_salt': backup.isEmpty ? '' : 'SALT',
    };

/// K3: a sign-in network blip. The first [failFirst] reads of the user
/// record die like a dropped connection; later reads answer with [backup] as
/// the stored backup blob ('' = none). Every PATCH body lands in [patches].
http.Client Function() _blipFactory({
  required int failFirst,
  required String backup,
  required List<Map<String, dynamic>> patches,
}) {
  var reads = 0;
  return () => MockClient((req) async {
        if (!req.url.path.endsWith('/collections/users/records/u_test')) {
          return http.Response('{"message":"not found"}', 404, headers: _json);
        }
        if (req.method == 'PATCH') {
          patches.add(jsonDecode(req.body) as Map<String, dynamic>);
        } else if (reads++ < failFirst) {
          throw http.ClientException('blip');
        }
        return http.Response(jsonEncode(_userRecord(backup)), 200,
            headers: _json);
      });
}

/// The signed-in, cached user on a device whose key slot is empty: the
/// state `getCurrentUser`'s reinstall branch runs key init from.
Future<void> _seedSignedInUser(AppDatabase db) async {
  final at = DateTime.utc(2026, 1, 1);
  await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
  await db.usersDao.upsertUser(UsersTableCompanion.insert(
      id: 'u_test', displayName: 'Test', username: 'test',
      friendCode: 'FRIEND1', createdAt: at, updatedAt: at));
}

Future<EncryptionSyncStatus> _route(EncryptionService enc, AppDatabase db) async {
  final container = ProviderContainer(overrides: [
    authProvider.overrideWith(
        () => _FixedAuthNotifier(AuthAuthenticated(_user()))),
    encryptionServiceProvider.overrideWithValue(enc),
    appDatabaseProvider.overrideWithValue(db),
  ]);
  addTearDown(container.dispose);
  await container.read(authProvider.future);
  return container.read(encryptionSyncProvider.future);
}

class _FakeConnectivity implements Connectivity {
  final _changes = StreamController<List<ConnectivityResult>>.broadcast();
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _changes.stream;
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.none];
  void goOnline() => _changes.add([ConnectivityResult.wifi]);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// K3: a device WITH a key routes while offline, then the network returns.
/// Returns the offline route and every route state seen after the reconnect.
Future<(EncryptionSyncStatus, List<AsyncValue<EncryptionSyncStatus>>)>
    _routeThenReconnect({required String backup}) async {
  var online = false;
  final up = _blipFactory(failFirst: 0, backup: backup, patches: []);
  final h = charHarness(
      clientFactory: () => online
          ? up()
          : MockClient((_) async => throw http.ClientException('offline')));
  addTearDown(h.close);
  h.storage.put('private_key', 'ZmFrZS1wcml2YXRlLWtleQ==');
  final net = _FakeConnectivity();
  final container = ProviderContainer(overrides: [
    authProvider.overrideWith(
        () => _FixedAuthNotifier(AuthAuthenticated(_user()))),
    encryptionServiceProvider.overrideWithValue(h.encryption),
    appDatabaseProvider.overrideWithValue(h.db),
    connectivitySignalProvider
        .overrideWithValue(ConnectivitySignal(connectivity: net)),
  ]);
  addTearDown(container.dispose);
  await container.read(authProvider.future);
  final offline = await container.read(encryptionSyncProvider.future);

  final after = <AsyncValue<EncryptionSyncStatus>>[];
  container.listen(encryptionSyncProvider, (_, next) => after.add(next));
  online = true;
  net.goOnline();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return (offline, after);
}

Future<EncryptionSyncStatus> _status({
  required http.Client Function() clientFactory,
}) async {
  final prep = charHarness();
  await prep.close();
  final storage = _KeyedSecureStorage();
  final pb = PocketBase('http://pocketbase.test',
      httpClientFactory: clientFactory);
  final pbClient = PocketBaseClient.forTest(pb);
  final enc = EncryptionService(storage, pbClient);
  final db = AppDatabase.test();
  addTearDown(db.close);

  final container = ProviderContainer(overrides: [
    authProvider.overrideWith(
        () => _FixedAuthNotifier(AuthAuthenticated(_user()))),
    encryptionServiceProvider.overrideWithValue(enc),
    appDatabaseProvider.overrideWithValue(db),
  ]);
  addTearDown(container.dispose);
  // Pre-settle auth: production routes only AFTER the session resolves, and
  // a FutureProvider's first build while a watched AsyncNotifier is still
  // AsyncLoading never re-emits under this riverpod version (probe-proven) —
  // this matches the real cold-start order.
  await container.read(authProvider.future);
  return container.read(encryptionSyncProvider.future);
}

void main() {
  test('P6.1 offline cold start WITH a local key: network-down backup check '
      'yields keyOk — never needsSetup (the reported bug)', () async {
    final status = await _status(
      clientFactory: _networkDownFactory(), // airplane mode / server unreachable
    );
    expect(status, EncryptionSyncStatus.keyOk,
        reason: 'a local key means the user can decrypt offline; the backup '
            'state is a server concern and an unreachable server is not '
            'evidence that no backup exists');
  });

  test('P6.2 local key + backup CONFIRMED on server: keyOk (regression)', () async {
    final status = await _status(
      clientFactory: _backupExistsFactory(),
    );
    expect(status, EncryptionSyncStatus.keyOk);
  });

  test('P6.3 no local key + network down: Restore, never setup (K3 — an '
      'unanswered check is not "no backup"; Restore writes nothing and its '
      'Start Fresh exit covers a new account)', () async {
    backupCheckRetryDelay = Duration.zero;
    addTearDown(() => backupCheckRetryDelay = const Duration(seconds: 2));
    final storage = FakeSecureStorage(); // base fake: getPrivateKey → null
    final pb = PocketBase('http://pocketbase.test',
        httpClientFactory: _networkDownFactory());
    final enc = EncryptionService(storage, PocketBaseClient.forTest(pb));
    final db = AppDatabase.test();
    addTearDown(db.close);
    expect(await _route(enc, db), EncryptionSyncStatus.needsRestore);
  });

  test('K1 fresh-install sign-in: a decrypt pass with no local key + a '
      'server backup creates NO key and the route stays needsRestore',
      () async {
    final storage = FakeSecureStorage(); // fresh install: empty key slot
    final pb = PocketBase('http://pocketbase.test',
        httpClientFactory: _backupExistsFactory());
    final enc = EncryptionService(storage, PocketBaseClient.forTest(pb));
    final db = AppDatabase.test();
    addTearDown(db.close);

    // What the message layer's auth listener sees right after sign-in: a
    // synced DM with the peer's public key and an undecrypted row.
    final at = DateTime.utc(2026, 1, 1);
    await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
    await db.conversationsDao.upsertConversation(
        ConversationsTableCompanion.insert(
            id: 'd1', type: 'direct', createdById: 'u_peer',
            createdAt: at, updatedAt: at));
    for (final uid in ['u_test', 'u_peer']) {
      await db.conversationsDao.upsertMember(
          ConversationMembersTableCompanion.insert(
              id: 'm_$uid', conversationId: 'd1', userId: uid, joinedAt: at));
    }
    await db.usersDao.upsertUser(UsersTableCompanion.insert(
        id: 'u_peer', displayName: 'Peer', username: 'peer',
        friendCode: 'PEER1', createdAt: at, updatedAt: at,
        publicKey: Value(base64.encode(List<int>.filled(32, 9)))));
    await db.messagesDao.upsertMessage(MessagesTableCompanion.insert(
        localId: 'msg1', conversationId: 'd1', senderId: 'u_peer',
        type: 'text', encryptedBody: 'AAAA', iv: 'AAAAAAAAAAAAAAAA',
        serverId: const Value('srv_msg1'),
        decryptState: const Value('key_missing'),
        createdAt: at, updatedAt: at));

    await DecryptPass(db: db, enc: enc, epoch: () => 0).runFor(const ['msg1']);

    expect(await storage.getPrivateKey(), isNull,
        reason: 'decrypting must never generate the device key pair');
    final row = (await db.messagesDao.getMessageByLocalId('msg1'))!;
    expect(row.decryptState, 'key_missing');

    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(
          () => _FixedAuthNotifier(AuthAuthenticated(_user()))),
      encryptionServiceProvider.overrideWithValue(enc),
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    await container.read(authProvider.future);
    expect(await container.read(encryptionSyncProvider.future),
        EncryptionSyncStatus.needsRestore);
  });

  test('K3 existing account, network blip at sign-in key init: no key is '
      'generated, the backed-up public key is never overwritten, and the '
      'route lands on Restore', () async {
    final patches = <Map<String, dynamic>>[];
    final h = charHarness(
        clientFactory: _blipFactory(
            failFirst: 1, backup: 'ENCRYPTED_BLOB', patches: patches));
    addTearDown(h.close);
    await _seedSignedInUser(h.db);

    await AuthRepositoryImpl(
            pbClient: h.pbClient, db: h.db, storage: h.storage)
        .getCurrentUser();

    expect(patches, isEmpty,
        reason: 'an unanswered backup check is not "no backup"; uploading a '
            'new public key would orphan the backed-up one');
    expect(await h.storage.getPrivateKey(), isNull);
    expect(await _route(h.encryption, h.db), EncryptionSyncStatus.needsRestore);

    // Setup reached anyway (a stale route): it must not create a key either.
    await h.encryption.backupOrCreateKey('123456');
    expect(patches, isEmpty);
    expect(await h.storage.getPrivateKey(), isNull);
  });

  test('K3 new account, network blip at sign-in key init: the route waits '
      'out the blip, lands on setup, and setup creates a working key',
      () async {
    backupCheckRetryDelay = Duration.zero;
    addTearDown(() => backupCheckRetryDelay = const Duration(seconds: 2));
    final patches = <Map<String, dynamic>>[];
    // Lost reads: key init's check and the route's first check.
    final h = charHarness(
        clientFactory:
            _blipFactory(failFirst: 2, backup: '', patches: patches));
    addTearDown(h.close);
    await _seedSignedInUser(h.db);

    await AuthRepositoryImpl(
            pbClient: h.pbClient, db: h.db, storage: h.storage)
        .getCurrentUser();
    expect(await h.storage.getPrivateKey(), isNull,
        reason: 'nothing is generated on an unknown backup state');
    expect(await _route(h.encryption, h.db), EncryptionSyncStatus.needsSetup);

    // What Backup PIN setup runs on submit.
    await h.encryption.backupOrCreateKey('7KQ2M-9XHMA-4TRBC-8D1WZ-P6YVN');

    final pub = await h.storage.getLocalPublicKey();
    expect(pub, isNotNull);
    expect(patches.map((p) => p['public_key']), contains(pub),
        reason: 'the new public key is published, so peers can reach it');
    expect(patches.where((p) => p['private_key_encrypted'] != null),
        isNotEmpty, reason: 'and the new private key is backed up');
    await h.encryption.getOrDeriveConversationKey(
        'd1', base64.encode(List<int>.filled(32, 9)));
  });

  test('K3 register on a blip: a just-created account has no backup, so it '
      'gets a key without asking the server, never lands on Restore, and '
      'publishes the key once back online', () async {
    var online = false;
    final patches = <Map<String, dynamic>>[];
    final up = _blipFactory(failFirst: 0, backup: '', patches: patches);
    final h = charHarness(
        clientFactory: () => online
            ? up()
            : MockClient((_) async => throw http.ClientException('blip')));
    addTearDown(h.close);
    await _seedSignedInUser(h.db);
    final auth =
        AuthRepositoryImpl(pbClient: h.pbClient, db: h.db, storage: h.storage);

    await auth.initEncryptionKeysForTest('u_test', newAccount: true);
    expect(await h.storage.getPrivateKey(), isNotNull);
    expect(await _route(h.encryption, h.db), EncryptionSyncStatus.keyOk);

    online = true; // the next _saveSession (resume refresh, sign-in)
    await auth.initEncryptionKeysForTest('u_test');
    expect(patches.map((p) => p['public_key']),
        contains(await h.storage.getLocalPublicKey()));
  });

  test('K3 a new account registered offline gets PIN setup as soon as the '
      'network is back, without reopening the app', () async {
    final (offline, after) = await _routeThenReconnect(backup: '');
    expect(offline, EncryptionSyncStatus.keyOk);
    expect(after.last.valueOrNull, EncryptionSyncStatus.needsSetup);
  });

  test('K3 a reconnect with the backup in place does not re-route (no '
      'bounce through the splash out of an open chat)', () async {
    final (offline, after) =
        await _routeThenReconnect(backup: 'ENCRYPTED_BLOB');
    expect(offline, EncryptionSyncStatus.keyOk);
    expect(after, isEmpty);
  });

  test('K3 new-account flag never overrides a backup the server reports',
      () async {
    final patches = <Map<String, dynamic>>[];
    final h = charHarness(
        clientFactory: _blipFactory(
            failFirst: 0, backup: 'ENCRYPTED_BLOB', patches: patches));
    addTearDown(h.close);
    await _seedSignedInUser(h.db);
    await AuthRepositoryImpl(
            pbClient: h.pbClient, db: h.db, storage: h.storage)
        .initEncryptionKeysForTest('u_test', newAccount: true);
    expect(patches, isEmpty);
    expect(await h.storage.getPrivateKey(), isNull);
  });

  test('K3 offline Restore and Start Fresh: a dead read is an error, not '
      '"Incorrect PIN", and Start Fresh leaves no unpublished key', () async {
    final h = charHarness(clientFactory: _networkDownFactory());
    addTearDown(h.close);
    await expectLater(h.encryption.restorePrivateKey('123456'), throwsA(anything));
    await expectLater(
        h.encryption.generateAndBackupNewKey('123456'), throwsA(anything));
    expect(await h.storage.getPrivateKey(), isNull);
    await expectLater(h.encryption.backupOrCreateKey('123456'), throwsA(anything));
  });

  test('K1 a private key whose public half was never written still derives '
      'the same key, and nothing is written', () async {
    final full = charHarness();
    addTearDown(full.close);
    final kp = await X25519().newKeyPair();
    final priv = base64.encode(await kp.extractPrivateKeyBytes());
    final pub = base64.encode((await kp.extractPublicKey()).bytes);
    full.storage.put('private_key', priv);
    full.storage.put('local_public_key', pub);
    final peer = base64.encode(List<int>.filled(32, 9));
    final expected =
        await full.encryption.getOrDeriveConversationKey('d1', peer);

    final half = charHarness();
    addTearDown(half.close);
    half.storage.put('private_key', priv); // crash before the pub write
    expect(await half.encryption.getOrDeriveConversationKey('d1', peer),
        expected);
    expect(await half.storage.getLocalPublicKey(), isNull);
    expect(await half.storage.getPrivateKey(), priv);
  });
}
