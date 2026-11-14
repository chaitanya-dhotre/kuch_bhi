/// Restore rev 2 (docs/design/pages/restore-rev2.md) gates 1–4 and 6–16:
/// offline pause and retry rounds (R1), the conversations step in 2 requests
/// (R2), no join rotation on first sight (R3), one key walk per group (R4),
/// one round trip per chat (R5). Gate 5 is in test/auth/restore_overlay_test.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/services/encryption_service.dart';

import 'char_harness.dart';

const _me = 'u_test';
final _at = DateTime.utc(2026, 7, 21, 10);

http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body), status,
    headers: {'content-type': 'application/json'});

/// Pages [items] the way PocketBase does.
http.Response _page(http.Request req, List<Object?> items) {
  final q = req.url.queryParameters;
  final page = int.tryParse(q['page'] ?? '') ?? 1;
  final perPage = int.tryParse(q['perPage'] ?? '') ?? 30;
  final skip = q['skipTotal'] == 'true' || q['skipTotal'] == '1';
  return _json({
    'page': page,
    'perPage': perPage,
    'totalItems': skip ? -1 : items.length,
    'totalPages': skip ? -1 : (items.length / perPage).ceil(),
    'items': items.skip((page - 1) * perPage).take(perPage).toList(),
  });
}

Map<String, Object?> _msg(String conv, int i, {bool mine = false}) {
  final at = _at.subtract(Duration(minutes: i)).toIso8601String();
  return {
    'id': '${conv}_m$i',
    'collectionId': 'messages',
    'collectionName': 'messages',
    'created': at,
    'updated': at,
    'conversation_id': conv,
    'sender_id': mine ? _me : 'u_peer',
    'type': 'text',
    'encrypted_body': '', // no decrypt hop; the row still lands
    'iv': '',
    'reply_to_id': '',
    'is_deleted_for_everyone': false,
    'is_pinned': false,
    'media_id': '',
    'disappear_after': 0,
    'expires_at': '',
  };
}

/// One request as the server saw it, with its arrival time.
class _Req {
  _Req(this.req, this.ms);
  final http.Request req;
  final int ms;
  String get path => req.url.path;
  String get filter => req.url.queryParameters['filter'] ?? '';
  bool on(String collection) =>
      path.contains('/collections/$collection/records');
}

/// A small PocketBase: [convs] group chats I am in, [others] members per
/// chat, [messages] per chat, user-wide deleted / starred lists. [hook] runs
/// first and may answer (or throw) instead.
class _Server {
  _Server(this.convs, {this.others = const {}, this.messages = const {}});
  final List<String> convs;
  Map<String, List<String>> others;
  final Map<String, List<Map<String, Object?>>> messages;
  Map<String, List<Map<String, Object?>>> receipts = {};
  Map<String, String> roles = {}; // conv → my role
  List<Map<String, Object?>> keyRows = [];
  List<String> deletedForMe = [];
  List<String> starred = [];
  String publicKey = '';
  Duration delay = Duration.zero;
  FutureOr<http.Response?> Function(http.Request req)? hook;
  final log = <_Req>[];
  final clock = Stopwatch()..start();

  Iterable<_Req> on(String c) => log.where((r) => r.on(c));

  static final _convRe = RegExp(r'conversation_id="([^"]+)"');

  Map<String, Object?> _convRecord(int i) => {
        'id': convs[i],
        'collectionName': 'conversations',
        'type': 'group',
        'name': 'Chat $i',
        'icon': '',
        'created_by': _me,
        'only_admins_can_message': false,
        'disappearing_duration': 0,
        // Newest first: chat order on the phone = list order here.
        'last_message_at':
            _at.subtract(Duration(hours: i)).toIso8601String(),
        'created': '2026-01-01T00:00:00.000Z',
      };

  Map<String, Object?> _member(String conv, String user) => {
        'id': 'mem_${conv}_$user',
        'collectionName': 'conversation_members',
        'conversation_id': conv,
        'user_id': user,
        'role': user == _me ? (roles[conv] ?? 'member') : 'member',
        'joined_at': '2026-01-01T00:00:00.000Z',
        'created': '2026-01-01T00:00:00.000Z',
        if (user != _me)
          'expand': {
            'user_id': {
              'id': user,
              'collectionName': 'users',
              'username': user,
              'display_name': 'User $user',
              'public_key': publicKey,
              'created': '2026-01-01T00:00:00.000Z',
              'updated': '2026-01-01T00:00:00.000Z',
            },
          },
      };

