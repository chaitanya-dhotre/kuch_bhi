// Fake PocketBase for the media-send tests: stateful messages +
// message_media collections, an offline switch, per-step gates and counters.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import 'char_harness.dart';

/// Server clock: an hour ahead of the device, so a device-time stamp is
/// easy to tell apart.
final serverNow = DateTime.now().toUtc().add(const Duration(hours: 1));
final serverCreated = DateTime.fromMillisecondsSinceEpoch(
  serverNow.millisecondsSinceEpoch ~/ 1000 * 1000,
  isUtc: true,
).toIso8601String();

class FakeMediaServer {
  final messages = <String, Map<String, dynamic>>{};
  final media = <String, Map<String, dynamic>>{}; // media id → record
  final createBodies = <Map<String, dynamic>>[];
  final createOrder = <String>[];
  final marks = <String>[];
  int mediaUploads = 0;
  int mediaLookups = 0;
  int inFlightMedia = 0;
  int maxInFlightMedia = 0;
  bool offline = false;

  /// Answer for the next media create (e.g. 413); null = success.
  int? mediaStatus;

  /// Store the record, then fail the response (a lost ack).
  bool loseMessageAck = false;
  bool loseMediaAck = false;

  /// Holds the media create until completed (a slow upload).
  Completer<void>? mediaGate;

  /// Holds a message create before it is stored (a create still in flight).
  Completer<void>? createGate;

  /// Fires when a media create reaches the server.
  final mediaArrived = StreamController<String>.broadcast();

  Map<String, dynamic> _record(String collection, Map<String, dynamic> body) =>
      {
        'collectionId': collection,
        'collectionName': collection,
        'created': serverCreated,
        'updated': serverCreated,
        ...body,
      };

  http.Response _json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  http.Response _list(List<Map<String, dynamic>> items) => _json({
        'page': 1,
        'perPage': items.length,
        'totalItems': items.length,
        'totalPages': 1,
        'items': items,
      });

  /// The SDK sends a multipart body as one `@jsonPayload` field.
  static Map<String, dynamic> _payload(String multipart) {
    final m = RegExp(r'name="@jsonPayload"\r\n(?:[^\r]+\r\n)*\r\n(.*?)\r\n--',
            dotAll: true)
        .firstMatch(multipart)!;
    return jsonDecode(m.group(1)!) as Map<String, dynamic>;
  }

  MockClient client() => MockClient((req) async {
        final path = req.url.path;
        if (path.startsWith('/api/realtime')) {
          return Completer<http.Response>().future;
        }
        if (offline) throw http.ClientException('offline', req.url);

        const msgs = '/api/collections/messages/records';
        const med = '/api/collections/message_media/records';
        if (path == msgs && req.method == 'POST') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          createBodies.add(body);
          final id = body['id'] as String;
          createOrder.add(id);
          if (createGate != null) await createGate!.future;
          if (messages.containsKey(id)) {
            return _json({
              'status': 400,
              'message': 'Failed to create record.',
              'data': {
                'id': {'code': 'validation_not_unique', 'message': 'taken'},
              },
            }, 400);
          }
          messages[id] = _record('messages', body);
          if (loseMessageAck) {
            loseMessageAck = false;
            throw http.ClientException('connection reset', req.url);
          }
          return _json(messages[id]!);
        }
        if (path.startsWith('$msgs/') && req.method == 'GET') {
          final rec = messages[path.substring(msgs.length + 1)];
          return rec == null
              ? _json({'status': 404, 'message': 'missing'}, 404)
              : _json(rec);
        }
        if (path.startsWith('$msgs/') && req.method == 'PATCH') {
          final id = path.substring(msgs.length + 1);
          marks.add(id);
          final rec = messages[id];
          if (rec == null) return _json({'status': 404, 'message': 'x'}, 404);
          rec.addAll(jsonDecode(req.body) as Map<String, dynamic>);
          return _json(rec);
        }
        if (path == msgs && req.method == 'GET') {
          return _list(messages.values.toList());
        }
        if (path == med && req.method == 'GET') {
          mediaLookups++;
          final filter = req.url.queryParameters['filter'] ?? '';
          final mid = RegExp(r'message_id="(\w+)"').firstMatch(filter)?.group(1);
          return _list([
            for (final r in media.values)
              if (r['message_id'] == mid) r,
          ]);
        }
        if (path == med && req.method == 'POST') {
          final body = _payload(latin1.decode(req.bodyBytes));
          final mid = body['message_id'] as String;
          mediaUploads++;
          inFlightMedia++;
          if (inFlightMedia > maxInFlightMedia) maxInFlightMedia = inFlightMedia;
          mediaArrived.add(mid);
          try {
            if (mediaGate != null) await mediaGate!.future;
            if (mediaStatus != null) {
              return _json({'status': mediaStatus, 'message': 'no'}, mediaStatus!);
            }
            final id = 'med${media.length}'.padRight(15, 'x');
            media[id] = _record('message_media', {
              'id': id,
              'message_id': mid,
              'file_name': body['file_name'],
            });
            if (loseMediaAck) {
              loseMediaAck = false;
              throw http.ClientException('connection reset', req.url);
            }
            return _json(media[id]!);
          } finally {
            inFlightMedia--;
          }
        }
        return http.Response('{"message":"unhandled $path"}', 404);
      });
}

/// path_provider's temp dir → a per-test directory (the store keeps sent
/// files under `<tmp>/media_clear`).
Future<Directory> mockTempDir() async {
  final dir = await Directory.systemTemp.createTemp('media_send');
  addTearDown(() => dir.delete(recursive: true));
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => dir.path,
  );
  return dir;
}

Future<File> tempFile(Directory dir, String name, [int bytes = 300000]) async =>
    File('${dir.path}/$name')
      ..writeAsBytesSync(List<int>.generate(bytes, (i) => i % 251));

/// Polls [check] (real time) until it holds.
Future<void> until(Future<bool> Function() check, {String? reason}) async {
  for (var i = 0; i < 200; i++) {
    if (await check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('timed out waiting${reason == null ? '' : ': $reason'}');
}

Future<(CharHarness, MessageRepositoryImpl, FakeMediaServer, Directory)>
    mediaSendSetup() async {
  final server = FakeMediaServer();
  final h = charHarness(clientFactory: server.client);
  addTearDown(h.close);
  await seedConversationAndKey(h);
  final tmp = await mockTempDir();
  return (h, buildRepo(h), server, tmp);
}
