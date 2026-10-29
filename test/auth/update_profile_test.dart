import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/infrastructure/repositories/auth_repository_impl.dart';
import 'package:pocketbase/pocketbase.dart';

import '../fakes/fake_auth_repository.dart';

ClientException _err(int status, Map<String, dynamic> response) =>
    ClientException(statusCode: status, response: response);

void main() {
  group('profileUpdateBody', () {
    test('exactly display_name, username (lower-cased), about', () {
      final body = profileUpdateBody(
          displayName: 'Avni', username: 'AvNi_1', about: 'hi');
      expect(body, {'display_name': 'Avni', 'username': 'avni_1', 'about': 'hi'});
    });

    test('avatar: null only when clearAvatar; never keys', () {
      final cleared = profileUpdateBody(
          displayName: 'A', username: 'abc', clearAvatar: true);
      expect(cleared.containsKey('avatar'), isTrue);
      expect(cleared['avatar'], isNull);
      final kept = profileUpdateBody(displayName: 'A', username: 'abc');
      expect(kept.containsKey('avatar'), isFalse);
      for (final b in [cleared, kept]) {
        expect(b.containsKey('public_key'), isFalse);
        expect(b.containsKey('friend_code'), isFalse);
      }
    });
  });

  group('isUsernameTaken', () {
    final taken = {
      'data': {'username': {'code': 'validation_not_unique'}}
    };
    test('true only for 400 + username + validation_not_unique', () {
      expect(isUsernameTaken(_err(400, taken)), isTrue);
      expect(isUsernameTaken(_err(500, taken)), isFalse);
      expect(
          isUsernameTaken(_err(400, {
            'data': {'email': {'code': 'validation_not_unique'}}
          })),
          isFalse);
      expect(
          isUsernameTaken(_err(400, {
            'data': {'username': {'code': 'validation_required'}}
          })),
          isFalse);
      expect(isUsernameTaken(_err(400, {})), isFalse);
    });
  });

  test('notifier sets the saved user without rebuilding or touching keys',
      () async {
    final repo = FakeAuthRepository(fakeUser());
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await container.read(authProvider.future);
    expect(repo.getCurrentUserCalls, 1);

    await container.read(authProvider.notifier).updateProfile(
        displayName: 'New Name', username: 'newname', about: 'x');

    final s = container.read(authProvider).value as AuthAuthenticated;
    expect(s.user.displayName, 'New Name');
    expect(s.user.username, 'newname');
    expect(repo.getCurrentUserCalls, 1, reason: 'build() must not re-run');
    expect(repo.updatePublicKeyCalls, 0);
  });
}