  late final client = MockClient((req) async {
    if (req.url.path.startsWith('/api/realtime')) {
      return Completer<http.Response>().future;
    }
    log.add(_Req(req, clock.elapsedMilliseconds));
    final hooked = await hook?.call(req);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (hooked != null) return hooked;
    final path = req.url.path;
    final filter = req.url.queryParameters['filter'] ?? '';
    final ids = [for (final m in _convRe.allMatches(filter)) m.group(1)!];
    if (path.contains('/collections/conversation_members/records')) {
      if (filter == 'user_id="$_me"') {
        return _page(req, [
          for (var i = 0; i < convs.length; i++)
            {
              ..._member(convs[i], _me),
              'expand': {'conversation_id': _convRecord(i)},
            },
        ]);
      }
      if (filter.contains('user_id!="$_me"')) {
        return _page(req, [
          for (final c in ids)
            for (final u in others[c] ?? const <String>[]) _member(c, u),
        ]);
      }
      // A probe or a full member list of one chat.
      final c = ids.first;
      return _page(req, [
        for (final u in [_me, ...?others[c]])
          if (!filter.contains('user_id="') || filter.contains('"$u"'))
            _member(c, u),
      ]);
    }
    if (path.contains('/collections/users/records/')) {
      final id = path.split('/').last;
      return _json({'id': id, 'collectionName': 'users', 'public_key': publicKey});
    }
    if (path.contains('/collections/messages/records')) {
      return _page(req, messages[ids.first] ?? const []);
    }
    if (path.contains('/collections/message_receipts/records')) {
      return _page(req, receipts[ids.first] ?? const []);
    }
    if (path.contains('/collections/group_keys/records')) {
      if (req.method == 'POST') return _json({'id': 'gk'});
      return _page(req, keyRows);
    }
    if (path.contains('/collections/deleted_messages_for_me/records')) {
      return _page(req, [
        for (final id in deletedForMe) {'id': 'd_$id', 'message_id': id},
      ]);
    }
    if (path.contains('/collections/starred_messages/records')) {
      return _page(req, [
        for (final id in starred) {'id': 's_$id', 'message_id': id},
      ]);
    }
    return _page(req, const []);
  });
}

/// A dropped connection: the SDK reports it as statusCode 0.
Never _drop() => throw http.ClientException('Failed host lookup');

class _FakeConnectivity implements Connectivity {
  final _changes = StreamController<List<ConnectivityResult>>.broadcast();
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];
  void goOnline() => _changes.add([ConnectivityResult.wifi]);
  void goOffline() => _changes.add([ConnectivityResult.none]);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Signed in, my key pair on the phone, nothing else local (fresh install).
Future<CharHarness> _fresh(_Server server) async {
  final h = charHarness(clientFactory: () => server.client);
  addTearDown(h.close);
  await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, _me);
  h.pbClient.serverClock.observe(HttpDate.format(DateTime.now()));
  server.publicKey = await h.encryption.getPublicKeyBase64();
  return h;
}

/// [n] chats c0..c{n-1}, [per] messages each from the peer.
_Server _chats(int n, {int per = 3}) {
  final convs = [for (var i = 0; i < n; i++) 'c$i'];
  return _Server(convs, messages: {
    for (final c in convs) c: [for (var i = 0; i < per; i++) _msg(c, i)],
  });
}

Future<int> _rows(CharHarness h, String conv) async =>
    (await h.db.messagesDao.watchMessages(conv).first).length;

/// The conversation a request is about (messages, receipts, keys).
String? _convOf(http.Request req) => _Server._convRe
    .firstMatch(req.url.queryParameters['filter'] ?? '')
    ?.group(1);

Future<String> _otherPub() async {
  final kp = await X25519().newKeyPair();
  return base64.encode((await kp.extractPublicKey()).bytes);
}

