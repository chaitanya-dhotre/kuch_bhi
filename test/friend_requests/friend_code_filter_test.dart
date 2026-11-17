// F21 (client security wave 2): only `^[A-Z0-9]{6}$` reaches the server.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/secure_storage/secure_storage_service.dart';
import 'package:kuch_bhi/domain/repositories/friend_repository.dart';
import 'package:kuch_bhi/infrastructure/repositories/friend_repository_impl.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  test('isFriendCode accepts only 6 of A-Z0-9', () {
    expect(isFriendCode('ABC123'), isTrue);
    for (final bad in ['abc123', '"||1=1', 'ABC12', 'ABC1234', 'ÄBC123', '']) {
      expect(isFriendCode(bad), isFalse, reason: bad);
    }
  });

  test('findUserByCode sends no request for a bad code, an escaped filter '
      'for a good one', () async {
    final requests = <http.Request>[];
    final pb = PocketBase(
      'http://pocketbase.test',
      httpClientFactory: () => MockClient((r) async {
        requests.add(r);
        return http.Response('{"message":"not found"}', 404);
      }),
    );
    final db = AppDatabase.test();
    addTearDown(db.close);
    final repo = FriendRepositoryImpl(
      pbClient: PocketBaseClient.forTest(pb),
      db: db,
      storage: SecureStorageService(),
    );

    expect(await repo.findUserByCode('"||1=1'), isNull);
    expect(requests, isEmpty);

    expect(await repo.findUserByCode('abc123'), isNull);
    expect(requests, hasLength(1));
    expect(
      requests.single.url.queryParameters['filter'],
      "friend_code = 'ABC123'",
    );
  });
}
