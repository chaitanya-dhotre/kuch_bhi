/// Group-key restore speed spec G1–G6 (docs/design/pages/group-key-restore.md):
/// one walk per group when the server answered, one isolate hop per wrapper
/// key, no rewrite of unchanged slots, no walk without the device key pair,
/// `fields` on the request.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';
import 'package:kuch_bhi/services/encryption_service.dart';

import 'char_harness.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body), status,
    headers: {'content-type': 'application/json'});

http.Response _page(List<Object?> items) => _json({
      'page': 1,
      'perPage': 500,
      'totalItems': items.length,
      'totalPages': 1,
      'items': items,
    });

/// Exactly the G5 `fields` shape: no id, no other user fields.
Map<String, Object?> _row(int version, String env, String wrapperPub) => {
      'key_version': version,
      'encrypted_key': env,
      'expand': {
        'encrypted_by_user_id': {'public_key': wrapperPub},
      },
    };

/// Records every request; group_keys answers [keyRows] (or 500), messages
/// answers [messages], the member list holds me + a peer.
class _Server {
  List<Map<String, Object?>> keyRows = [];
  List<Map<String, Object?>> messages = [];
  bool failKeys = false;
  final requests = <http.Request>[];

  Iterable<http.Request> on(String collection) => requests.where(
      (r) => r.url.path.contains('/collections/$collection/records'));

  late final client = MockClient((req) async {
    final path = req.url.path;
    if (path.startsWith('/api/realtime')) {
      return Completer<http.Response>().future;
    }
    requests.add(req);
    final filter = req.url.queryParameters['filter'] ?? '';
    if (path.contains('/collections/group_keys/records')) {
      if (failKeys) return _json({'message': 'boom'}, 500);
      return _page(keyRows);
    }
    if (path.contains('/collections/messages/records')) {
      return _page(messages);
    }
    if (path.contains('/collections/conversation_members/records') &&
        filter.contains('conversation_id')) {
      return _page([
        for (final u in ['u_test', 'u_peer']) {'id': 'mem_$u', 'user_id': u},
      ]);
    }
    return _page(const []);
  });
}

Future<String> _otherPub() async {
  final kp = await X25519().newKeyPair();
  return base64.encode((await kp.extractPublicKey()).bytes);
}

/// A wrapped group key that never opens under [wrapperPub]: wrapped for an
/// unrelated key pair (the "someone's key pair changed" case).
Future<String> _deadEnv(EncryptionService enc, String strangerPub) =>
    enc.encryptGroupKeyForMember(enc.generateGroupKey(), strangerPub, 'g1');

class _Fixture {
  _Fixture(this.h, this.server, this.good);
  final CharHarness h;
  final _Server server;

  /// version → key for the rows that open.
  final Map<int, List<int>> good;
}

/// 16 rows v16..v1, wrappers alternate A (me) / B (another pub); v14 (A),
/// v9 (B) and v3 (A) open, the rest (newest included) are dead.
Future<_Fixture> _sixteenRows() async {
  final server = _Server();
  final h = charHarness(clientFactory: () => server.client);
  addTearDown(h.close);
  final enc = h.encryption;
  final a = await enc.getPublicKeyBase64(); // also creates my key pair
  final b = await _otherPub();
  final stranger = await _otherPub();
  final good = <int, List<int>>{};
  for (var v = 16; v >= 1; v--) {
    final wrapper = v.isEven ? a : b;
    if (v == 14 || v == 9 || v == 3) {
      final key = enc.generateGroupKey();
      good[v] = key;
      server.keyRows.add(
          _row(v, await enc.encryptGroupKeyForMember(key, wrapper, 'g1'), wrapper));
    } else {
      server.keyRows.add(_row(v, await _deadEnv(enc, stranger), wrapper));
    }
  }
  // Fresh install: no cached transport keys, nothing written yet.
  for (final pub in [a, b, stranger]) {
    h.storage.removeKey('contact_enc_g1_gk_$pub');
  }
  h.storage.writes.clear();
  h.storage.contactKeyReads = 0;
  return _Fixture(h, server, good);
}

List<String> _versionSlots(Iterable<String> keys) =>
    keys.where((k) => RegExp(r'^group_key_g1_\d+$').hasMatch(k)).toList()
      ..sort();

