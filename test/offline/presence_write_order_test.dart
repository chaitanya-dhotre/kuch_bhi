import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/data/local/database/tables/app_settings_table.dart';
import 'package:kuch_bhi/services/presence_service.dart';

import 'char_harness.dart';

/// Every presence PATCH body in arrival order; [hold] parks the next one
/// until it completes (a slow mobile network).
class _Server {
  final bodies = <Map<String, dynamic>>[];
  Completer<void>? hold;

  http.Client client() => MockClient((req) async {
    final gate = hold;
    hold = null;
    if (gate != null) await gate.future;
    bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
    return http.Response(
      jsonEncode({'id': 'u_test', 'collectionId': 'users'}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

Future<(PresenceService, _Server)> _presence() async {
  final server = _Server();
  final h = charHarness(clientFactory: server.client);
  addTearDown(h.close);
  await h.db.settingsDao.setSetting(AppSettingsKeys.currentUserId, 'u_test');
  final presence = PresenceService(pbClient: h.pbClient, db: h.db);
  addTearDown(presence.dispose);
  return (presence, server);
}

void main() {
  test('a slow leave still lands before the next chat\'s enter', () async {
    final (presence, server) = await _presence();
    await presence.enterChat('A');
    server.hold = Completer<void>();
    final gate = server.hold!;
    final leave = presence.leaveChat('A'); // back: not awaited
    final enter = presence.enterChat('B');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    gate.complete();
    await Future.wait([leave, enter]);
    expect(server.bodies.map((b) => b['current_chat']).toList(), [
      'A',
      '',
      'B',
    ]);
  });

  test('a late leave of an old chat never clears the chat entered since',
      () async {
    final (presence, server) = await _presence();
    await presence.enterChat('A');
    await presence.enterChat('B');
    await presence.leaveChat('A'); // chat A's dispose, after B opened
    expect(server.bodies.last['current_chat'], 'B');
    expect(server.bodies, hasLength(2));
    await presence.leaveChat('B');
    expect(server.bodies.last['current_chat'], '');
  });
}
