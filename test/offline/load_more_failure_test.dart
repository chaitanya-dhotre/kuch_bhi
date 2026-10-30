// Bug wave 1 §1.3: a failed history page must reach the chat screen (so it
// keeps its offset and offers Retry) and the network call is bounded at 8s.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/chat/message_offline_policy.dart';
import 'package:kuch_bhi/features/chat/screens/chat_screen.dart';

import 'char_harness.dart';
import 'send_fetch_char_test.dart' show fetchListClient;

/// SSE hangs (see send_fetch_char_test); every other call gets [onList].
MockClient _client(Future<http.Response> Function() onList) =>
    MockClient((req) {
      if (req.url.path.startsWith('/api/realtime')) {
        return Completer<http.Response>().future;
      }
      return onList();
    });

Widget _host(Widget child) => MaterialApp(
  theme: warmPopLight(),
  home: Scaffold(body: child),
);

void main() {
  test('a failed history page throws instead of returning normally', () async {
    final h = charHarness(
      clientFactory: () =>
          _client(() async => throw http.ClientException('offline')),
    );
    addTearDown(h.close);
    await seedConversationAndKey(h);

    await expectLater(
      buildRepo(h).loadMoreMessages('g1', 40),
      throwsA(anything),
    );
  });

  test('a stalled history page gives up after 8s', () async {
    final h = charHarness(
      clientFactory: () => _client(() => Completer<http.Response>().future),
    );
    addTearDown(h.close);
    await seedConversationAndKey(h);

    final sw = Stopwatch()..start();
    await expectLater(
      buildRepo(h).loadMoreMessages('g1', 40),
      throwsA(isA<TimeoutException>()),
    );
    expect(sw.elapsed, lessThan(const Duration(seconds: 12)));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a page without the group key still lands, as key_missing', () async {
    final h = charHarness(
      clientFactory: () => fetchListClient(conversationId: 'g1'),
    );
    addTearDown(h.close);
    await seedConversationAndKey(h, withKey: false);

    await buildRepo(h).loadMoreMessages('g1', 40);
    final cached = await h.db.messagesDao.watchMessages('g1').first;
    expect(cached, hasLength(1));
    expect(cached.first.decryptState, 'key_missing');
  });

  testWidgets('history load failure offers Retry online', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      _host(HistoryLoadFailedRow(online: true, onRetry: () => retried++)),
    );
    expect(find.text("Couldn't load older messages."), findsOneWidget);
    expect(find.text(kOfflineActionHint), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('history load failure dims Retry offline with the hint', (
    tester,
  ) async {
    var retried = 0;
    await tester.pumpWidget(
      _host(HistoryLoadFailedRow(online: false, onRetry: () => retried++)),
    );
    final dims = tester
        .widgetList<Opacity>(find.byType(Opacity))
        .where((o) => o.opacity == .38);
    expect(dims, hasLength(1));
    expect(find.text(kOfflineActionHint), findsOneWidget);
    await tester.tap(find.text('Retry'), warnIfMissed: false);
    expect(retried, 0);
  });
}
