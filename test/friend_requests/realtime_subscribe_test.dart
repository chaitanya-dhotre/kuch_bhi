import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/network/realtime_subscribe.dart';
import 'package:pocketbase/pocketbase.dart';

/// The realtime subscribe helper must:
/// 1. Time out instead of hanging when the handshake never completes
///    (PocketBase's SSE client retries forever).
/// 2. Register a SCOPED dispose func — never a topic-less collection
///    unsubscribe that would remove a sibling screen's listener.
/// 3. Drop an orphaned listener when the caller abandons the subscribe and
///    is gone by the time the handshake eventually lands.
void main() {
  late _FakeRealtimeServer server;
  late PocketBase pb;

  setUp(() async {
    server = await _FakeRealtimeServer.start();
    pb = PocketBase(server.url);
  });

  tearDown(() async {
    await server.close();
  });

  test('the helper resolves (times out) when the handshake never lands',
      () async {
    // A server that accepts the connection but never sends PB_CONNECT.
    final silent = await _FakeRealtimeServer.start(handshake: false);
    addTearDown(silent.close);
    final silentPb = PocketBase(silent.url);

    final disposers = <void Function()>[];
    final result = await subscribeWithTimeout(
      silentPb,
      'friend_requests',
      () {},
      disposers.add,
      timeout: const Duration(milliseconds: 200),
    );

    expect(result, isNull, reason: 'a timed-out subscribe yields no handle');
    // A disposer IS registered: PocketBase registers the listener before the
    // handshake, so the orphan must be removable — otherwise it would keep
    // firing into a dead provider.
    expect(
      disposers.length,
      1,
      reason: 'the timed-out listener must still be disposable',
    );
  });

  test('a successful subscribe registers a scoped dispose func', () async {
    final disposers = <void Function()>[];
    final handle = await subscribeWithTimeout(
      pb,
      'friend_requests',
      () {},
      disposers.add,
    );

    expect(handle, isNotNull);
    expect(disposers.length, 1);

    // The registered dispose must remove ONLY this listener — a sibling on
    // the same collection must survive it.
    var siblingCalls = 0;
    await pb.collection('friend_requests').subscribe('*', (_) => siblingCalls++);

    for (final d in disposers) {
      d();
    }
    // The scoped unsubscribe is async — let it settle before emitting.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    server.emit('friend_requests', {'action': 'create'});
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(
      siblingCalls,
      1,
      reason: 'the scoped dispose must not remove a sibling listener',
    );
  });

  test('a stale generation does not drop a LIVE provider\'s listener',
      () async {
    // Riverpod REUSES a notifier instance across `invalidateSelf`, so an
    // "abandoned" flag stored in a field stays `true` after the first
    // rebuild. If the helper trusted such a flag it would drop the listener
    // of a LIVE provider — re-creating the R1 symptom (no live updates).
    //
    // The handshake lands LATE (after the helper's timeout) while the
    // caller's generation is CURRENT: the listener must be ADOPTED
    // (registered for disposal), not dropped.
    final slow = await _FakeRealtimeServer.start(
      handshakeDelay: const Duration(milliseconds: 400),
    );
    addTearDown(slow.close);
    final slowPb = PocketBase(slow.url);

    var generation = 1;
    final disposers = <void Function()>[];

    final handle = await subscribeWithTimeout(
      slowPb,
      'friend_requests',
      () {},
      disposers.add,
      isAbandoned: () => generation != 1,
      timeout: const Duration(milliseconds: 100),
    );
    expect(handle, isNull, reason: 'the handshake had not landed yet');

    // The handshake lands; the provider is still the CURRENT generation.
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(
      disposers.length,
      1,
      reason: 'a live provider must keep (adopt) its listener — dropping it '
          're-creates the R1 symptom',
    );

    // And the adopted listener actually delivers events.
    var calls = 0;
    await slowPb.collection('friend_requests').subscribe('*', (_) => calls++);
    slow.emit('friend_requests', {'action': 'create'});
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(calls, 1);
  });

  test('a listener that materialises after the caller is gone is dropped',
      () async {
    // A server that delays the PB_CONNECT handshake: the subscribe times
    // out first, and PocketBase has ALREADY registered the listener. The
    // caller is gone by the time the handshake lands, so the orphaned
    // listener must be dropped — not left firing into a dead provider.
    final slow = await _FakeRealtimeServer.start(
      handshakeDelay: const Duration(milliseconds: 700),
    );
    addTearDown(slow.close);
    final slowPb = PocketBase(slow.url);

    final disposers = <void Function()>[];
    var abandoned = true;

    final handle = await subscribeWithTimeout(
      slowPb,
      'friend_requests',
      () {},
      disposers.add,
      isAbandoned: () => abandoned,
      timeout: const Duration(milliseconds: 100),
    );
    expect(handle, isNull, reason: 'the handshake had not landed yet');

    // The caller goes away while the handshake is still in flight.
    abandoned = true;

    // Let the handshake land, then check the orphan was dropped.
    await Future<void>.delayed(const Duration(milliseconds: 900));

    var calls = 0;
    await slowPb.collection('friend_requests').subscribe('*', (_) => calls++);
    slow.emit('friend_requests', {'action': 'create'});
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(
      calls,
      1,
      reason: 'only the fresh sibling may receive the event — the orphaned '
          'listener must be dropped',
    );
  });
}

/// Minimal SSE server speaking PocketBase's realtime protocol.
class _FakeRealtimeServer {
  _FakeRealtimeServer._(this._server, this._sessions);

  static Future<_FakeRealtimeServer> start({
    bool handshake = true,
    Duration handshakeDelay = Duration.zero,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sessions = <_SseSession>[];

    server.listen((request) async {
      if (request.method == 'POST') {
        await request.drain();
        request.response
          ..statusCode = 204
          ..close();
        return;
      }
      request.response.headers.contentType =
          ContentType('text', 'event-stream');
      request.response.bufferOutput = false;
      final session = _SseSession(request.response);
      sessions.add(session);
      if (handshake) {
        if (handshakeDelay > Duration.zero) {
          Timer(handshakeDelay, () {
            session.send({
              'id': 'test-client-1',
              'event': 'PB_CONNECT',
              'data': jsonEncode({'clientId': 'test-client-1'}),
            });
          });
        } else {
          session.send({
            'id': 'test-client-1',
            'event': 'PB_CONNECT',
            'data': jsonEncode({'clientId': 'test-client-1'}),
          });
        }
      }
    });

    return _FakeRealtimeServer._(server, sessions);
  }

  final HttpServer _server;
  final List<_SseSession> _sessions;

  String get url => 'http://127.0.0.1:${_server.port}';

  void emit(String collection, Map<String, dynamic> record) {
    for (final s in _sessions) {
      s.send({
        'id': 'evt-${_sessions.length}',
        'event': '$collection/*',
        'data': jsonEncode(record),
      });
    }
  }

  Future<void> close() async {
    for (final s in _sessions) {
      s.close();
    }
    await _server.close(force: true);
  }
}

class _SseSession {
  _SseSession(this._response);

  final HttpResponse _response;

  void send(Map<String, String> frame) {
    final buffer = StringBuffer();
    frame.forEach((k, v) => buffer.write('$k: $v\n'));
    buffer.write('\n');
    try {
      _response.add(utf8.encode(buffer.toString()));
    } catch (_) {
      // Connection already closed.
    }
  }

  void close() {
    try {
      _response.close();
    } catch (_) {
      // Already closed.
    }
  }
}
