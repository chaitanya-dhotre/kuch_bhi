/// Key-change warning (audit F3), docs/design/pages/key-change-warning.md §4 H:
/// pin store, migration seed, security code, local lines, DM decrypt reads
/// only accepted keys, group-key walk trusts only accepted wrapper keys,
/// rotation skips a pending member.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/decrypt/decrypt_pass.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/contact_key_store.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';
import 'package:kuch_bhi/services/encryption_service.dart';
import 'package:kuch_bhi/services/security_code.dart';

import '../offline/char_harness.dart';

Future<String> _pub() async {
  final kp = await X25519().newKeyPair();
  return base64.encode((await kp.extractPublicKey()).bytes);
}

UsersTableCompanion _user(String id, String? pub) => UsersTableCompanion.insert(
  id: id,
  displayName: 'Bob',
  username: id,
  friendCode: 'F$id',
  publicKey: Value(pub),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _page(List<Object?> items) => _json({
  'page': 1,
  'perPage': 500,
  'totalItems': items.length,
  'totalPages': 1,
  'items': items,
});

void main() {
  setUp(bodyCache.clear);
  _acceptRotatesTests();

  group('pin store (A2, A5, D-14)', () {
    late AppDatabase db;
    late ContactKeyStore store;
    setUp(() async {
      db = AppDatabase.test();
      store = db.contactKeys;
      await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'me');
    });
    tearDown(() => db.close());

    test('first sight pins silently; same key is a no-op', () async {
      expect(await store.observe('bob', 'K1'), KeyObservation.firstSeen);
      expect(await store.observe('bob', 'K1'), KeyObservation.same);
      final pin = await store.get('bob');
      expect(pin!.key, 'K1');
      expect(pin.isPending, isFalse);
      expect(pin.verified, isFalse);
    });

    test('a different key goes pending, never replaces the pin', () async {
      await store.observe('bob', 'K1');
      expect(await store.observe('bob', 'K2'), KeyObservation.changed);
      expect(await store.observe('bob', 'K2'), KeyObservation.stillPending);
      final pin = await store.get('bob');
      expect(pin!.key, 'K1');
      expect(pin.pendingKey, 'K2');
      expect(pin.pendingSince, isNotNull);
    });

    test('back to the pin clears pending silently (D-14)', () async {
      await store.observe('bob', 'K1');
      await store.observe('bob', 'K2');
      expect(await store.observe('bob', 'K1'), KeyObservation.cleared);
      expect((await store.get('bob'))!.isPending, isFalse);
    });

    test('accept: pending becomes the pin, old key moves to history', () async {
      await store.observe('bob', 'K1');
      await store.setVerified('bob', true);
      await store.observe('bob', 'K2');
      expect(await store.accept('bob'), isTrue);
      final pin = (await store.get('bob'))!;
      expect(pin.key, 'K2');
      expect(pin.previousKeys, ['K1']);
      expect(pin.acceptedKeys, ['K2', 'K1']);
      expect(pin.verified, isFalse, reason: 'a change clears verified');
      expect(await store.accept('bob'), isFalse, reason: 'nothing pending');
    });

    test('an earlier accepted key coming back is still a change', () async {
      await store.observe('bob', 'K1');
      await store.observe('bob', 'K2');
      await store.accept('bob');
      expect(await store.observe('bob', 'K1'), KeyObservation.changed);
    });

    test('my own key and empty keys are ignored', () async {
      expect(await store.observe('me', 'K1'), KeyObservation.ignored);
      expect(await store.observe('bob', ''), KeyObservation.ignored);
      expect(await store.get('me'), isNull);
    });

    test('every user upsert passes the pin check (A2 funnel)', () async {
      await db.usersDao.upsertUser(_user('bob', 'K1'));
      await db.usersDao.upsertUsers([_user('bob', 'K9'), _user('cy', 'C1')]);
      expect((await store.get('bob'))!.pendingKey, 'K9');
      expect((await store.get('cy'))!.key, 'C1');
      // users.public_key keeps the server value for display only.
      expect((await db.usersDao.getUserById('bob'))!.publicKey, 'K9');
    });

    test('accepted-keys for a wrapper: me → my local key only', () async {
      await store.observe('adm', 'A1');
      expect(
        await store.keysForWrapper('adm', 'A1', myLocalKey: () async => 'L'),
        ['A1'],
      );
      expect(
        await store.keysForWrapper('adm', 'EVIL', myLocalKey: () async => 'L'),
        ['A1'],
        reason: 'a swapped wrapper key is never offered',
      );
      expect(
        await store.keysForWrapper('me', 'EVIL', myLocalKey: () async => 'L'),
        ['L'],
      );
    });
  });

  test('migration seed (F1): every cached key but mine, unverified', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    await db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'me');
    // Rows written before the pin table existed.
    await db.customStatement('DELETE FROM contact_keys');
    await db.batch(
      (b) => b.insertAll(db.usersTable, [
        _user('me', 'MINE'),
        _user('bob', 'K1'),
        _user('nokey', null),
      ]),
    );
    await db.customStatement('DELETE FROM contact_keys');
    await ContactKeyStore.seedFromUsers(db);
    expect((await db.contactKeys.get('bob'))!.key, 'K1');
    expect((await db.contactKeys.get('bob'))!.verified, isFalse);
    expect(await db.contactKeys.get('me'), isNull);
    expect(await db.contactKeys.get('nokey'), isNull);
    expect(await db.contactKeys.pending(), isEmpty, reason: 'no lines');
  });

  group('security code (D1)', () {
    test('both phones get the same 60 digits', () async {
      final a = await _pub();
      final b = await _pub();
      final mine = securityCode('alice', a, 'bob', b);
      final theirs = securityCode('bob', b, 'alice', a);
      expect(mine, theirs);
      expect(mine, matches(RegExp(r'^\d{60}$')));
      expect(securityCodeGroups(mine), hasLength(12));
    });

    test('fixed vector', () {
      final k1 = base64.encode(List<int>.generate(32, (i) => i));
      final k2 = base64.encode(List<int>.generate(32, (i) => 255 - i));
      expect(fingerprintDigits('alice', k1), hasLength(30));
      expect(
        securityCode('alice', k1, 'bob', k2),
        _vector,
        reason: 'the scheme must never drift between builds',
      );
    });

    test('a different key changes the code', () async {
      final a = await _pub();
      expect(
        securityCode('alice', a, 'bob', await _pub()),
        isNot(securityCode('alice', a, 'bob', await _pub())),
      );
    });
  });

  test('line ids carry the contact; text rebuilds from the name', () {
    final id = keyChangeLineId('abc123', 'u-u-i-d');
    expect(keyChangeLineUserId(id), 'abc123');
    expect(keyChangeLineUserId('sys_other'), isNull);
    expect(keyChangeLineUserId('local_1'), isNull);
    expect(
      keyChangeLineText('Bob'),
      "Bob's security code changed. Tap to compare.",
    );
    expect(keyChangeLineText(null), startsWith('A contact'));
  });

  group('DM decrypt reads only accepted keys (B3, D-4, A6)', () {
    test(
      'a message under a pending key stays locked, opens on accept',
      () async {
        final h = charHarness();
        addTearDown(h.close);
        await h.db.settingsDao.setSetting(
          AppSettingsKeys.currentUserId,
          'u_test',
        );
        final enc = h.encryption;
        await enc.getPublicKeyBase64(); // my key pair
        final oldPeer = await _pub();
        final newPeer = await _pub();
        final at = DateTime.utc(2026, 1, 1);
        await h.db.conversationsDao.upsertConversation(
          ConversationsTableCompanion.insert(
            id: 'd1',
            type: 'direct',
            createdById: 'u_test',
            createdAt: at,
            updatedAt: at,
          ),
        );
        for (final u in ['u_test', 'u_peer']) {
          await h.db.conversationsDao.upsertMember(
            ConversationMembersTableCompanion.insert(
              id: 'm_$u',
              conversationId: 'd1',
              userId: u,
              joinedAt: at,
            ),
          );
        }
        await h.db.contactKeys.observe('u_peer', oldPeer);
        await h.db.contactKeys.observe('u_peer', newPeer); // pending

        // The peer (or whoever holds the new key) writes under the new key.
        final newKey = await enc.getOrDeriveConversationKey('d1', newPeer);
        final sealed = await enc.encryptMessage('hi from new key', newKey);
        await h.db.messagesDao.upsertMessage(
          MessagesTableCompanion.insert(
            localId: 'r1',
            serverId: const Value('s1'),
            conversationId: 'd1',
            senderId: 'u_peer',
            type: 'text',
            encryptedBody: sealed.ciphertext,
            iv: sealed.iv,
            createdAt: at,
            updatedAt: at,
          ),
        );
        final pass = DecryptPass(db: h.db, enc: enc, epoch: () => 0);
        await pass.runFor(['r1']);
        expect(bodyCache.get('r1'), isNull, reason: 'pending key never used');

        await h.db.contactKeys.accept('u_peer');
        await pass.rerunConversation('d1');
        expect(bodyCache.get('r1'), 'hi from new key');
      },
    );
  });

  group('group-key walk trusts only accepted wrapper keys (C2)', () {
    Future<({CharHarness h, List<Map<String, Object?>> rows, String adminPub})>
    setup() async {
      final rows = <Map<String, Object?>>[];
      final client = MockClient((req) async {
        if (req.url.path.startsWith('/api/realtime')) {
          return Completer<http.Response>().future;
        }
        if (req.url.path.contains('/collections/group_keys/records')) {
          return _page(rows);
        }
        return _page(const []);
      });
      final h = charHarness(clientFactory: () => client);
      addTearDown(h.close);
      await h.db.settingsDao.setSetting(
        AppSettingsKeys.currentUserId,
        'u_test',
      );
      await h.encryption.getPublicKeyBase64();
      h.encryption.acceptedWrapperKeys = (id, serverKey) =>
          h.db.contactKeys.keysForWrapper(
            id,
            serverKey,
            myLocalKey: h.storage.getLocalPublicKey,
          );
      final adminPub = await _pub();
      await h.db.contactKeys.observe('u_admin', adminPub);
      return (h: h, rows: rows, adminPub: adminPub);
    }

    Map<String, Object?> row(int v, String env, String wrapperPub) => {
      'key_version': v,
      'encrypted_key': env,
      'encrypted_by_user_id': 'u_admin',
      'expand': {
        'encrypted_by_user_id': {'public_key': wrapperPub},
      },
    };

    test('a swapped admin key cannot hand out its own group key', () async {
      final s = await setup();
      final attacker = await _pub();
      final evilKey = s.h.encryption.generateGroupKey();
      s.rows.add(
        row(
          2,
          await s.h.encryption.encryptGroupKeyForMember(
            evilKey,
            attacker,
            'g1',
          ),
          attacker,
        ),
      );
      await expectLater(
        s.h.encryption.getOrFetchGroupKeyCandidates('g1', 'u_test'),
        throwsA(isA<MissingKeyException>()),
      );
      expect((await s.h.db.contactKeys.get('u_admin'))!.pendingKey, attacker);
    });

    test('an old wrap opens with the admin key from history', () async {
      final s = await setup();
      final newAdmin = await _pub();
      final oldKey = s.h.encryption.generateGroupKey();
      // v1 wrapped while the admin still had the old (now history) key.
      s.rows.add(
        row(
          1,
          await s.h.encryption.encryptGroupKeyForMember(
            oldKey,
            s.adminPub,
            'g1',
          ),
          newAdmin,
        ),
      );
      await s.h.db.contactKeys.observe('u_admin', newAdmin);
      await s.h.db.contactKeys.accept('u_admin');
      final cands = await s.h.encryption.getOrFetchGroupKeyCandidates(
        'g1',
        'u_test',
      );
      expect(cands.map(base64.encode), contains(base64.encode(oldKey)));
    });
  });

  test('rotation wraps to the pin and skips a pending member (C1)', () async {
    final created = <Map<String, dynamic>>[];
    final pubs = <String, String>{};
    final client = MockClient((req) async {
      final path = req.url.path;
      if (path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (path.contains('/collections/conversation_members/records')) {
        return _page([
          for (final u in ['u_test', 'u_peer', 'u_cy'])
            {'id': 'mem_$u', 'user_id': u, 'conversation_id': 'g1'},
        ]);
      }
      if (path.contains('/collections/group_keys/records')) {
        if (req.method == 'POST') {
          created.add(jsonDecode(req.body) as Map<String, dynamic>);
          return _json({'id': 'gk${created.length}'});
        }
        return _page(const []);
      }
      final m = RegExp(r'/collections/users/records/(\w+)').firstMatch(path);
      if (m != null) {
        final id = m.group(1)!;
        return _json({
          'id': id,
          'collectionName': 'users',
          'display_name': id,
          'username': id,
          'friend_code': 'F$id',
          'public_key': pubs[id] ?? '',
          'created': '2026-01-01 00:00:00.000Z',
          'updated': '2026-01-01 00:00:00.000Z',
        });
      }
      return _page(const []);
    });
    final h = charHarness(clientFactory: () => client);
    addTearDown(h.close);
    await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
    final repo = buildRepo(h);
    pubs['u_test'] = await h.encryption.getPublicKeyBase64();
    final peerPin = await _pub();
    final cyPin = await _pub();
    await h.db.contactKeys.observe('u_peer', peerPin);
    await h.db.contactKeys.observe('u_cy', cyPin);
    pubs['u_peer'] = await _pub(); // swapped on the server → pending
    pubs['u_cy'] = cyPin;

    await repo.debugRotateGroupKey('g1', 'u_test');

    final wrappedFor = created.map((b) => b['user_id']).toSet();
    expect(wrappedFor, {'u_test', 'u_cy'});
    expect((await h.db.contactKeys.get('u_peer'))!.isPending, isTrue);
  });
}