void main() {
  setUp(bodyCache.clear);

  group('R1', () {
    test('gate 1: offline from chat 3 → waitingForNetwork, chatsLeft 3; '
        'back online → chats 3–5 land once, then complete', () async {
      final server = _chats(5);
      final h = await _fresh(server);
      final net = _FakeConnectivity();
      final signal = ConnectivitySignal(connectivity: net);
      addTearDown(signal.dispose);
      final seen = <String>{};
      var down = false;
      var tripped = false;
      server.hook = (req) async {
        if (req.url.path.contains('/collections/messages/records')) {
          seen.add(_convOf(req)!);
          if (seen.length == 3 && !tripped) {
            tripped = true;
            down = true;
            net.goOffline();
            await Future<void>.delayed(Duration.zero); // signal hears it
          }
        }
        if (down) _drop();
        return null;
      };
      final waiting = Completer<HistorySyncProgress>();
      var completes = 0;
      final sync = buildRepo(h).syncAllHistory(
        net: signal,
        onProgress: (p) {
          if (p.phase == HistorySyncPhase.waitingForNetwork &&
              !waiting.isCompleted) {
            waiting.complete(p);
          }
          if (p.phase == HistorySyncPhase.complete) completes++;
        },
      );
      final p = await waiting.future;
      expect(p.chatsLeft, 3);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(completes, 0, reason: 'no time limit while offline');

      down = false;
      net.goOnline();
      await sync;
      expect(completes, 1);
      for (final c in server.convs) {
        expect(await _rows(h, c), 3, reason: '$c: landed once');
      }
    });

    test('gate 2: online but failing → the chat lands in round 2', () async {
      final server = _chats(3);
      final h = await _fresh(server);
      final signal = ConnectivitySignal(connectivity: _FakeConnectivity());
      addTearDown(signal.dispose);
      var fails = 0;
      server.hook = (req) {
        if (req.url.path.contains('/collections/messages/records') &&
            _convOf(req) == 'c1' &&
            fails < 2) {
          fails++;
          _drop();
        }
        return null;
      };
      final repo = buildRepo(h)
        ..historyRetryGap = const Duration(milliseconds: 20);
      var completes = 0;
      await repo.syncAllHistory(
        net: signal,
        onProgress: (p) {
          if (p.phase == HistorySyncPhase.complete) completes++;
        },
      );
      expect(fails, 2);
      expect(
          server.on('messages').where((r) => _convOf(r.req) == 'c1'), hasLength(3));
      expect(await _rows(h, 'c1'), 3);
      expect(completes, 1);
    });

    test('gate 3: a refused chat (403) is not retried', () async {
      final server = _chats(3);
      final h = await _fresh(server);
      final signal = ConnectivitySignal(connectivity: _FakeConnectivity());
      addTearDown(signal.dispose);
      server.hook = (req) =>
          req.url.path.contains('/collections/messages/records') &&
                  _convOf(req) == 'c1'
              ? _json({'message': 'forbidden'}, 403)
              : null;
      final repo = buildRepo(h)
        ..historyRetryGap = const Duration(milliseconds: 20);
      var completes = 0;
      await repo.syncAllHistory(
        net: signal,
        onProgress: (p) {
          if (p.phase == HistorySyncPhase.complete) completes++;
        },
      );
      expect(
          server.on('messages').where((r) => _convOf(r.req) == 'c1'), hasLength(1));
      expect(await _rows(h, 'c0'), 3);
      expect(await _rows(h, 'c2'), 3);
      expect(completes, 1);
    });

    test('gate 4: no signal → a dropped chat is skipped as before', () async {
      final server = _chats(3);
      final h = await _fresh(server);
      server.hook = (req) {
        if (req.url.path.contains('/collections/messages/records') &&
            _convOf(req) == 'c1') {
          _drop();
        }
        return null;
      };
      var completes = 0;
      await buildRepo(h).syncAllHistory(onProgress: (p) {
        if (p.phase == HistorySyncPhase.complete) completes++;
        expect(p.phase, isNot(HistorySyncPhase.waitingForNetwork));
      });
      expect(
          server.on('messages').where((r) => _convOf(r.req) == 'c1'), hasLength(1));
      expect(await _rows(h, 'c1'), 0);
      expect(await _rows(h, 'c2'), 3);
      expect(completes, 1);
    });

    test('gate 16: a 429 on page 1 → left, lands in a retry round', () async {
      final server = _chats(3);
      final h = await _fresh(server);
      final signal = ConnectivitySignal(connectivity: _FakeConnectivity());
      addTearDown(signal.dispose);
      var limited = false;
      server.hook = (req) {
        if (req.url.path.contains('/collections/messages/records') &&
            _convOf(req) == 'c2' &&
            !limited) {
          limited = true;
          return _json({'message': 'Too Many Requests.'}, 429);
        }
        return null;
      };
      final repo = buildRepo(h)
        ..historyRetryGap = const Duration(milliseconds: 20);
      await repo.syncAllHistory(net: signal);
      expect(
          server.on('messages').where((r) => _convOf(r.req) == 'c2'), hasLength(2));
      expect(await _rows(h, 'c2'), 3);
    });
  });

  group('R2', () {
    Future<void> members(int n, int expectedRequests) async {
      final convs = [for (var i = 0; i < n; i++) 'c$i'];
      final server = _Server(convs, others: {
        for (final c in convs) c: ['u_${c}_a', 'u_${c}_b'],
      });
      final h = await _fresh(server);
      await buildRepo(h).debugSyncConversations();

      expect(server.on('conversation_members'), hasLength(expectedRequests));
      for (final c in convs) {
        final rows = await h.db.conversationsDao.getAllMembersForConversation(c);
        expect(
            {for (final r in rows) (r.id, r.userId, r.role)},
            {
              ('mem_${c}_$_me', _me, 'member'),
              ('mem_${c}_u_${c}_a', 'u_${c}_a', 'member'),
              ('mem_${c}_u_${c}_b', 'u_${c}_b', 'member'),
            },
            reason: c);
        for (final u in ['u_${c}_a', 'u_${c}_b']) {
          final user = await h.db.usersDao.getUserById(u);
          expect(user?.publicKey, server.publicKey, reason: u);
        }
      }
    }

    test('gate 6: 26 chats × 3 members → 2 requests', () => members(26, 2));
    test('gate 6: 45 chats → 3 requests', () => members(45, 3));

    test('gate 6: every member filter stays under the 3500-char cap', () async {
      final convs = [for (var i = 0; i < 45; i++) 'abcdefghij${i + 10000}'];
      final server = _Server(convs);
      final h = await _fresh(server);
      await buildRepo(h).debugSyncConversations();
      for (final r in server.on('conversation_members')) {
        expect(r.filter.length, lessThan(3500));
      }
    });

    test('gate 7: three calls during one pass → 2 passes, no overlap',
        () async {
      final server = _chats(3)..delay = const Duration(milliseconds: 40);
      final h = await _fresh(server);
      final repo = buildRepo(h);
      final first = repo.debugSyncConversations();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final more = [for (var i = 0; i < 3; i++) repo.debugSyncConversations()];
      await Future.wait([first, ...more]);

      final list = server.on('conversation_members').toList();
      final memberships =
          [for (var i = 0; i < list.length; i++) if (list[i].filter == 'user_id="$_me"') i];
      expect(memberships, hasLength(2));
      // Pass 2's list comes after pass 1's member request (no overlap).
      final pass1Members = list.indexWhere((r) => r.filter.contains('user_id!='));
      expect(pass1Members, greaterThan(memberships.first));
      expect(memberships.last, greaterThan(pass1Members));
    });

    test('gate 8: 35 memberships → all 35 chats stored', () async {
      final server = _chats(35);
      final h = await _fresh(server);
      await buildRepo(h).debugSyncConversations();
      final convs = await h.db.conversationsDao.watchAllConversations().first;
      expect(convs, hasLength(35));
    });
  });

  group('R3', () {
    test('gate 9: fresh install, admin of a group of 4 → no rotation',
        () async {
      final server = _Server(['g'], others: {
        'g': ['u_x', 'u_y', 'u_z'],
      })
        ..roles = {'g': 'admin'};
      final h = await _fresh(server);
      await buildRepo(h).debugSyncConversations();
      await Future<void>.delayed(const Duration(milliseconds: 3400));
      expect(server.on('group_keys').where((r) => r.req.method == 'POST'),
          isEmpty);
    });

    test('gate 9: a member added to a group the phone knew → rotates',
        () async {
      final server = _Server(['g'], others: {
        'g': ['u_x', 'u_y'],
      })
        ..roles = {'g': 'admin'};
      final h = await _fresh(server);
      final repo = buildRepo(h);
      server.others = {'g': ['u_x']};
      await repo.debugSyncConversations(); // the phone knows g: me + u_x
      server.others = {'g': ['u_x', 'u_y']};
      await repo.debugSyncConversations(); // u_y is new
      await Future<void>.delayed(const Duration(milliseconds: 3400));
      expect(server.on('group_keys').where((r) => r.req.method == 'POST'),
          hasLength(3), reason: 'one wrapped key per member');
    });
  });

  group('R4', () {
    /// v2 dead, v1 opens (wrapped for me).
    Future<(CharHarness, _Server, List<int>)> keys() async {
      final server = _Server(const [])..delay = const Duration(milliseconds: 50);
      final h = charHarness(clientFactory: () => server.client);
      addTearDown(h.close);
      final enc = h.encryption;
      final me = await enc.getPublicKeyBase64();
      final good = enc.generateGroupKey();
      Map<String, Object?> row(int v, String env) => {
            'key_version': v,
            'encrypted_key': env,
            'expand': {
              'encrypted_by_user_id': {'public_key': me},
            },
          };
      server.keyRows = [
        row(2, await enc.encryptGroupKeyForMember(
            enc.generateGroupKey(), await _otherPub(), 'g1')),
        row(1, await enc.encryptGroupKeyForMember(good, me, 'g1')),
      ];
      return (h, server, good);
    }

    test('gate 10: two callers of a cold group share 1 walk; '
        'requireCurrent joining a dead-newest walk still throws', () async {
      final (h, server, good) = await keys();
      final enc = h.encryption;
      final a = enc.getOrFetchGroupKeyCandidates('g1', _me);
      final b = enc.getOrFetchGroupKeyCandidates('g1', _me);
      final current = enc
          .getOrFetchGroupKeyCandidates('g1', _me, requireCurrent: true)
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(await a, [good]);
      expect(await b, [good]);
      expect(await current, isA<MissingKeyException>());
      expect(server.on('group_keys'), hasLength(1));
    });

    test('gate 11: refresh inside 60 s → 0 requests; after 61 s → 1; '
        'send inside the window → 1', () async {
      final (h, server, good) = await keys();
      final enc = h.encryption;
      var now = DateTime.utc(2026, 11, 14, 12);
      enc.now = () => now;
      await enc.getOrFetchGroupKeyCandidates('g1', _me); // the good walk
      expect(server.on('group_keys'), hasLength(1));

      now = now.add(const Duration(seconds: 30));
      expect(await enc.getOrFetchGroupKeyCandidates('g1', _me), [good]);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(server.on('group_keys'), hasLength(1), reason: 'inside window');

      now = now.add(const Duration(seconds: 31)); // 61 s after the walk
      await enc.getOrFetchGroupKeyCandidates('g1', _me);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(server.on('group_keys'), hasLength(2), reason: 'window over');

      // Send path inside the new window: never skipped.
      server.keyRows.removeAt(0); // newest opens now
      await enc.getOrFetchGroupKeyCandidates('g1', _me, requireCurrent: true);
      expect(server.on('group_keys'), hasLength(3));
    });

    test('gate 12: prefetchGroupKeys during syncAllHistory → 0 requests',
        () async {
      final server = _chats(1);
      final h = await _fresh(server);
      final repo = buildRepo(h);
      final release = Completer<void>();
      server.hook = (req) async {
        if (req.url.path.contains('/collections/messages/records')) {
          await release.future;
        }
        return null;
      };
      final sync = repo.syncAllHistory();
      // The sync's own walk answers (no rows: the group stays cold) while
      // page 1 is held.
      while (server.on('group_keys').isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.prefetchGroupKeys();
      release.complete();
      await sync;
      expect(server.on('group_keys'), hasLength(1), reason: 'the sync only');

      await repo.prefetchGroupKeys(); // after the sync: it walks again
      expect(server.on('group_keys'), hasLength(2));
    });
  });

  group('R5', () {
    test('gate 13: key, receipts and page 1 leave before any answer',
        () async {
      final server = _Server(['g'], others: {
        'g': ['u_peer'],
      }, messages: {
        'g': [
          for (var i = 0; i < 6; i++) _msg('g', i, mine: i.isEven),
        ],
      })
        ..receipts = {
          'g': [
            {
              'id': 'r0',
              'message_id': 'g_m0',
              'recipient_id': 'u_peer',
              'delivered_at': 'x',
              'read_at': 'x',
              'updated': _at.toIso8601String(),
            },
            {
              'id': 'r2',
              'message_id': 'g_m2',
              'recipient_id': 'u_peer',
              'delivered_at': 'x',
              'read_at': '',
              'updated': _at.toIso8601String(),
            },
          ],
        };
      final h = await _fresh(server);
      final repo = buildRepo(h);
      await repo.debugSyncConversations();
      server.log.clear();
      server.delay = const Duration(milliseconds: 300);
      await repo.syncAllHistory();

      final chat = [
        server.on('group_keys').first,
        server.on('message_receipts').first,
        server.on('messages').first,
      ];
      // The chat's first request is answered 300 ms after it left.
      final firstAnswer = chat.map((r) => r.ms).reduce((a, b) => a < b ? a : b) + 300;
      for (final r in chat) {
        expect(r.ms, lessThan(firstAnswer), reason: r.path);
      }
      Future<String?> status(String id) async =>
          (await h.db.messagesDao.getMessageByServerId(id))?.status;
      expect(await status('g_m0'), 'read');
      expect(await status('g_m2'), 'delivered');
      expect(await status('g_m4'), 'sent');
      expect(await _rows(h, 'g'), 6);
    });

    test('gate 14: no member request after the conversations pass; a 3-member '
        'group still needs both receipts for read', () async {
      Map<String, Object?> read(String msg, String to) => {
            'id': 'r_${msg}_$to',
            'message_id': msg,
            'recipient_id': to,
            'delivered_at': 'x',
            'read_at': 'x',
            'updated': _at.toIso8601String(),
          };
      final server = _Server(['g'], others: {
        'g': ['u_a', 'u_b'],
      }, messages: {
        'g': [_msg('g', 0, mine: true), _msg('g', 1, mine: true)],
      })
        ..receipts = {
          'g': [read('g_m0', 'u_a'), read('g_m0', 'u_b'), read('g_m1', 'u_a')],
        };
      final h = await _fresh(server);
      await buildRepo(h).syncAllHistory();
      expect(server.on('conversation_members'), hasLength(2),
          reason: 'memberships + one member list; none per chat');
      expect((await h.db.messagesDao.getMessageByServerId('g_m0'))?.status,
          'read');
      expect((await h.db.messagesDao.getMessageByServerId('g_m1'))?.status,
          'sent', reason: 'u_b has no receipt');
    });

    test('gate 15: deleted and starred once for the account, after the last '
        'chat; chat 4 rows flagged at complete', () async {
      final server = _chats(5)
        ..deletedForMe = ['c3_m0']
        ..starred = ['c3_m1'];
      final h = await _fresh(server);
      MessagesTableData? deleted;
      MessagesTableData? starred;
      await buildRepo(h).syncAllHistory(onProgress: (p) async {
        if (p.phase != HistorySyncPhase.complete) return;
        deleted = await h.db.messagesDao.getMessageByServerId('c3_m0');
        starred = await h.db.messagesDao.getMessageByServerId('c3_m1');
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final dels = server.on('deleted_messages_for_me').toList();
      final stars = server.on('starred_messages').toList();
      expect(dels, hasLength(1));
      expect(stars, hasLength(1));
      final lastPage = server.log.lastIndexWhere((r) => r.on('messages'));
      expect(server.log.indexOf(dels.single), greaterThan(lastPage));
      expect(server.log.indexOf(stars.single), greaterThan(lastPage));
      expect(deleted?.isDeletedForMe, isTrue);
      expect(starred?.isStarred, isTrue);
    });
  });
}