void main() {
  setUp(bodyCache.clear);

  test('gate 1 (G2): 16 rows, 2 wrappers → 1 request, 2 hops, 3 keys',
      () async {
    final f = await _sixteenRows();
    final enc = f.h.encryption;

    final cands = await enc.getOrFetchGroupKeyCandidates('g1', 'u_test');

    expect(f.server.on('group_keys'), hasLength(1));
    expect(enc.groupKeyHops, 2);
    expect(f.h.storage.contactKeyReads, lessThanOrEqualTo(2));
    expect(cands, [f.good[14], f.good[9], f.good[3]],
        reason: 'newest version first');
    expect(_versionSlots(f.h.storage.writes),
        ['group_key_g1_14', 'group_key_g1_3', 'group_key_g1_9']);
    expect(_versionSlots((await f.h.storage.readAll()).keys),
        ['group_key_g1_14', 'group_key_g1_3', 'group_key_g1_9']);
    final all = await f.h.storage.readAll();
    expect(all['group_key_g1'], base64.encode(f.good[14]!));
  });

  test('gate 2 (G3): same answer writes nothing; a new version writes only it',
      () async {
    final f = await _sixteenRows();
    final enc = f.h.encryption;
    await enc.getOrFetchGroupKeyCandidates('g1', 'u_test');

    f.h.storage.writes.clear();
    await enc.getOrFetchGroupKeyCandidates('g1', 'u_test',
        refreshFromServer: true);
    expect(f.h.storage.writes, isEmpty);

    final v17 = enc.generateGroupKey();
    final me = await enc.getPublicKeyBase64();
    f.server.keyRows.insert(
        0, _row(17, await enc.encryptGroupKeyForMember(v17, me, 'g1'), me));
    f.h.storage.writes.clear();
    final cands = await enc.getOrFetchGroupKeyCandidates('g1', 'u_test',
        refreshFromServer: true);
    expect(f.h.storage.writes.toSet(), {'group_key_g1_17', 'group_key_g1'});
    expect(cands.first, v17);
  });

  group('gate 3 (G1): history sync and a group where nothing opens', () {
    Future<(CharHarness, _Server)> signedIn() async {
      final server = _Server();
      final h = charHarness(clientFactory: () => server.client);
      addTearDown(h.close);
      await h.db.settingsDao
          .setSetting(AppSettingsKeys.currentUserId, 'u_test');
      await seedConversationAndKey(h, withKey: false);
      h.pbClient.serverClock.observe(HttpDate.format(DateTime.now()));
      final enc = h.encryption;
      final stranger = await _otherPub();
      final me = await enc.getPublicKeyBase64();
      for (var v = 4; v >= 1; v--) {
        server.keyRows.add(_row(v, await _deadEnv(enc, stranger), me));
      }
      final lost = enc.generateGroupKey();
      for (var i = 0; i < 3; i++) {
        final c = await enc.encryptMessage('hi $i', lost);
        final at = DateTime.utc(2026, 7, 21, 10, i).toIso8601String();
        server.messages.add({
          'id': 'm$i',
          'collectionId': 'messages',
          'collectionName': 'messages',
          'created': at,
          'updated': at,
          'conversation_id': 'g1',
          'sender_id': 'u_peer',
          'type': 'text',
          'encrypted_body': c.ciphertext,
          'iv': c.iv,
          'reply_to_id': '',
          'is_deleted_for_everyone': false,
          'is_pinned': false,
          'media_id': '',
          'disappear_after': 0,
          'expires_at': '',
        });
      }
      return (h, server);
    }

    test('server answered, nothing opens → 1 walk, rows land key_missing',
        () async {
      final (h, server) = await signedIn();
      final sw = Stopwatch()..start();
      await buildRepo(h).syncAllHistory();
      // One request means the loop never reached its 400/800 ms sleeps
      // (each sleep is followed by another walk).
      expect(server.on('group_keys'), hasLength(1));
      expect(sw.elapsedMilliseconds, lessThan(1200));
      for (var i = 0; i < 3; i++) {
        final row = await h.db.messagesDao.getMessageByServerId('m$i');
        expect(row?.decryptState, 'key_missing', reason: 'm$i');
      }
    });

    test('group_keys request fails → still 3 tries', () async {
      final (h, server) = await signedIn();
      server.failKeys = true;
      await buildRepo(h).syncAllHistory();
      expect(server.on('group_keys'), hasLength(3));
      final row = await h.db.messagesDao.getMessageByServerId('m0');
      expect(row?.decryptState, 'key_missing');
    });
  });

  group('gate 4 (G4): no device key pair', () {
    test('getOrFetchGroupKeyCandidates makes no request', () async {
      final server = _Server();
      final h = charHarness(clientFactory: () => server.client);
      addTearDown(h.close);

      final err = await h.encryption
          .getOrFetchGroupKeyCandidates('g1', 'u_test')
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(err, isA<MissingKeyException>());
      expect(err, isNot(isA<NoGroupKeyException>()));
      expect(server.on('group_keys'), isEmpty);
    });

    test('with a cached key, a failed request still falls back to it',
        () async {
      final server = _Server()..failKeys = true;
      final h = charHarness(clientFactory: () => server.client);
      addTearDown(h.close);
      h.storage.put('group_key_g1', base64.encode(fixtureGroupKey));

      final cands = await h.encryption.getOrFetchGroupKeyCandidates(
          'g1', 'u_test',
          requireCurrent: true);
      expect(cands, [fixtureGroupKey]);
    });

    test('prefetchGroupKeys makes no request', () async {
      final server = _Server();
      final h = charHarness(clientFactory: () => server.client);
      addTearDown(h.close);
      await h.db.settingsDao
          .setSetting(AppSettingsKeys.currentUserId, 'u_test');
      await seedConversationAndKey(h, withKey: false);

      await buildRepo(h).prefetchGroupKeys();
      expect(server.on('group_keys'), isEmpty);
    });
  });

  test('gate 5 (G5): request carries fields; a fields-only answer opens',
      () async {
    final f = await _sixteenRows();
    final cands =
        await f.h.encryption.getOrFetchGroupKeyCandidates('g1', 'u_test');
    expect(f.server.on('group_keys').single.url.queryParameters['fields'],
        // F3 C2: the wrapper id rides along so the pin can be checked.
        'key_version,encrypted_key,encrypted_by_user_id,'
        'expand.encrypted_by_user_id.public_key');
    expect(cands, hasLength(3));
  });

  test('gate 6: requireCurrent with the newest version dead still throws',
      () async {
    final f = await _sixteenRows(); // v16 is dead, v14 opens
    final err = await f.h.encryption
        .getOrFetchGroupKeyCandidates('g1', 'u_test', requireCurrent: true)
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(err, isA<MissingKeyException>());
    await expectLater(f.h.encryption.getOrFetchGroupKey('g1', 'u_test'),
        throwsA(isA<MissingKeyException>()));
  });
}
