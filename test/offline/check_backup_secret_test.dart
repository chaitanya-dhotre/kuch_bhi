import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/utils/recovery_key.dart';
import 'package:kuch_bhi/services/encryption_service.dart';

import 'char_harness.dart';

const _json = {'content-type': 'application/json'};

/// One users record; every request's method is kept in [methods] so a test
/// can prove nothing but GETs went out.
class _Server {
  _Server({String blob = '', String salt = ''})
    : record = {
        'id': 'u_test',
        'collectionId': 'users',
        'collectionName': 'users',
        'created': '2026-01-01T00:00:00.000Z',
        'updated': '2026-01-01T00:00:00.000Z',
        'public_key': '',
        'private_key_encrypted': blob,
        'private_key_salt': salt,
      };

  final Map<String, dynamic> record;
  final methods = <String>[];

  http.Client client() => MockClient((req) async {
    methods.add(req.method);
    if (req.method == 'PATCH') {
      record.addAll(jsonDecode(req.body) as Map<String, dynamic>);
    }
    return http.Response(jsonEncode(record), 200, headers: _json);
  });
}

final _priv = List<int>.generate(32, (i) => 200 - i);
final _otherPriv = List<int>.generate(32, (i) => i + 7);

Future<String> _pubOf(List<int> priv) async => base64.encode(
  (await (await X25519().newKeyPairFromSeed(priv)).extractPublicKey()).bytes,
);

/// v1 as the old app wrote it: PBKDF2-100k of the PIN, 32-byte salt, no AAD.
Future<(String, String)> _v1(List<int> priv, String pin) async {
  final salt = List<int>.generate(32, (i) => i * 3);
  final key = await Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  ).deriveKeyFromPassword(password: pin, nonce: salt);
  final nonce = List<int>.generate(12, (i) => i + 40);
  final box = await AesGcm.with256bits().encrypt(
    priv,
    secretKey: key,
    nonce: nonce,
  );
  return (
    base64.encode([...nonce, ...box.cipherText, ...box.mac.bytes]),
    base64.encode(salt),
  );
}

/// A v2 blob for [_priv] under a fresh recovery key, made by the real writer.
Future<(_Server, String)> _v2Server() async {
  final server = _Server();
  final writer = charHarness(clientFactory: server.client);
  addTearDown(writer.close);
  await writer.storage.savePrivateKey(base64.encode(_priv));
  await writer.storage.saveLocalPublicKey(await _pubOf(_priv));
  final key = generateRecoveryKey();
  await writer.encryption.backupPrivateKey(key);
  server.methods.clear();
  return (server, key);
}

/// Checks [secret] on a device that holds a DIFFERENT key plus cached
/// conversation keys, and proves the check wrote nothing anywhere.
Future<RestoreResult> _check(http.Client Function() client, String secret,
    {_Server? server}) async {
  final h = charHarness(clientFactory: client);
  addTearDown(h.close);
  await h.storage.savePrivateKey(base64.encode(_otherPriv));
  await h.storage.saveLocalPublicKey(await _pubOf(_otherPriv));
  await h.storage.write(key: 'conv_key_c1', value: 'AAAA');
  await h.storage.write(key: 'group_key_g1', value: 'BBBB');
  final before = await h.storage.readAll();
  final recordBefore = jsonEncode(server?.record);

  try {
    return await h.encryption.checkBackupSecret(secret);
  } finally {
    expect(await h.storage.readAll(), before);
    expect(jsonEncode(server?.record), recordBefore);
    if (server != null) expect(server.methods.toSet(), {'GET'});
  }
}

void main() {
  test('v2 + the right recovery key (typed lowercase with spaces) → '
      'restored', () async {
    final (server, key) = await _v2Server();
    final typed = recoveryKeyGroups(key).join(' ').toLowerCase();
    expect(
      await _check(server.client, typed, server: server),
      RestoreResult.restored,
    );
  });

  test('v1 + its PIN → restoredLegacy', () async {
    final (blob, salt) = await _v1(_priv, '123456');
    final server = _Server(blob: blob, salt: salt);
    expect(
      await _check(server.client, '123456', server: server),
      RestoreResult.restoredLegacy,
    );
  });

  test('wrong secret → wrongSecret (v2 wrong key, v2 garbage, v1 wrong '
      'PIN)', () async {
    final (server, _) = await _v2Server();
    expect(
      await _check(server.client, generateRecoveryKey(), server: server),
      RestoreResult.wrongSecret,
    );
    expect(
      await _check(server.client, 'not a key', server: server),
      RestoreResult.wrongSecret,
    );
    final (blob, salt) = await _v1(_priv, '123456');
    final v1 = _Server(blob: blob, salt: salt);
    expect(
      await _check(v1.client, '654321', server: v1),
      RestoreResult.wrongSecret,
    );
  });

  test('no blob → noBackup', () async {
    final server = _Server();
    expect(
      await _check(server.client, '123456', server: server),
      RestoreResult.noBackup,
    );
  });

  test('v9: → unsupported', () async {
    final server = _Server(blob: 'v9:AAAA', salt: 'AAAA');
    expect(
      await _check(server.client, '123456', server: server),
      RestoreResult.unsupported,
    );
  });

  test('offline → throws, storage untouched', () async {
    await expectLater(
      _check(
        () => MockClient((_) async => throw http.ClientException('down')),
        '123456',
      ),
      throwsA(anything),
    );
  });
}
