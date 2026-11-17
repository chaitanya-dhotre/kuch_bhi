// Chat calm (spec docs/design/pages/chat-calm.md) gates 3, 5, 6, 7, 8, 10.
// Gates 1–2 live in bubble_geometry_test, 4 in run_grouping_test, 9 in
// media/media_download_state_test.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/document_message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/expiry_badge.dart';
import 'package:kuch_bhi/features/chat/widgets/image_message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/voice_message_bubble.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

final _file = File('/nonexistent/calm.jpg');

List<Override> _overrides() => [
  outboxStatusProvider.overrideWith((ref, c) => Stream.value(const [])),
  messageBodyProvider.overrideWith((ref, id) async => bodyCache.get(id)),
  mediaFileProvider.overrideWith(
    (ref, r) async => LocalMediaFile(
      file: _file,
      width: 400,
      height: 300,
      fileName: 'report.pdf',
    ),
  ),
  mediaFullLocalProvider.overrideWith((ref, r) => Stream.value(_file)),
  mediaBlobStatusProvider.overrideWith((ref, r) async => MediaBlobStatus.other),
  isOnlineProvider.overrideWith((ref) => Stream.value(true)),
];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 411,
  bool dark = false,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(
        theme: dark ? warmPopDark() : warmPopLight(),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Message _text(String id, {String sender = 'me', int minute = 0}) {
  bodyCache.put(id, id == 'link' ? 'hi https://example.com' : 'Hi $id');
  return Message(
    localId: id,
    conversationId: 'c1',
    senderId: sender,
    type: 'text',
    status: 'read',
    createdAt: DateTime(2026, 11, 14, 10, minute),
  );
}

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  testWidgets('gate 3 (B2): no bubble holds a time; one meta line follows '
      "the run's last; one-line bubbles in a run are equal height", (
    tester,
  ) async {
    await _pump(
      tester,
      Column(
        children: [
          MessageBubble(
            message: _text('a'),
            isMine: true,
            runStart: true,
            runEnd: false,
          ),
          MessageBubble(
            message: _text('b', minute: 1),
            isMine: true,
            runStart: false,
            runEnd: false,
          ),
          MessageBubble(
            message: _text('c', minute: 2),
            isMine: true,
            runStart: false,
            runEnd: true,
          ),
        ],
      ),
    );
    final frames = find.byType(ChatBubbleFrame);
    expect(frames, findsNWidgets(3));
    expect(
      find.descendant(of: frames, matching: find.byType(ChatBubbleTimestamp)),
      findsNothing,
    );
    expect(find.byType(ChatBubbleTimestamp), findsOneWidget);
    final meta = tester.getRect(find.byType(ChatBubbleTimestamp));
    final last = tester.getRect(frames.at(2));
    expect(meta.top, greaterThanOrEqualTo(last.bottom));
    final heights = {
      for (var i = 0; i < 3; i++) tester.getSize(frames.at(i)).height,
    };
    expect(heights, hasLength(1), reason: 'one height for one-line bubbles');
    expect(heights.single, closeTo(38, 0.5), reason: '9 + 20 + 9');
  });

  testWidgets(
    'gate 5 (B6): a short link above a preview card is start-aligned',
    (tester) async {
      await _pump(tester, MessageBubble(message: _text('link'), isMine: true));
      final text = tester.getRect(find.text('hi https://example.com'));
      final card = tester.getRect(
        find.byKey(const ValueKey('link-preview-card')),
      );
      expect(text.left, closeTo(card.left, 0.5));
      expect(card.width, ChatBubbleGeometry.attachmentWidth(411));
    },
  );

  for (final w in [384.0, 411.0, 554.0]) {
    testWidgets('gate 6: voice, document and photo share one width at W = $w', (
      tester,
    ) async {
      await _pump(
        tester,
        width: w,
        const Column(
          children: [
            VoiceMessageBubble(
              conversationId: 'c1',
              serverId: 'v1',
              isMine: true,
              durationText: '0:12',
            ),
            DocumentMessageBubble(
              conversationId: 'c1',
              serverId: 'd1',
              isMine: false,
              isDark: false,
            ),
            ImageMessageBubble(
              conversationId: 'c1',
              serverId: 'i1',
              isMine: true,
              isDark: false,
            ),
          ],
        ),
      );
      final frames = find.byType(ChatBubbleFrame);
      expect(frames, findsNWidgets(3));
      final a2 = ChatBubbleGeometry.attachmentWidth(w);
      for (var i = 0; i < 3; i++) {
        // The frame aligns a box to its side; measure the box.
        final box = find
            .descendant(of: frames.at(i), matching: find.byType(Container))
            .first;
        // The 12 dp A7 margin sits outside the box (motion C1 marks it).
        expect(
          tester.getSize(box).width,
          closeTo(a2, 0.5),
          reason: 'bubble $i',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  test('gate 7: every D1/D2 text pair is at least 4.5 : 1', () {
    final l = ColorTokens.light, d = ColorTokens.dark;
    final pairs = <String, (Color, Color)>{
      'ink on own bubble, light': (l.ink, l.bubbleMine),
      'ink on own bubble, dark': (d.ink, d.bubbleMine),
      'ink on their bubble, light': (l.ink, l.surface),
      'ink on their bubble, dark': (d.ink, d.surface),
      'time line, light': (l.inkSoft, l.bg),
      'time line, dark': (d.inkSoft, d.bg),
      'accentText on bg, light': (l.accentText, l.bg),
      'accentText on surface, dark': (d.accentText, d.surface),
      'onAccent on solid accent': (l.onAccent, l.accent),
      'ink on primary/50': (l.ink, WarmPopTokens.primary50),
    };
    pairs.forEach((name, p) {
      expect(_contrast(p.$1, p.$2), greaterThanOrEqualTo(4.5), reason: name);
    });
    expect(l.bubbleMine, WarmPopTokens.primary100, reason: 'D-1 A');
    expect(d.bubbleMine, WarmPopTokens.primary900);
    expect(WarmPopTokens.accentPressed, WarmPopTokens.primary600);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'gate 8: own text fill is bubbleMine (${dark ? 'dark' : 'light'}); '
      'the only accent fill is the voice play disc',
      (tester) async {
        await _pump(
          tester,
          dark: dark,
          Column(
            children: [
              MessageBubble(message: _text('own'), isMine: true),
              MessageBubble(
                message: _text('their', sender: 'u2'),
                isMine: false,
              ),
              const VoiceMessageBubble(
                conversationId: 'c1',
                serverId: 'v1',
                isMine: true,
                durationText: '0:12',
              ),
            ],
          ),
        );
        final t = dark ? ColorTokens.dark : ColorTokens.light;
        Color? fill(Finder f) =>
            ((tester
                        .widget<Container>(
                          find
                              .descendant(
                                of: f,
                                matching: find.byType(Container),
                              )
                              .first,
                        )
                        .decoration
                    as BoxDecoration?)
                ?.color);
        final frames = find.byType(ChatBubbleFrame);
        expect(fill(frames.at(0)), t.bubbleMine);
        expect(fill(frames.at(1)), t.surface);
        // D-5 A: their bubble has a 1 dp line border in light mode only.
        final theirBorder =
            (tester
                        .widget<Container>(
                          find
                              .descendant(
                                of: frames.at(1),
                                matching: find.byType(Container),
                              )
                              .first,
                        )
                        .foregroundDecoration
                    as BoxDecoration?)
                ?.border;
        expect(theirBorder != null, !dark);

        final accentFills = tester
            .widgetList<Container>(find.byType(Container))
            .where((c) => (c.decoration as BoxDecoration?)?.color == t.accent)
            .toList();
        expect(accentFills, hasLength(1));
        expect(accentFills.single.key, const ValueKey('voice-play-disc'));
      },
    );
  }

  group('gate 10 (R11)', () {
    Widget host({bool reduced = false}) => MaterialApp(
      theme: warmPopLight(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: const SkeletonGroup(
          child: Column(
            children: [Skeleton(width: 80), Skeleton(width: 60), Skeleton()],
          ),
        ),
      ),
    );

    testWidgets('one controller per group; nothing shows before 300 ms', (
      tester,
    ) async {
      final before = SkeletonGroup.debugLiveControllers;
      await tester.pumpWidget(host());
      expect(SkeletonGroup.debugLiveControllers - before, 1);
      Opacity outer() => tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(SkeletonGroup),
              matching: find.byType(Opacity),
            )
            .first,
      );
      await tester.pump(const Duration(milliseconds: 290));
      expect(outer().opacity, 0, reason: 'no placeholder before 300 ms');
      await tester.pump(const Duration(milliseconds: 20));
      expect(outer().opacity, 1);
      // The blocks breathe together: one shared animation.
      final fades = tester
          .widgetList<FadeTransition>(
            find.descendant(
              of: find.byType(SkeletonGroup),
              matching: find.byType(FadeTransition),
            ),
          )
          .map((f) => f.opacity)
          .toSet();
      expect(fades, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      expect(SkeletonGroup.debugLiveControllers, before);
    });

    testWidgets('reduced motion: no ticker, full opacity', (tester) async {
      final before = SkeletonGroup.debugLiveControllers;
      await tester.pumpWidget(host(reduced: true));
      expect(SkeletonGroup.debugLiveControllers, before);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.binding.hasScheduledFrame, isFalse);
      for (final f in tester.widgetList<FadeTransition>(
        find.descendant(
          of: find.byType(SkeletonGroup),
          matching: find.byType(FadeTransition),
        ),
      )) {
        expect(f.opacity.value, 1);
      }
    });

    test('shimmer is not imported anywhere', () {
      const pkg =
          'package:'
          'shimmer/';
      final hits = <String>[
        for (final dir in ['lib', 'test'])
          for (final f in Directory(dir).listSync(recursive: true))
            if (f is File &&
                f.path.endsWith('.dart') &&
                f.readAsStringSync().contains(pkg))
              f.path,
      ];
      expect(hits, isEmpty);
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('shimmer:')),
      );
    });
  });

  testWidgets('F: a decrypting text bubble is the placeholder, in the final '
      'shape and nearly the final size (no nested box, no jump)', (
    tester,
  ) async {
    const text = 'See you at the station at six';
    // base64 of UTF-8 text + 16-byte tag.
    final cipherLen = ((text.length + 16 + 2) ~/ 3) * 4;
    final body = Completer<String?>();
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final msg = Message(
      localId: 'pending-body',
      conversationId: 'c1',
      senderId: 'me',
      type: 'text',
      status: 'read',
      ciphertextLength: cipherLen,
      createdAt: DateTime(2026, 11, 14, 10),
    );
    Widget host() => ProviderScope(
      overrides: [
        ..._overrides(),
        messageBodyProvider.overrideWith((ref, id) => body.future),
      ],
      child: MaterialApp(
        theme: warmPopDark(),
        home: Scaffold(body: MessageBubble(message: msg, isMine: true)),
      ),
    );
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 400));
    Size bubble() => tester.getSize(
      find
          .descendant(
            of: find.byType(ChatBubbleFrame),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(find.byType(SkeletonBreath), findsOneWidget);
    final before = bubble();

    bodyCache.put('pending-body', text);
    body.complete(text);
    await tester.pump();
    await tester.pump();
    expect(find.text(text), findsOneWidget);
    expect(find.byType(SkeletonBreath), findsNothing);
    final after = bubble();
    expect(after.height, before.height);
    expect((after.width - before.width).abs(), lessThan(after.width * 0.15));
  });
}
