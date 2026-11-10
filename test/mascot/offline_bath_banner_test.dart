import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/constants/app_strings.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/outbox_table.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/mascot/capy.dart';
import 'package:kuch_bhi/features/mascot/offline_bath_banner.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';

import 'capy_test.dart' show FakeSource;

void main() {
  group('nextBathPhase', () {
    BathPhase n(BathPhase p, bool online, int q) =>
        nextBathPhase(p, online: online, queued: q);

    test('offline wins from any phase', () {
      for (final p in BathPhase.values) {
        expect(n(p, false, 0), BathPhase.offline);
      }
    });
    test('reconnect: sending while texts wait, else collapse as before', () {
      expect(n(BathPhase.offline, true, 2), BathPhase.sending);
      expect(n(BathPhase.offline, true, 0), BathPhase.hidden);
    });
    test('sending → done at zero; hidden never reopens while online', () {
      expect(n(BathPhase.sending, true, 1), BathPhase.sending);
      expect(n(BathPhase.sending, true, 0), BathPhase.done);
      expect(n(BathPhase.hidden, true, 5), BathPhase.hidden);
      expect(n(BathPhase.done, true, 0), BathPhase.done);
    });
    test('copy', () {
      expect(bathCopy(BathPhase.offline, 0), [kOfflineSendCopy]);
      expect(bathCopy(BathPhase.offline, 4), [kOfflineSendCopy, '4 waiting']);
      expect(bathCopy(BathPhase.sending, 3), ['Back online, sending 3…']);
      expect(bathCopy(BathPhase.done, 0), ['All sent.']);
    });
  });

  group('banner', () {
    late StreamController<bool> online;
    late StreamController<int> queued;
    late FakeSource source;
    var retries = 0;

    setUp(() {
      online = StreamController<bool>();
      queued = StreamController<int>();
      CapyLoader.debugSource = source = FakeSource();
      retries = 0;
    });
    tearDown(() => CapyLoader.debugSource = null);

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isOnlineProvider.overrideWith((ref) => online.stream),
            queuedCountProvider.overrideWith((ref) => queued.stream),
          ],
          child: MaterialApp(
            theme: warmPopLight(),
            home: Scaffold(
              body: OfflineBathBanner(
                tapToRetry: true,
                onRetry: () => retries++,
              ),
            ),
          ),
        ),
      );
    }

    Future<void> emit(WidgetTester tester, {bool? on, int? q}) async {
      if (on != null) online.add(on);
      if (q != null) queued.add(q);
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
    }

    testWidgets('offline → sending (flush per send) → All sent → collapses', (
      tester,
    ) async {
      await pump(tester);
      await emit(tester, on: true, q: 0);
      expect(find.byType(Capy), findsNothing);

      await emit(tester, on: false, q: 3);
      expect(find.text(kOfflineSendCopy), findsOneWidget);
      expect(find.text('3 waiting'), findsOneWidget);
      final rig = source.rigs.single;
      expect(rig.mood, CapyMood.chill);
      expect(rig.queued, 3);

      await emit(tester, q: 4);
      expect(find.text('4 waiting'), findsOneWidget);
      expect(rig.queued, 3, reason: 'the pool shows at most 3 yuzus');

      await emit(tester, on: true);
      expect(find.text('Back online, sending 4…'), findsOneWidget);
      expect(rig.mood, CapyMood.active);

      await emit(tester, q: 3);
      await emit(tester, q: 1);
      expect(rig.fired.where((f) => f == 'flush').length, 2);

      await emit(tester, q: 0);
      expect(find.text('All sent.'), findsOneWidget);
      expect(rig.mood, CapyMood.happy);
      expect(rig.fired.last, 'flush', reason: 'the last yuzu leaves first');
      expect(find.text('Retry'), findsNothing);
      await tester.pump(kBathHopDelay);
      expect(rig.fired.last, 'hop');

      await tester.pump(kBathDoneHold);
      await tester.pumpAndSettle();
      expect(find.text('All sent.'), findsNothing);
      expect(find.byType(Capy), findsNothing);
    });

    testWidgets(
      'a stuck op cannot pin the banner: it leaves 10 s after reconnect',
      (tester) async {
        await pump(tester);
        await emit(tester, on: false, q: 2);
        await emit(tester, on: true);
        expect(find.text('Back online, sending 2…'), findsOneWidget);
        await tester.pump(const Duration(seconds: 9));
        expect(find.text('Back online, sending 2…'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.byType(Capy), findsNothing);
      },
    );

    testWidgets(
      'tapping the capybara pets it; the banner tap still retries (F8)',
      (tester) async {
        await pump(tester);
        await emit(tester, on: false, q: 1);
        await tester.tap(find.byType(Capy));
        expect(source.rigs.single.fired, ['pet']);
        expect(retries, 0);

        await tester.tap(find.text(kOfflineSendCopy));
        await tester.tap(find.text('Retry'));
        expect(retries, 2);
      },
    );
  });

  test('queuedCountProvider counts only text_send in queued|sending', () async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    var seq = 0;
    Future<void> op(String kind, OutboxState state) => db.outboxDao.enqueue(
      OutboxTableCompanion.insert(
        opId: 'op${seq++}',
        kind: kind,
        ref: 'm$seq',
        conversationId: seq.isEven ? 'a' : 'b',
        seq: seq,
        state: Value(state),
        createdAt: DateTime(2026),
      ),
    );
    await op('text_send', OutboxState.queued);
    await op('text_send', OutboxState.sending);
    await op('text_send', OutboxState.sent);
    await op('text_send', OutboxState.failedTerminal);
    await op('media_upload', OutboxState.queued);
    await op('reaction_add', OutboxState.queued);
    await op('text_send', OutboxState.queued);

    final sub = container.listen(queuedCountProvider, (_, __) {});
    addTearDown(sub.close);
    expect(await container.read(queuedCountProvider.future), 3);
  });
}
