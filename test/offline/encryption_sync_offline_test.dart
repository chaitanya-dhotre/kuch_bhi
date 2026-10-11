import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/providers/encryption_sync_provider.dart';
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

  test('P6.3 no local key + network down: stays needsSetup (unchanged — '
      'without a local key there is nothing to decrypt either way)', () async {
    final storage = FakeSecureStorage(); // base fake: getPrivateKey → null
    final pb = PocketBase('http://pocketbase.test',
        httpClientFactory: _networkDownFactory());
    final enc = EncryptionService(storage, PocketBaseClient.forTest(pb));
    final db = AppDatabase.test();
    addTearDown(db.close);
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith(
          () => _FixedAuthNotifier(AuthAuthenticated(_user()))),
      encryptionServiceProvider.overrideWithValue(enc),
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);
    await container.read(authProvider.future); // same pre-settle as _status
    final status = await container.read(encryptionSyncProvider.future);
    expect(status, EncryptionSyncStatus.needsSetup);
  });
}
