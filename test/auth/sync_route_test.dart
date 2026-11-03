import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/router/app_router.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/auth/providers/encryption_sync_provider.dart';
import 'package:kuch_bhi/services/encryption_service.dart';

import '../offline/char_harness.dart';

/// Cold start on mobile data (2026-11-03): one backup read took 6–19 s and
/// the router held the splash for all of it. A reload for a user already
/// routed keyOk stays put; a device with a key waits at most the budget.

User _user(String id) => User(
      id: id,
      displayName: 'Test',
      username: 'test',
      email: 'test@example.com',
      friendCode: 'FRIEND1',
      createdAt: DateTime.utc(2026, 1, 1),
    );

final _a = AuthAuthenticated(_user('u_test'));
const _first = AsyncLoading<EncryptionSyncStatus>();
const _keyOk = AsyncData(EncryptionSyncStatus.keyOk);
AsyncValue<EncryptionSyncStatus> _reload(EncryptionSyncStatus prev) =>
    const AsyncLoading<EncryptionSyncStatus>()
        .copyWithPrevious(AsyncData(prev), isRefresh: false);

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._fixed);
  final AuthState _fixed;
  @override
  Future<AuthState> build() async => _fixed;
}

/// Every users/u_test read waits on [answer], then reports [backup] ('' =
/// none). [reads] counts them.
http.Client Function() _slowServer(Completer<void> answer, String backup,
        List<int> reads) =>
    () => MockClient((req) async {
          reads.add(1);
          await answer.future;
          return http.Response(
              jsonEncode({
                'id': 'u_test',
                'collectionId': 'users',
                'collectionName': 'users',
                'created': '2026-01-01T00:00:00.000Z',
                'updated': '2026-01-01T00:00:00.000Z',
                'private_key_encrypted': backup,
              }),
              200,
              headers: {'content-type': 'application/json'});
        });

Future<(ProviderContainer, List<AsyncValue<EncryptionSyncStatus>>)> _keyedRoute(
    http.Client Function() server) async {
  final h = charHarness(clientFactory: server);
  addTearDown(h.close);
  h.storage.put('private_key', 'ZmFrZS1wcml2YXRlLWtleQ==');
  final c = ProviderContainer(overrides: [
    authProvider.overrideWith(() => _FixedAuthNotifier(_a)),
    encryptionServiceProvider.overrideWithValue(h.encryption),
    appDatabaseProvider.overrideWithValue(h.db),
  ]);
  addTearDown(c.dispose);
  await c.read(authProvider.future);
  final seen = <AsyncValue<EncryptionSyncStatus>>[];
  c.listen(encryptionSyncProvider, (_, next) => seen.add(next),
      fireImmediately: true);
  return (c, seen);
}

void main() {
  group('router: key-sync redirect', () {
    test('first load with no value shows the splash', () {
      final g = SyncRouteGate();
      expect(g.redirect(AppRoutes.splash, _a, _first), isNull);
      expect(g.redirect(AppRoutes.home, _a, _first), AppRoutes.splash);
    });

    test('a reload after keyOk for the same user stays put', () {
      final g = SyncRouteGate();
      expect(g.redirect(AppRoutes.splash, _a, _keyOk), AppRoutes.home);
      expect(g.redirect(AppRoutes.home, _a, _reload(EncryptionSyncStatus.keyOk)),
          isNull);
      expect(g.redirect(AppRoutes.chat, _a, _reload(EncryptionSyncStatus.keyOk)),
          isNull);
    });

    test('a reload that answers needsSetup / needsRestore still routes', () {
      final g = SyncRouteGate();
      g.redirect(AppRoutes.splash, _a, _keyOk);
      expect(g.redirect(AppRoutes.home, _a,
              const AsyncData(EncryptionSyncStatus.needsSetup)),
          AppRoutes.backupPinSetup);
      expect(g.redirect(AppRoutes.backupPinSetup, _a,
              _reload(EncryptionSyncStatus.needsSetup)),
          AppRoutes.splash, reason: 'only a keyOk answer is trusted mid-reload');
      expect(g.redirect(AppRoutes.splash, _a,
              const AsyncData(EncryptionSyncStatus.needsRestore)),
          AppRoutes.backupPinRestore);
    });

    test('the cold-start keyOk computed before sign-in settled is not '
        'trusted: the reload waits on the splash', () {
      final g = SyncRouteGate();
      expect(g.redirect(AppRoutes.splash, null, _keyOk), isNull);
      expect(g.redirect(AppRoutes.splash, _a, _reload(EncryptionSyncStatus.keyOk)),
          isNull);
      expect(g.redirect(AppRoutes.home, _a, _reload(EncryptionSyncStatus.keyOk)),
          AppRoutes.splash);
    });

    test('keyOk for one user is not trusted for the next one', () {
      final g = SyncRouteGate();
      g.redirect(AppRoutes.splash, _a, _keyOk);
      final b = AuthAuthenticated(_user('u_other'));
      expect(g.redirect(AppRoutes.home, b, _reload(EncryptionSyncStatus.keyOk)),
          AppRoutes.splash);
      g.redirect(AppRoutes.splash, _a, _keyOk);
      g.redirect(AppRoutes.login, const AuthUnauthenticated(), _keyOk);
      expect(g.redirect(AppRoutes.home, _a, _reload(EncryptionSyncStatus.keyOk)),
          AppRoutes.splash, reason: 'a sign-out forgets the answer');
    });
  });

  group('sync route: a device with a key and a slow server', () {
    setUp(() => backupCheckBudget = const Duration(milliseconds: 50));
    tearDown(() => backupCheckBudget = const Duration(seconds: 3));

    test('past the budget the route is keyOk; a late "no backup" then '
        'routes to setup without another read', () async {
      final answer = Completer<void>();
      final reads = <int>[];
      final (c, seen) = await _keyedRoute(_slowServer(answer, '', reads));
      expect(await c.read(encryptionSyncProvider.future),
          EncryptionSyncStatus.keyOk);
      answer.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(seen.last.valueOrNull, EncryptionSyncStatus.needsSetup);
      expect(reads, hasLength(1));
    });

    test('a late answer with the backup in place changes nothing', () async {
      final answer = Completer<void>();
      final (c, seen) =
          await _keyedRoute(_slowServer(answer, 'ENCRYPTED_BLOB', []));
      expect(await c.read(encryptionSyncProvider.future),
          EncryptionSyncStatus.keyOk);
      final before = seen.length;
      answer.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(seen, hasLength(before));
    });

    test('an answer inside the budget routes as before', () async {
      final (c, _) =
          await _keyedRoute(_slowServer(Completer()..complete(), '', []));
      expect(await c.read(encryptionSyncProvider.future),
          EncryptionSyncStatus.needsSetup);
    });
  });
}
