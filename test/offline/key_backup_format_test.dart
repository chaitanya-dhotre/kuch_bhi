import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/utils/recovery_key.dart';
import 'package:kuch_bhi/services/encryption_service.dart';

import 'char_harness.dart';

const _json = {'content-type': 'application/json'};

/// One users record that PATCHes really change. Every PATCH body is kept in
/// [patches]; [failPatch] drops a PATCH like a lost connection.
class _Server {
  _Server({String blob = '', String salt = '', String publicKey = ''})
    : record = {
        'id': 'u_test',
        'collectionId': 'users',
        'collectionName': 'users',
        'created': '2026-01-01T00:00:00.000Z',
        'updated': '2026-01-01T00:00:00.000Z',
        'public_key': publicKey,
        'private_key_encrypted': blob,
        'private_key_salt': salt,
      };

  final Map<String, dynamic> record;
  final patches = <Map<String, dynamic>>[];
  bool failPatch = false;

  http.Client client() => MockClient((req) async {
    if (!req.url.path.contains('/collections/users/records/')) {
      return http.Response('{"message":"not found"}', 404, headers: _json);
    }
    if (req.method == 'PATCH') {
      if (failPatch) throw http.ClientException('dropped');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      patches.add(body);
      record.addAll(body);
    }
    return http.Response(jsonEncode(record), 200, headers: _json);
  });
}

final _allPatches = <Map<String, dynamic>>[];

/// A harness on [server] whose device holds [priv] (null = no key).
Future<CharHarness> _device(_Server server, {List<int>? priv}) async {
  final h = charHarness(clientFactory: server.client);
  addTearDown(h.close);
  addTearDown(() => _allPatches.addAll(server.patches));
  if (priv != null) {
    await h.storage.savePrivateKey(base64.encode(priv));
    await h.storage.saveLocalPublicKey(await _pubOf(priv));
  }
  return h;
}

Future<String> _pubOf(List<int> priv) async => base64.encode(
  (await (await X25519().newKeyPairFromSeed(priv)).extractPublicKey()).bytes,
);

final _priv = List<int>.generate(32, (i) => 200 - i);
final _otherPriv = List<int>.generate(32, (i) => i + 7);

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

Future<List<int>?> _deviceKey(CharHarness h) async {
  final b64 = await h.storage.getPrivateKey();
  return b64 == null ? null : base64.decode(b64);
}

