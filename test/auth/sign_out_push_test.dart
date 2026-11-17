// F14 (client security wave 2): sign-out clears this phone's push token on
// the old account, with the session still attached, and never fails or
// hangs because the network is down.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';
import 'package:kuch_bhi/infrastructure/repositories/auth_repository_impl.dart';
import 'package:pocketbase/pocketbase.dart';

import '../offline/char_harness.dart';

String _jwt() {
  String enc(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m)));
  return '${enc(const {'alg': 'HS256', 'typ': 'JWT'})}.'
      '${enc(const {'exp': 4102444800})}.sig';
}

Future<(AuthRepositoryImpl, AppDatabase)> _repo(
    Future<http.Response> Function(http.Request) handler) async {
  final pb = PocketBase('http://pocketbase.test',
      httpClientFactory: () => MockClient(handler));
  pb.authStore.save(_jwt(), null);
  final db = AppDatabase.test();
  await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u1');
  final repo = AuthRepositoryImpl(
    pbClient: PocketBaseClient.forTest(pb),
    db: db,
    storage: FakeSecureStorage(userId: 'u1'),
  );
  return (repo, db);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clears users.fcm_token with the session attached', () async {
    final requests = <http.Request>[];
    final (repo, db) = await _repo((r) async {
      requests.add(r);
      return http.Response('{"id":"u1","collectionName":"users"}', 200);
    });
    addTearDown(db.close);

    await repo.signOut();

    final patch = requests.singleWhere((r) => r.method == 'PATCH');
    expect(patch.url.path, '/api/collections/users/records/u1');
    expect(jsonDecode(patch.body), {'fcm_token': ''});
    expect(patch.headers['Authorization'], isNotEmpty,
        reason: 'must run before clearAuth');
    expect(repo.pbClient.isAuthenticated, isFalse);
    expect(
        await db.settingsDao.getSetting(AppSettingsKeys.currentUserId), isNull);
  });

  test('a dead network does not stop sign-out', () async {
    final (repo, db) = await _repo(
        (r) async => throw http.ClientException('network down'));
    addTearDown(db.close);

    await repo.signOut();

    expect(repo.pbClient.isAuthenticated, isFalse);
    expect(
        await db.settingsDao.getSetting(AppSettingsKeys.currentUserId), isNull);
  });
}
