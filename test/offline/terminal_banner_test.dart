// Task 4 — terminal-failure banner: a `failedTerminal` outbox op must render
// a visible stuck-message strip (error class + Retry + Discard) under its
// message bubble, and both actions must hit the REAL MessageRepository
// methods (mocktail-free fake — char_harness implements+noSuchMethod pattern).
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/outbox_table.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/message_bubble.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart'
    show messageRepositoryProvider;

/// Mocktail-free fake: only retry/discard are wired; everything else routes
/// to noSuchMethod and fails loudly if the banner ever calls wider repo API.
class FakeMessageRepository implements MessageRepository {
  final retried = <String>[];
  final discarded = <String>[];

  @override
  Future<void> retryOp(String opId) async => retried.add(opId);

  @override
  Future<void> discardOp(String opId) async => discarded.add(opId);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeMessageRepository.${invocation.memberName} not stubbed');
}

Message _msg() => Message(
      localId: 'l1',
      conversationId: 'c1',
      senderId: 'me',
      type: 'text',
      decryptedBody: 'stuck message',
      status: 'failed',
      createdAt: DateTime(2026, 10, 7),
    );

OutboxTableData _op({
  String opId = 'opdead000000001',
  String ref = 'l1',
  String conversationId = 'c1',
  OutboxState state = OutboxState.failedTerminal,
  String errorClass = 'dead_link',
}) =>
    OutboxTableData(
      opId: opId,
      kind: 'text_send',
      ref: ref,
      conversationId: conversationId,
      seq: 1,
      state: state,
      attempts: 3,
      createdAt: DateTime(2026, 10, 7),
      lastError: '404',
      errorClass: errorClass,
    );

/// Pumps one message bubble with the outbox provider fed by [rows] and the
/// repo swapped for a recording fake.
Future<FakeMessageRepository> _pump(
  WidgetTester tester, {
  required List<OutboxTableData> rows,
}) async {
  final fake = FakeMessageRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        outboxStatusProvider
            .overrideWith((ref, convId) => Stream.value(rows)),
        messageRepositoryProvider.overrideWithValue(fake),
        // T9: bubble bodies ride messageBodyProvider — stub the resolved
        // body hermetically (no repo/DB in this banner test; keeps the
        // coalescer timer out of the fake clock).
        messageBodyProvider.overrideWith((ref, id) async => 'stuck message'),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: ListView(
            children: [
              MessageBubble(message: _msg(), isMine: true),
            ],
          ),
        ),
      ),
    ),
  );
  // Let the Stream.value emission land + the rebuild flush.
  await tester.pump();
  await tester.pump();
  return fake;
}

void main() {
  testWidgets(
      'failedTerminal op renders banner: title + error class + Retry/Discard',
      (tester) async {
    await _pump(tester, rows: [_op()]);

    expect(find.text('Failed to send'), findsOneWidget,
        reason: 'banner title must be visible');
    expect(find.text('dead_link'), findsOneWidget,
        reason: 'error class text must be visible (spec: terminal block VISIBLE)');
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
  });

  testWidgets('banner rides Warm Pop tokens: t.error @8% bg, radiusSm',
      (tester) async {
    await _pump(tester, rows: [_op()]);

    final banner = find.byKey(const ValueKey('terminal-banner-l1'));
    expect(banner, findsOneWidget);
    final container = tester.widget<Container>(
      find.descendant(of: banner, matching: find.byType(Container)).first,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color,
        WarmPopTokens.error.withValues(alpha: 0.08),
        reason: 'banner bg = t.error @ 8% (Warm Pop token law)');
    expect(decoration.borderRadius, BorderRadius.circular(WarmPopTokens.radiusSm));
  });

  testWidgets('Discard tap calls repo.discardOp with the op id',
      (tester) async {
    final fake = await _pump(tester, rows: [_op()]);

    await tester.tap(find.text('Discard'));
    await tester.pump();

    expect(fake.discarded, ['opdead000000001'],
        reason: 'Discard must hit the REAL discardOp (cascade in Task 3)');
    expect(fake.retried, isEmpty);
  });

  testWidgets('Retry tap calls repo.retryOp with the op id', (tester) async {
    final fake = await _pump(tester, rows: [_op()]);

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(fake.retried, ['opdead000000001'],
        reason: 'Retry must hit the REAL retryOp (unstick + drain)');
    expect(fake.discarded, isEmpty);
  });

  testWidgets('no banner while the op is not failedTerminal (still queued)',
      (tester) async {
    await _pump(tester, rows: [_op(state: OutboxState.queued)]);

    expect(find.text('Failed to send'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Discard'), findsNothing);
  });

  testWidgets('no banner when no outbox row matches this message localId',
      (tester) async {
    await _pump(tester, rows: [_op(ref: 'someone_else')]);

    expect(find.text('Failed to send'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('no banner when the outbox stream is empty', (tester) async {
    await _pump(tester, rows: const []);

    expect(find.text('Failed to send'), findsNothing);
  });

  test('outboxStatusProvider streams only the given conversation rows',
      () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await db.outboxDao.enqueue(OutboxTableCompanion.insert(
      opId: 'op_c1',
      kind: 'text_send',
      ref: 'l1',
      conversationId: 'c1',
      seq: 1,
      state: const Value(OutboxState.failedTerminal),
      errorClass: const Value('dead_link'),
      createdAt: DateTime(2026, 10, 7),
    ));
    await db.outboxDao.enqueue(OutboxTableCompanion.insert(
      opId: 'op_c2',
      kind: 'text_send',
      ref: 'l9',
      conversationId: 'c2',
      seq: 1,
      createdAt: DateTime(2026, 10, 7),
    ));

    final rows = await container.read(outboxStatusProvider('c1').future);
    expect(rows, hasLength(1), reason: 'c2 rows must not leak into c1');
    expect(rows.single.opId, 'op_c1');
    expect(rows.single.state, OutboxState.failedTerminal);
    expect(rows.single.errorClass, 'dead_link');
  });
}