void main() {
  tearDownAll(() {
    // T9: only restore's re-publish (and Start Fresh) ever send public_key;
    // neither runs a backup write, so no PATCH carries both.
    for (final p in _allPatches) {
      expect(
        p.containsKey('public_key') && p.containsKey('private_key_encrypted'),
        isFalse,
        reason: 'backup writer sent public_key: $p',
      );
    }
  });

  test('T1 round-trip v2: v2 prefix, 16-byte salt, two keys only; the key '
      'typed lowercase with spaces restores the same device key', () async {
    final server = _Server();
    final a = await _device(server, priv: _priv);
    final key = generateRecoveryKey();
    await a.encryption.backupPrivateKey(key);

    expect(server.patches, hasLength(1));
    final p = server.patches.single;
    expect(p.keys.toSet(), {'private_key_encrypted', 'private_key_salt'});
    expect(p['private_key_encrypted'] as String, startsWith('v2:'));
    expect(base64.decode(p['private_key_salt'] as String), hasLength(16));

    final b = await _device(server);
    final typed = recoveryKeyGroups(key).join(' ').toLowerCase();
    expect(await b.encryption.restorePrivateKey(typed), RestoreResult.restored);
    expect(await _deviceKey(b), _priv);
  });

  test('T2 legacy v1 + its PIN → restoredLegacy, same key', () async {
    final (blob, salt) = await _v1(_priv, '123456');
    final h = await _device(_Server(blob: blob, salt: salt));
    expect(
      await h.encryption.restorePrivateKey('123456'),
      RestoreResult.restoredLegacy,
    );
    expect(await _deviceKey(h), _priv);
  });

  test('T3 old → new: after a legacy restore the upgrade writes v2; the key '
      'opens it, the old PIN no longer does', () async {
    final (blob, salt) = await _v1(_priv, '123456');
    final server = _Server(blob: blob, salt: salt);
    final h = await _device(server);
    await h.encryption.restorePrivateKey('123456');
    server.patches.clear(); // restore's public_key re-publish
    final key = generateRecoveryKey();
    await h.encryption.backupPrivateKey(key);
    expect(
      server.patches.single['private_key_encrypted'] as String,
      startsWith('v2:'),
    );

    final fresh = await _device(server);
    expect(
      await fresh.encryption.restorePrivateKey(key),
      RestoreResult.restored,
    );
    expect(await _deviceKey(fresh), _priv);
    final again = await _device(server);
    expect(
      await again.encryption.restorePrivateKey('123456'),
      RestoreResult.wrongSecret,
    );
  });

  test('T4 wrong secret (v1 and v2): wrongSecret, device key untouched, '
      'zero PATCH', () async {
    final (blob, salt) = await _v1(_priv, '123456');
    final v1 = _Server(blob: blob, salt: salt);
    final h1 = await _device(v1);
    expect(
      await h1.encryption.restorePrivateKey('654321'),
      RestoreResult.wrongSecret,
    );
    expect(await _deviceKey(h1), isNull);
    expect(v1.patches, isEmpty);

    final v2 = _Server();
    await (await _device(
      v2,
      priv: _priv,
    )).encryption.backupPrivateKey(generateRecoveryKey());
    v2.patches.clear();
    final h2 = await _device(v2, priv: _otherPriv);
    expect(
      await h2.encryption.restorePrivateKey(generateRecoveryKey()),
      RestoreResult.wrongSecret,
    );
    expect(
      await h2.encryption.restorePrivateKey('not a key'),
      RestoreResult.wrongSecret,
    );
    expect(await _deviceKey(h2), _otherPriv);
    expect(v2.patches, isEmpty);
  });

  test('T5 no backup → noBackup, not wrongSecret; zero PATCH', () async {
    final server = _Server();
    final h = await _device(server);
    expect(
      await h.encryption.restorePrivateKey(generateRecoveryKey()),
      RestoreResult.noBackup,
    );
    expect(server.patches, isEmpty);
  });

  test('T6 unknown version → unsupported; zero PATCH', () async {
    final server = _Server(blob: 'v9:AAAA', salt: 'AAAA');
    final h = await _device(server);
    expect(
      await h.encryption.restorePrivateKey(generateRecoveryKey()),
      RestoreResult.unsupported,
    );
    expect(server.patches, isEmpty);
  });

  test('T7 tamper: prefix stripped, or moved to another account → '
      'wrongSecret; zero PATCH', () async {
    final key = generateRecoveryKey();
    final server = _Server();
    await (await _device(server, priv: _priv)).encryption.backupPrivateKey(key);
    final blob = server.record['private_key_encrypted'] as String;
    final salt = server.record['private_key_salt'] as String;

    final stripped = _Server(blob: blob.substring(3), salt: salt);
    final h = await _device(stripped);
    expect(
      await h.encryption.restorePrivateKey(key),
      RestoreResult.wrongSecret,
    );
    expect(stripped.patches, isEmpty);

    // The same backup written by account u_other, served to u_test (AAD).
    final other = _Server();
    final s = FakeSecureStorage(userId: 'u_other');
    await s.savePrivateKey(base64.encode(_priv));
    await EncryptionService(
      s,
      (await _device(other)).pbClient,
    ).backupPrivateKey(key);
    final moved = _Server(
      blob: other.record['private_key_encrypted'] as String,
      salt: other.record['private_key_salt'] as String,
    );
    final victim = await _device(moved);
    expect(
      await victim.encryption.restorePrivateKey(key),
      RestoreResult.wrongSecret,
    );
    expect(moved.patches, isEmpty);
  });

  test('T8 interrupted re-wrap: a dropped PATCH throws, the v1 backup still '
      'opens with the PIN, the retry writes v2', () async {
    final (blob, salt) = await _v1(_priv, '123456');
    final server = _Server(blob: blob, salt: salt)..failPatch = true;
    final h = await _device(server, priv: _priv);
    final key = generateRecoveryKey();
    await expectLater(h.encryption.backupPrivateKey(key), throwsA(anything));
    expect(server.record['private_key_encrypted'], blob);
    expect(await _deviceKey(h), _priv);
    server.failPatch = false;
    final check = await _device(server);
    expect(
      await check.encryption.restorePrivateKey('123456'),
      RestoreResult.restoredLegacy,
    );

    server.patches.clear();
    await h.encryption.backupPrivateKey(key);
    expect(
      server.patches.single['private_key_encrypted'] as String,
      startsWith('v2:'),
    );
  });

  test('T9 guard: a device key that is not the published one is never '
      'backed up; empty or equal public_key writes once', () async {
    final (blob, salt) = await _v1(_priv, '123456');
    final mismatch = _Server(
      blob: blob,
      salt: salt,
      publicKey: await _pubOf(_priv),
    );
    final h = await _device(mismatch, priv: _otherPriv);
    await expectLater(
      h.encryption.backupPrivateKey(generateRecoveryKey()),
      throwsA(isA<KeyMismatchException>()),
    );
    expect(mismatch.patches, isEmpty);
    expect(mismatch.record['private_key_encrypted'], blob);

    for (final pub in ['', await _pubOf(_priv)]) {
      final server = _Server(publicKey: pub);
      await (await _device(
        server,
        priv: _priv,
      )).encryption.backupPrivateKey(generateRecoveryKey());
      expect(server.patches, hasLength(1));
    }

    await expectLater(
      h.encryption.backupPrivateKey('123456'),
      throwsA(isA<ArgumentError>()),
      reason: 'only a recovery key can lock a v2 backup',
    );
  });

  test(
    'T10 construction pinned: the committed v2 vector still opens',
    () async {
      final h = await _device(
        _Server(
          blob:
              'v2:ZGVmZ2hpamtsbW5vxHNWmAQ2KDARHH1CosGTbXhRWT1i7rK1HQEgF5BWeTe'
              'N1m1PE4x6CeN+adZkscBB',
          salt: 'AQIDBAUGBwgJCgsMDQ4PEA==',
        ),
      );
      expect(
        await h.encryption.restorePrivateKey('7KQ2M-9XHMA-4TRBC-8D1WZ-P6YVN'),
        RestoreResult.restored,
      );
      expect(await _deviceKey(h), _priv);
    },
  );

  test('backup kind: none / legacy / current, null on any error', () async {
    final (blob, salt) = await _v1(_priv, '123456');
    Future<BackupKind?> kind(_Server s) async =>
        (await _device(s)).encryption.tryGetBackupKind('u_test');
    expect(await kind(_Server()), BackupKind.none);
    expect(await kind(_Server(blob: blob, salt: salt)), BackupKind.legacy);
    expect(
      await kind(_Server(blob: 'v2:AAAA', salt: salt)),
      BackupKind.current,
    );
    final down = charHarness(
      clientFactory: () =>
          MockClient((_) async => throw http.ClientException('down')),
    );
    addTearDown(down.close);
    expect(await down.encryption.tryGetBackupKind('u_test'), isNull);
  });
}
