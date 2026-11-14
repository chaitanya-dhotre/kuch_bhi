// A voice note or document whose upload failed never gets a server id, so it
// stays on the optimistic placeholder. Device 2026-10-30: in dark mode that
// placeholder drew dark onAccent ink on an 18% accent shell (unreadable) and
// still claimed "Uploading…" with a spinner after the upload had failed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/message_bubble.dart';

Future<void> _pump(WidgetTester tester, String type, String status) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          outboxStatusProvider.overrideWith(
            (ref, convId) => Stream.value(const []),
          ),
          messageBodyProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp(
          theme: warmPopDark(),
          home: Scaffold(
            body: MessageBubble(
              message: Message(
                localId: 'l1',
                conversationId: 'c1',
                senderId: 'me',
                type: type,
                status: status,
                createdAt: DateTime(2026, 10, 30),
              ),
              isMine: true,
            ),
          ),
        ),
      ),
    );

/// Chat calm D2/E7: the shell is the own tint (`bubbleMine`), like every
/// other own bubble, and its ink is `ink`, readable in dark mode.
void _expectAccentShell(WidgetTester tester) {
  final accent = tester.element(find.byType(MessageBubble)).t.bubbleMine;
  final shells = tester
      .widgetList<Container>(find.byType(Container))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .where((d) => d.color == accent);
  expect(shells, isNotEmpty);
}

void main() {
  for (final (type, label) in [
    ('voice', 'Voice note not sent'),
    ('document', 'Document not sent'),
  ]) {
    testWidgets('failed $type upload says so, readably, without a spinner', (
      tester,
    ) async {
      await _pump(tester, type, 'failed');
      await tester.pump();

      expect(find.text(label), findsOneWidget);
      expect(find.textContaining('Uploading'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      _expectAccentShell(tester);
    });
  }

  testWidgets('an upload in flight still shows progress on the accent shell', (
    tester,
  ) async {
    await _pump(tester, 'document', 'pending');
    await tester.pump();

    expect(find.text('Uploading document…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    _expectAccentShell(tester);
  });
}
