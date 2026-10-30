import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/busy_spinner.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/image_message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/video_message_bubble.dart';
import 'package:kuch_bhi/features/media/screens/media_docs_screen.dart';
import 'package:kuch_bhi/features/media/screens/media_viewer_screen.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/services/media_gallery_service.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';
import 'package:pocketbase/pocketbase.dart';

import 'viewer_harness.dart' show inViewer;

/// A2/A4: every entry point pushes the viewer at once, on the thumbnail.
void main() {
  late Completer<LocalMediaFile?> full;
  late int fullReads;
  setUp(() {
    full = Completer<LocalMediaFile?>();
    fullReads = 0;
  });

  List<Override> overrides() => [
        mediaFileProvider.overrideWith((ref, r) {
          if (r.thumb) {
            return LocalMediaFile(
                file: File('/nonexistent/thumb_${r.serverId}.jpg'),
                width: 4,
                height: 3);
          }
          fullReads++;
          return full.future;
        }),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        fontFamilyProvider.overrideWith((ref) => Stream.value(AppFont.system)),
        mediaPageProvider.overrideWith((ref, key) async => [
              if (key.mediaType == 'image')
                RecordModel({
                  'id': 'm1',
                  'message_id': 's1',
                  'created': '2026-10-01 10:00:00Z',
                }),
              if (key.mediaType == 'video')
                RecordModel({
                  'id': 'm2',
                  'message_id': 's2',
                  'duration_seconds': 65,
                  'created': '2026-10-01 10:00:00Z',
                }),
            ]),
      ];

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(ProviderScope(
      overrides: overrides(),
      child: MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(body: Center(child: child)),
      ),
    ));
    await tester.pump();
  }

  /// The push frame builds the new route offstage (Hero measuring); one more
  /// frame puts it on screen, well inside the fade and before any load ends.
  Future<void> nextFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }

  /// The bubble's thumbnail (the frame around it is full width); a video's
  /// centre is its play disc.
  Finder media(Type bubble) => find
      .descendant(
          of: find.byType(bubble),
          matching: bubble == VideoMessageBubble
              ? find.byIcon(Icons.play_arrow)
              : find.byType(Image))
      .first;

  Finder hero(String tag) =>
      inViewer(find.byWidgetPredicate((w) => w is Hero && w.tag == tag));

  ImageMessageBubble photo({required bool mine}) => ImageMessageBubble(
        conversationId: 'c1',
        serverId: 's1',
        isMine: mine,
        isDark: false,
        senderName: 'Aanya',
        createdAt: DateTime(2026, 10, 30, 14, 2),
      );

  VideoMessageBubble video({required bool mine}) => VideoMessageBubble(
        conversationId: 'c1',
        serverId: 's1',
        isMine: mine,
        isDark: false,
        senderName: 'Aanya',
        createdAt: DateTime(2026, 10, 30, 14, 2),
      );

  for (final mine in [true, false]) {
    final who = mine ? 'You' : 'Aanya';
    testWidgets('chat photo (${mine ? 'mine' : 'theirs'}): viewer on the next '
        'frame, load pending, Hero media_s1, title $who', (tester) async {
      await pump(tester, photo(mine: mine));
      await tester.tap(media(ImageMessageBubble));
      await nextFrames(tester);

      expect(find.byType(MediaViewerScreen), findsOneWidget);
      expect(full.isCompleted, isFalse);
      expect(fullReads, 1, reason: 'the viewer starts the load itself');
      expect(inViewer(find.byType(BusySpinner)), findsOneWidget);
      expect(hero('media_s1'), findsOneWidget);
      expect(inViewer(find.text(who)), findsOneWidget);
    });

    testWidgets('chat video (${mine ? 'mine' : 'theirs'}): same, Hero '
        'media_s1, title $who', (tester) async {
      await pump(tester, video(mine: mine));
      await tester.tap(media(VideoMessageBubble));
      await nextFrames(tester);

      expect(find.byType(MediaViewerScreen), findsOneWidget);
      expect(full.isCompleted, isFalse);
      expect(hero('media_s1'), findsOneWidget);
      expect(inViewer(find.text(who)), findsOneWidget);
    });
  }

  testWidgets('no sender name → Photo / Video', (tester) async {
    await pump(
        tester,
        ImageMessageBubble(
            conversationId: 'c1', serverId: 's1', isMine: false, isDark: false));
    await tester.tap(media(ImageMessageBubble));
    await nextFrames(tester);
    expect(inViewer(find.text('Photo')), findsOneWidget);
  });

  testWidgets('Media & docs photo tile pushes with media_docs_{recordId}',
      (tester) async {
    await pump(tester, const MediaDocsScreen(conversationId: 'c1'));
    await tester.pump();
    await tester.tap(find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'media_docs_m1'));
    await nextFrames(tester);

    expect(find.byType(MediaViewerScreen), findsOneWidget);
    expect(full.isCompleted, isFalse);
    expect(hero('media_docs_m1'), findsOneWidget);
    expect(inViewer(find.text('Photo')), findsOneWidget);
  });

  testWidgets('Media & docs video tile pushes with media_docs_{recordId}',
      (tester) async {
    await pump(tester, const MediaDocsScreen(conversationId: 'c1'));
    await tester.tap(find.text('Videos'));
    await tester.pumpAndSettle();
    // Video tiles have no Hero of their own (frozen grid); tap the tile.
    await tester.tap(find.byIcon(Icons.play_arrow));
    await nextFrames(tester);

    expect(find.byType(MediaViewerScreen), findsOneWidget);
    expect(full.isCompleted, isFalse);
    expect(hero('media_docs_m2'), findsOneWidget);
    expect(inViewer(find.text('Video')), findsOneWidget);
  });

  testWidgets('a double tap pushes one viewer', (tester) async {
    await pump(tester, photo(mine: false));
    await tester.tap(media(ImageMessageBubble));
    await tester.tap(media(ImageMessageBubble), warnIfMissed: false);
    await tester.pump();
    await tester.tap(media(ImageMessageBubble), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(MediaViewerScreen), findsOneWidget);
  });
}
