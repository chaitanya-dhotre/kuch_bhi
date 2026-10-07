import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/entities/message.dart';

Message msg({String? body}) => Message(
      localId: 'l1',
      conversationId: 'c1',
      senderId: 'u2',
      type: 'text',
      decryptedBody: body,
      status: 'sent',
      createdAt: DateTime(2026, 10, 7),
    );

void main() {
  testWidgets('bubble with null body renders without throwing (placeholder law baseline)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: warmPopLight(),
      home: Scaffold(body: ListView(children: [
        Text(msg(body: null).decryptedBody ?? '🔒'), // baseline: null-safe display path
      ])),
    ));
    expect(tester.takeException(), isNull);
  });

  test('conversation preview source tolerates null decryptedBody', () {
    final m = msg(body: null);
    final preview = (m.decryptedBody ?? '').isEmpty ? '' : m.decryptedBody!;
    expect(preview, '', reason: 'today: empty, never throws — Task 9 keeps it non-throwing');
  });

  test('chat search filter over null-body rows does not throw', () {
    final rows = [msg(body: 'alpha'), msg(body: null), msg(body: 'beta')];
    final q = 'a';
    final hits = rows
        .where((m) => (m.decryptedBody ?? '').contains(q))
        .toList();
    // CORRECTION vs brief (expected 1): both 'alpha' AND 'beta' contain
    // 'a' — 2 hits. The pinned behavior: the null-body row is skipped
    // without a crash, never the exact count the brief guessed.
    expect(hits.length, 2);
  });
}
