import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/network/pocketbase_client.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/secure_storage/secure_storage_service.dart';
import 'package:kuch_bhi/domain/repositories/auth_repository.dart';
import 'package:kuch_bhi/infrastructure/repositories/auth_repository_impl.dart';
import 'package:pocketbase/pocketbase.dart';

/// A server that never answers.
MockClient _hang() => MockClient((_) => Completer<http.Response>().future);

/// Any storage call means _saveSession ran.
class _Storage implements SecureStorageService {
  final calls = <Symbol>[];
  @override
  dynamic noSuchMethod(Invocation i) {
    calls.add(i.memberName);
    return Future<void>.value();
  }
}

/// The Google picker answers at once (user-paced legs are not bounded).
class _Google extends GoogleSignInPlatform {
  @override
  Future<void> initWithParams(SignInInitParameters params) async {}
  @override
  Future<GoogleSignInUserData?> signIn() async =>
      GoogleSignInUserData(email: 'a@b.c', id: '1');
  @override
  Future<GoogleSignInTokenData> getTokens(
          {required String email, bool? shouldRecoverAuth}) async =>
      GoogleSignInTokenData(idToken: 'id-token');
}

void main() {
  late PocketBase pb;
  late _Storage storage;
  late AuthRepositoryImpl repo;

  setUp(() {
    pb = PocketBase('http://pb.test', httpClientFactory: _hang);
    storage = _Storage();
    repo = AuthRepositoryImpl(
      pbClient: PocketBaseClient.forTest(pb),
      db: AppDatabase.test(),
      storage: storage,
    );
    GoogleSignInPlatform.instance = _Google();
  });

  tearDown(() => repo.db.close());

  final timeout = isA<AuthException>().having((e) => e.code, 'code', 'timeout');

  testWidgets('password sign-in gives up at 8s; no session saved',
      (tester) async {
    Object? error;
    unawaited(repo
        .signInWithEmailPassword(email: 'a@b.c', password: 'pw')
        .then<void>((_) {}, onError: (Object e) => error = e));
    await tester.pump(const Duration(seconds: 7));
    expect(error, isNull, reason: 'not before 8s');
    await tester.pump(const Duration(seconds: 1, milliseconds: 50));
    expect(error, timeout);
    expect(pb.authStore.token, isEmpty);
    expect(storage.calls, isEmpty, reason: '_saveSession never ran');
  });

  testWidgets('Google sign-in: the hook POST gives up at 8s; no session',
      (tester) async {
    Object? error;
    unawaited(http.runWithClient(
      () => repo.signInWithGoogle().catchError((Object e) {
        error = e;
        return null;
      }),
      _hang,
    ));
    await tester.pump(const Duration(seconds: 7));
    expect(error, isNull);
    await tester.pump(const Duration(seconds: 1, milliseconds: 50));
    expect(error, timeout);
    expect(pb.authStore.token, isEmpty);
    expect(storage.calls, isEmpty);
  });

  testWidgets('password reset gives up at 8s', (tester) async {
    Object? error;
    unawaited(
        repo.requestPasswordReset('a@b.c').then<void>((_) {},
            onError: (Object e) => error = e));
    await tester.pump(const Duration(seconds: 8, milliseconds: 50));
    expect(error, timeout);
  });

  group('google-auth hook register answers (decision 18 live)', () {
    Future<Object?> register(int status, String body) async {
      Object? error;
      await http.runWithClient(
        () => repo
            .registerWithGoogle(idToken: 't', displayName: 'I', username: 'ichigo')
            .then<void>((_) {}, onError: (Object e) => error = e),
        () => MockClient((_) async => http.Response(body, status)),
      );
      return error;
    }

    test('400 username validation_not_unique → UsernameTakenException',
        () async {
      expect(
          await register(400,
              '{"data":{"username":{"code":"validation_not_unique","message":"Username is taken."}}}'),
          isA<UsernameTakenException>());
      expect(storage.calls, isEmpty);
    });

    test('503 (hook cannot reach Google) → code 503', () async {
      expect(await register(503, '{"message":"Google unavailable"}'),
          isA<AuthException>().having((e) => e.code, 'code', '503'));
    });
  });

  testWidgets('register gives up at 8s even in the friend-code lookup',
      (tester) async {
    Object? error;
    unawaited(repo
        .register(
            email: 'a@b.c', password: 'secret123', displayName: 'A', username: 'abc')
        .then<void>((_) {}, onError: (Object e) => error = e));
    await tester.pump(const Duration(seconds: 8, milliseconds: 50));
    expect(error, timeout);
    expect(storage.calls, isEmpty);
  });
}