/// A6 rev (device run 2026-11-18): an admin's Accept rotates every shared
/// group, so a friend who started fresh (and still has an old-key row at the
/// current version) gets a version wrapped to the NEW key.
void _acceptRotatesTests() {
  test('admin Accept rotates the shared group to the new key (A6 rev)',
      () async {
    final created = <Map<String, dynamic>>[];
    final pubs = <String, String>{};
    final client = MockClient((req) async {
      final path = req.url.path;
      if (path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      if (path.contains('/collections/conversation_members/records')) {
        return _page([
          for (final u in ['u_test', 'u_peer'])
            {'id': 'mem_$u', 'user_id': u, 'conversation_id': 'g1'},
        ]);
      }
      if (path.contains('/collections/group_keys/records')) {
        if (req.method == 'POST') {
          created.add(jsonDecode(req.body) as Map<String, dynamic>);
          return _json({'id': 'gk${created.length}'});
        }
        // The friend already has a row at v1 (wrapped to the old key).
        return _page([
          {'key_version': 1, 'user_id': 'u_peer'},
        ]);
      }
      final m = RegExp(r'/collections/users/records/(\w+)').firstMatch(path);
      if (m != null) {
        final id = m.group(1)!;
        return _json({
          'id': id,
          'collectionName': 'users',
          'display_name': id,
          'username': id,
          'friend_code': 'F$id',
          'public_key': pubs[id] ?? '',
          'created': '2026-01-01 00:00:00.000Z',
          'updated': '2026-01-01 00:00:00.000Z',
        });
      }
      return _page(const []);
    });
    final h = charHarness(clientFactory: () => client);
    addTearDown(h.close);
    await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
    final at = DateTime.utc(2026, 1, 1);
    await h.db.conversationsDao.upsertConversation(
      ConversationsTableCompanion.insert(
        id: 'g1',
        type: 'group',
        createdById: 'u_test',
        createdAt: at,
        updatedAt: at,
      ),
    );
    for (final (u, role) in [('u_test', 'admin'), ('u_peer', 'member')]) {
      await h.db.conversationsDao.upsertMember(
        ConversationMembersTableCompanion.insert(
          id: 'm_$u',
          conversationId: 'g1',
          userId: u,
          role: Value(role),
          joinedAt: at,
        ),
      );
    }
    final repo = buildRepo(h);
    pubs['u_test'] = await h.encryption.getPublicKeyBase64();
    await h.db.contactKeys.observe('u_peer', await _pub());
    final newPeer = await _pub();
    pubs['u_peer'] = newPeer;
    await h.db.contactKeys.observe('u_peer', newPeer); // pending

    await repo.acceptContactKey('u_peer');
    expect(created, isEmpty, reason: 'Accept returns before the rotation');
    await repo.acceptRotations;

    final peerRows = created.where((b) => b['user_id'] == 'u_peer').toList();
    expect(peerRows, hasLength(1));
    expect(peerRows.single['key_version'], 2, reason: 'a NEW version');
    // The row opens with the new pin: unwrap it as the peer would.
    final transport = await h.encryption.getOrDeriveConversationKey(
      'g1_gk',
      newPeer,
    );
    final parts = (peerRows.single['encrypted_key'] as String).split(':');
    expect(
      await h.encryption.decryptMessage(parts[1], parts[0], transport),
      isNotNull,
    );
  });
}

/// Pinned by the first run of this test (spec H: a fixed test vector).
const _vector = '878952523748391029625406228657902300374106797731250666982950';
