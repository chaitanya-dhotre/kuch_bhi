import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/utils/media_utils.dart';
import 'package:kuch_bhi/features/chat/message_offline_policy.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/document_message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/image_message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/video_message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/voice_message_bubble.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';
import 'package:kuch_bhi/features/media/screens/media_docs_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/services/media_gallery_service.dart';
import 'package:pocketbase/pocketbase.dart';

import '../core/sheet_harness.dart';

/// Bug wave 2 §4: mediaFileProvider is a plain family, so a failed or empty
/// load stays cached. Every media surface gets a retry that drops it first,
/// and an empty result re-runs by itself on reconnect.
void main() {
  late int fetches;
  setUp(() => fetches = 0);

  Override emptyMedia() => mediaFileProvider.overrideWith((ref, r) async {
    fetches++;
    return null; // offline / never landed
  });
  Override online(bool on) =>
      isOnlineProvider.overrideWith((ref) => Stream.value(on));

  Future<void> bubble(
    WidgetTester tester,
    Widget w, {
    bool on = true,
    MediaBlobStatus blob = MediaBlobStatus.other,
  }) async {
    await pumpHost(
      tester,
      Scaffold(body: Center(child: w)),
      overrides: [
        emptyMedia(),
        online(on),
        mediaBlobStatusProvider.overrideWith((ref, r) async => blob),
      ],
      large: true,
    );
    await tester.pump();
    await tester.pump();
  }

  final cases = <String, Widget>{
    'Photo': const ImageMessageBubble(
      conversationId: 'c1',
      serverId: 's1',
      isMine: false,
      isDark: false,
    ),
    'Video': const VideoMessageBubble(
      conversationId: 'c1',
      serverId: 's1',
      isMine: false,
      isDark: false,
    ),
    'Document': const DocumentMessageBubble(
      conversationId: 'c1',
      serverId: 's1',
      isMine: true,
      isDark: false,
    ),
  };

  for (final MapEntry(key: what, value: w) in cases.entries) {
    testWidgets('$what bubble: an empty load offers Tap to retry, and the '
        'tap really fetches again (360dp, 200%)', (tester) async {
      await bubble(tester, w);
      expect(find.text('Tap to retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('Tap to retry')),
        isSemantics(
          label: "$what didn't load. Tap to retry",
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
      expect(fetches, 1);

      await tester.tap(find.text('Tap to retry'));
      await tester.pump();
      await tester.pump();
      expect(fetches, 2, reason: 'a retry must not reuse the cached null');
    });
  }

  // Device check 2026-10-31: 3-month-old media sat on a shimmer, then a
  // retry that could never work (a purged record answers 404 = "queued").
  final old = DateTime.now().subtract(const Duration(days: 90));
  final expiredCases = <String, Widget>{
    'image': ImageMessageBubble(
      conversationId: 'c1',
      serverId: 's1',
      isMine: false,
      isDark: false,
      createdAt: old,
    ),
    'video': VideoMessageBubble(
      conversationId: 'c1',
      serverId: 's1',
      isMine: false,
      isDark: false,
      createdAt: old,
    ),
    'voice': VoiceMessageBubble(
      conversationId: 'c1',
      serverId: 's1',
      isMine: false,
      createdAt: old,
    ),
    'document': DocumentMessageBubble(
      conversationId: 'c1',
      serverId: 's1',
      isMine: true,
      isDark: false,
      createdAt: old,
    ),
  };
  for (final MapEntry(key: type, value: w) in expiredCases.entries) {
    testWidgets('$type past its longest retention: expired at once, never '
        'fetched, no retry (360dp, 200%)', (tester) async {
      await bubble(tester, w);
      expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
      expect(find.text('Tap to retry'), findsNothing);
      expect(fetches, 0);
      expect(tester.takeException(), isNull);
    });
  }

  // Device round 2: in full-width voice/doc bubbles the mark sat centred and
  // faint grey on the own amber bubble. Now a left row; chat calm E7: the
  // own bubble is a tint, so both sides read inkSoft.
  for (final mine in [true, false]) {
    testWidgets('expired voice + document (${mine ? 'own' : 'theirs'}): a '
        'left-aligned row in readable ink (360dp, 200%)', (tester) async {
      for (final w in [
        VoiceMessageBubble(
          conversationId: 'c1',
          serverId: 's1',
          isMine: mine,
          createdAt: old,
        ),
        DocumentMessageBubble(
          conversationId: 'c1',
          serverId: 's1',
          isMine: mine,
          isDark: false,
          createdAt: old,
        ),
      ]) {
        await bubble(tester, w);
        final icon = tester.getRect(find.byIcon(Icons.timer_off_outlined));
        final text = tester.getRect(find.text('Media expired'));
        expect(
          icon.right,
          lessThanOrEqualTo(text.left),
          reason: 'icon and copy share one row',
        );
        final frame = tester.getRect(find
            .ancestor(
                of: find.byIcon(Icons.timer_off_outlined),
                matching: find.byType(DecoratedBox))
            .first);
        expect(icon.left - frame.left, lessThan(30),
            reason: 'starts at the bubble edge, not centred');
        final t = tokens(tester);
        expect(
          paintedColor(tester, find.text('Media expired')),
          t.inkSoft,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  test('isPastRetention: the longest retention per type, plus a day', () {
    DateTime ago(int days) => DateTime.now().subtract(Duration(days: days));
    expect(isPastRetention('image', ago(60)), isFalse);
    expect(isPastRetention('image', ago(62)), isTrue);
    expect(isPastRetention('video', ago(30)), isFalse);
    expect(isPastRetention('video', ago(32)), isTrue);
    expect(isPastRetention('voice', ago(62)), isTrue);
    expect(isPastRetention('document', ago(60)), isFalse);
    expect(isPastRetention('image', null), isFalse);
  });

  testWidgets('offline: one 38% dim plus the hint, and the tap does nothing', (
    tester,
  ) async {
    await bubble(tester, cases['Photo']!, on: false);
    expect(find.text(kOfflineActionHint), findsOneWidget);
    expect(find.text('Tap to retry'), findsNothing);
    final dims = tester
        .widgetList<Opacity>(
          find.ancestor(
            of: find.byIcon(Icons.broken_image_outlined),
            matching: find.byType(Opacity),
          ),
        )
        .toList();
    expect(dims.map((o) => o.opacity), [.38]);
    await tester.tap(find.text(kOfflineActionHint));
    await tester.pump();
    expect(fetches, 1);
  });

  testWidgets('a blob the store marked failed is final: no retry offered', (
    tester,
  ) async {
    // Decision 9: an expired blob now says Media expired (was No longer
    // available, which is kept for a dead link).
    await bubble(tester, cases['Photo']!, blob: MediaBlobStatus.expired);
    expect(find.text('Media expired'), findsOneWidget);
    expect(find.text('Tap to retry'), findsNothing);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.text('Media expired')),
      isSemantics(label: 'Photo. Media expired', isButton: false),
    );
    handle.dispose();
    await tester.tap(find.text('Media expired'));
    await tester.pump();
    expect(fetches, 1);
  });

  testWidgets('voice bubble: the second tap after a failed load re-fetches; '
      'offline it dims with the hint', (tester) async {
    final online$ = StreamController<bool>();
    addTearDown(online$.close);
    await pumpHost(
      tester,
      const Scaffold(
        body: Center(
          child: VoiceMessageBubble(
            conversationId: 'c1',
            serverId: 'v1',
            isMine: false,
          ),
        ),
      ),
      overrides: [
        emptyMedia(),
        isOnlineProvider.overrideWith((ref) => online$.stream),
      ],
      large: true,
    );
    online$.add(true);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    final afterFailure = fetches;
    await tester.tap(find.byIcon(Icons.error_outline));
    await tester.pump();
    await tester.pump();
    expect(
      fetches,
      afterFailure + 1,
      reason: 'the retry tap dropped the cached null and fetched again',
    );

    online$.add(false);
    await tester.pump();
    await tester.pump();
    expect(find.text(kOfflineActionHint), findsOneWidget);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byIcon(Icons.error_outline)),
      isSemantics(
        label: "Voice message didn't load. $kOfflineActionHint",
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
    handle.dispose();
    final before = fetches;
    await tester.tap(find.byIcon(Icons.error_outline));
    await tester.pump();
    expect(fetches, before);
  });

  group('Media & Docs', () {
    Override page(
      String type,
      List<RecordModel> Function() rows, {
      void Function()? onLoad,
      bool fail = false,
    }) => mediaPageProvider.overrideWith((ref, key) async {
      if (key.mediaType != type) return const [];
      onLoad?.call();
      if (fail) throw Exception('ClientException: Connection timed out');
      return rows();
    });

    testWidgets('a failed tab says so in plain words; Retry loads again', (
      tester,
    ) async {
      var loads = 0;
      await pumpHost(
        tester,
        const MediaDocsScreen(conversationId: 'c1'),
        overrides: [
          page('image', () => const [], onLoad: () => loads++, fail: true),
          online(true),
        ],
        large: true,
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load this chat's media."), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('Error:'), findsNothing);
      expect(loads, 1);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(loads, 2);
    });

    testWidgets('offline, the tab Retry dims once with the hint', (
      tester,
    ) async {
      var loads = 0;
      await pumpHost(
        tester,
        const MediaDocsScreen(conversationId: 'c1'),
        overrides: [
          page('image', () => const [], onLoad: () => loads++, fail: true),
          online(false),
        ],
        large: true,
      );
      await tester.pumpAndSettle();
      expect(find.text(kOfflineActionHint), findsOneWidget);
      final dim = tester.widget<Opacity>(
        find
            .ancestor(of: find.text('Retry'), matching: find.byType(Opacity))
            .first,
      );
      expect(dim.opacity, .38);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(loads, 1);
    });

    testWidgets('a doc whose load came back empty: plain toast, and the '
        'next tap fetches again', (tester) async {
      await pumpHost(
        tester,
        const MediaDocsScreen(conversationId: 'c1'),
        overrides: [
          page(
            'document',
            () => [
              RecordModel({
                'id': 'm1',
                'message_id': 'd1',
                'file_name': 'notes.pdf',
                'file_size': 2048,
                'created': '2026-10-01 10:00:00Z',
              }),
            ],
          ),
          emptyMedia(),
          online(true),
        ],
      );
      await tester.tap(find.text('Docs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('notes.pdf'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't open the file. Try again."), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(fetches, 1);

      await tester.tap(find.text('notes.pdf'));
      await tester.pumpAndSettle();
      expect(
        fetches,
        2,
        reason: 'the second tap must not reuse the cached null',
      );
    });
  });

  group('reconnect re-runs an empty result', () {
    late StreamController<bool> online$;
    late ProviderContainer container;
    setUp(() {
      online$ = StreamController<bool>();
      container = ProviderContainer(
        overrides: [isOnlineProvider.overrideWith((ref) => online$.stream)],
      );
      addTearDown(container.dispose);
      addTearDown(online$.close);
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test(
      'invalidateOnReconnect: offline → online runs it again, only then',
      () async {
        var runs = 0;
        final p = FutureProvider<int?>((ref) async {
          runs++;
          invalidateOnReconnect(ref);
          return null;
        });
        container.listen(p, (_, __) {});
        await container.read(p.future);
        expect(runs, 1);
        online$.add(true);
        await settle();
        online$.add(false);
        await settle();
        expect(runs, 1, reason: 'going offline is no reason to run again');
        online$.add(true);
        await settle();
        await container.read(p.future);
        expect(runs, 2);
      },
    );
  });
}
