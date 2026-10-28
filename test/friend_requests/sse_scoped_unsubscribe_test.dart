import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

/// R1 regression: a scoped unsubscribe must remove ONLY its own listener.
///
/// The bug: `pb.collection('friend_requests').unsubscribe()` (no topic) maps
/// to PocketBase's `realtime.unsubscribeByPrefix`, which removes EVERY
/// listener registered on `friend_requests/*` — including the one owned by
/// `FriendQueryService` (the home screen's live friend list). One
/// `ref.invalidateSelf()` on the Requests page (e.g. after a decline) fired
/// the notifier's `onDispose`, which called that prefix-wide unsubscribe and
/// silently killed the other page's live updates.
///
/// The fix: keep the `UnsubscribeFunc` PocketBase returns from `subscribe()`
/// and call THAT on dispose — it removes just the listener it owns.
///
/// This drives the real PocketBase realtime stack against a local SSE
/// server, so the assertion covers the actual subscription registry.
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

  test(
    'prefix-wide unsubscribe kills a sibling listener on the same collection',
    () async {
      var firstCalls = 0;
      var secondCalls = 0;

      await pb
          .collection('friend_requests')
          .subscribe('*', (_) => firstCalls++);
      await pb.collection('friend_requests').subscribe('*', (_) => secondCalls++);

      // The regression trigger: the old dispose path used the topic-less
      // collection unsubscribe, which removes EVERY listener on the topic.
      await pb.collection('friend_requests').unsubscribe();

      server.emit('friend_requests', {'action': 'create'});
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        firstCalls,
        0,
        reason: 'the prefix-wide unsubscribe removed the first listener too',
      );
      expect(
        secondCalls,
        0,
        reason: 'prefix-wide unsubscribe removes EVERY listener on the topic',
      );
    },
  );

  test(
    'a scoped unsubscribe removes only its own listener',
    () async {
      var firstCalls = 0;
      var secondCalls = 0;

      final unsubFirst = await pb
          .collection('friend_requests')
          .subscribe('*', (_) => firstCalls++);
      await pb.collection('friend_requests').subscribe('*', (_) => secondCalls++);

      // The fix: dispose via the UnsubscribeFunc PB handed back.
      await unsubFirst();

      server.emit('friend_requests', {'action': 'update'});
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        firstCalls,
        0,
        reason: 'the scoped unsubscribe removed its own listener',
      );
      expect(
        secondCalls,
        1,
        reason:
            'the scoped unsubscribe must NOT touch the sibling listener — '
            'this is the R1 fix',
      );
    },
  );
}

/// Minimal SSE server speaking PocketBase's realtime protocol:
/// `id`/`event`/`data` frames plus the PB_CONNECT handshake.
class _FakeRealtimeServer {
  _FakeRealtimeServer._(this._server, this._sessions);

  static Future<_FakeRealtimeServer> start() async {
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
      // GET /api/realtime — the SSE stream.
      request.response.headers.contentType =
          ContentType('text', 'event-stream');
      request.response.bufferOutput = false;
      final session = _SseSession(request.response);
      sessions.add(session);
      session.send({
        'id': 'test-client-1',
        'event': 'PB_CONNECT',
        'data': jsonEncode({'clientId': 'test-client-1'}),
      });
    });

    return _FakeRealtimeServer._(server, sessions);
  }

  final HttpServer _server;
  final List<_SseSession> _sessions;

  String get url => 'http://127.0.0.1:${_server.port}';

  /// Push a record event to every connected client.
  ///
  /// PocketBase keys its realtime subscriptions by `collection/topic`, so the
  /// SSE `event` field must be `friend_requests/*` — that is the key the
  /// realtime service dispatches on.
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

/// One SSE connection.
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
