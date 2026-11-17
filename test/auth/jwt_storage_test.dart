// F19 (client security wave 2): the session JWT is never kept in plain
// Drift. A copy an older build left there moves to secure storage once.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';
import 'package:kuch_bhi/data/local/secure_storage/secure_storage_service.dart';
import 'package:kuch_bhi/infrastructure/repositories/auth_repository_impl.dart';
import 'package:pocketbase/pocketbase.dart';

class _Storage implements SecureStorageService {
  String? token;
  @override
  Future<void> saveAuthToken(String t) async => token = t;
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

String _jwt() {
  String enc(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m)));
  return '${enc(const {'alg': 'HS256', 'typ': 'JWT'})}.'
      '${enc(const {'exp': 4102444800})}.sig';
}

void main() {
  test('a Drift token from an older build moves to secure storage once',
      () async {
    final pb = PocketBase('http://pb.test',
        httpClientFactory: () =>
            MockClient((_) async => http.Response('{}', 401)));
    final db = AppDatabase.test();
    addTearDown(db.close);
    final storage = _Storage();
    final repo = AuthRepositoryImpl(
        pbClient: PocketBaseClient.forTest(pb), db: db, storage: storage);
    final token = _jwt();
    await db.settingsDao.setSetting(AppSettingsKeys.authToken, token);

    await repo.getCurrentUser();

    expect(storage.token, token);
    expect(await db.settingsDao.getSetting(AppSettingsKeys.authToken), isNull);
  });

  test('no Drift token: nothing is restored, nothing written', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final storage = _Storage();
    final repo = AuthRepositoryImpl(
        pbClient: PocketBaseClient.forTest(PocketBase('http://pb.test')),
        db: db,
        storage: storage);

    expect(await repo.getCurrentUser(), isNull);
    expect(storage.token, isNull);
  });
}
