/// Albums 12.5 E5–E10 / G1: the pager shell — one item is a pager of one
/// with no counter; a swipe pages only at fit; zoom owns horizontal drags;
/// neighbours read no full file until current; Save acts on the current
/// item; leaving a video page disposes its controller; reduced motion jumps.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';
import 'package:kuch_bhi/features/media/screens/media_viewer_screen.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

import 'viewer_harness.dart';

MediaViewerItem _item(int i, {String type = 'image', String? thumb}) =>
    MediaViewerItem(
      serverId: 's$i',
      mediaType: type,
      heroTag: 'media_s$i',
      thumbPath: thumb,
    );

Future<File> _png(String path, int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
  );
  canvas.drawColor(
    const Color.fromARGB(255, 230, 120, 40),
    BlendMode.src,
  );
  final image = await recorder.endRecording().toImage(w, h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File(path);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

/// Records what Save/share received, and each full-file provider read.
class PagerActions extends FakeMediaActions {
  final saved = <String>[];
  final shared = <String>[];
  @override
  Future<bool> save(String path, {required bool video}) async {
    saved.add(path);
    return await super.save(path, video: video);
  }

  @override
  Future<void> share(String path) async {
    shared.add(path);
    await super.share(path);
  }
}

class PagerCtx {
  PagerCtx({
    required this.loads,
    required this.actions,
    required this.files,
  });
  final List<String> loads;
  final PagerActions actions;
  final Map<String, LocalMediaFile> files;
}

Future<PagerCtx> pumpPager(
  WidgetTester tester, {
  required List<MediaViewerItem> items,
  int initialIndex = 0,
  Map<String, LocalMediaFile> files = const {},
  bool still = false,
}) async {
  final loads = <String>[];
  final actions = PagerActions();
  final args = MediaViewerArgs(
    conversationId: 'c1',
    serverId: items[initialIndex].serverId,
    mediaType: items[initialIndex].mediaType,
    senderName: 'Aanya Kulkarni',
    timestamp: DateTime(2026, 11, 1, 14, 2),
    items: items,
    initialIndex: initialIndex,
  );
  await pumpViewer(
    tester,
    args: args,
    load: () async => null,
    extraOverrides: [
      mediaFileProvider.overrideWith((ref, r) async {
        if (r.thumb) return null;
        loads.add(r.serverId);
        return files[r.serverId];
      }),
      mediaActionsProvider.overrideWithValue(actions),
    ],
    still: still,
  );
  return PagerCtx(loads: loads, actions: actions, files: files);
}

Future<void> _doubleTap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(at);
  await settle(tester);
}

void main() {
  late File thumb;
  late Map<String, LocalMediaFile> photoFiles;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('pager_a');
    addTearDown(() => dir.delete(recursive: true));
    thumb = await _png('${dir.path}/t.png', 4, 4);
    photoFiles = {
      for (var i = 1; i <= 5; i++)
        's$i': LocalMediaFile(
          file: await _png('${dir.path}/p$i.png', 300, 200),
          width: 300,
          height: 200,
        ),
    };
  });

  testWidgets('one item → a pager of one, no counter', (tester) async {
    await pumpPager(tester, items: [_item(1, thumb: thumb.path)]);
    expect(find.text('1 of 1'), findsNothing);
    expect(find.text('Aanya Kulkarni'), findsOneWidget);
    expect(find.byType(MediaViewerScreen), findsOneWidget);
    expect(inViewer(find.byType(Hero)), findsOneWidget);
  });

  testWidgets('swipe left at fit → page 2, counter 2 of 5', (tester) async {
    await pumpPager(
      tester,
      items: [for (var i = 1; i <= 5; i++) _item(i, thumb: thumb.path)],
      files: photoFiles,
    );
    expect(find.text('1 of 5'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await settle(tester);
    expect(find.text('2 of 5'), findsOneWidget);
  });

  testWidgets('leaving a video page disposes its controller', (tester) async {
    final fake = _FakeVideoPlatform();
    final previous = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = fake;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    await pumpPager(
      tester,
      items: [
        _item(1, type: 'video', thumb: thumb.path),
        _item(2, thumb: thumb.path),
      ],
      files: {
        's1': LocalMediaFile(file: thumb, durationSeconds: 65),
        's2': photoFiles['s2']!,
      },
    );
    await settle(tester);
    expect(fake._next, 1, reason: 'the video page made one controller');
    expect(fake.disposed, isEmpty);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await settle(tester);
    expect(find.text('2 of 2'), findsOneWidget);
    // controller.dispose() reaches the platform after an async cancel.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(fake.disposed, [0], reason: 'E8: one controller at a time');
  });

  testWidgets('a playing video with ticking position still hides its chrome '
      'after three seconds', (tester) async {
    final fake = _FakeVideoPlatform();
    final previous = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = fake;
    addTearDown(() => VideoPlayerPlatform.instance = previous);
    await pumpPager(
      tester,
      items: [
        _item(1, type: 'video', thumb: thumb.path),
        _item(2, thumb: thumb.path),
      ],
      files: {'s1': LocalMediaFile(file: thumb, durationSeconds: 65)},
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 3));
    final opacity = tester.widget<AnimatedOpacity>(find.ancestor(
        of: find.byTooltip('Pause'), matching: find.byType(AnimatedOpacity)).first);
    expect(opacity.opacity, 0, reason: 'ticks must not restart the 3 s timer');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('zoomed in, a horizontal drag pans and does not page',
      (tester) async {
    await pumpPager(
      tester,
      items: [for (var i = 1; i <= 5; i++) _item(i, thumb: thumb.path)],
      files: photoFiles,
    );
    await _doubleTap(tester, const Offset(300, 300));
    double zoom() => tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value
        .getMaxScaleOnAxis();
    expect(zoom(), closeTo(2.5, .01));

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await settle(tester);
    expect(find.text('1 of 5'), findsOneWidget, reason: 'E6: no paging');
    expect(zoom(), greaterThan(1.01), reason: 'still zoomed');

    // Back at fit → pages again.
    await _doubleTap(tester, const Offset(300, 300));
    expect(zoom(), closeTo(1, .01));
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await settle(tester);
    expect(find.text('2 of 5'), findsOneWidget);
  });

  testWidgets('rotating while zoomed resets to fit without a build-time '
      'setState, and pages again', (tester) async {
    await pumpPager(
      tester,
      items: [for (var i = 1; i <= 3; i++) _item(i, thumb: thumb.path)],
      files: photoFiles,
    );
    await _doubleTap(tester, const Offset(300, 300));
    tester.view.physicalSize = const Size(900, 1600); // to portrait
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await settle(tester);
    expect(find.text('2 of 3'), findsOneWidget, reason: 'shell saw the reset');
  });

  testWidgets('only the current page requests the full file (E9)',
      (tester) async {
    final ctx = await pumpPager(
      tester,
      items: [for (var i = 1; i <= 5; i++) _item(i, thumb: thumb.path)],
      files: photoFiles,
    );
    expect(ctx.loads, ['s1'], reason: 'a start at page 1 reads s1 only');
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await settle(tester);
    expect(ctx.loads, ['s1', 's2']);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await settle(tester);
    expect(ctx.loads, ['s1', 's2', 's3'], reason: 'no prefetch of s4/s5');
  });

  testWidgets('Save acts on the current item', (tester) async {
    final ctx = await pumpPager(
      tester,
      items: [for (var i = 1; i <= 5; i++) _item(i, thumb: thumb.path)],
      files: photoFiles,
    );
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1200);
    await settle(tester);
    // Wait for the file to load and the Save button to appear
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.tap(find.byTooltip('Save to gallery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(ctx.actions.saved, [ctx.files['s2']!.file.path]);
    expect(ctx.actions.shared, isEmpty);
  });

  testWidgets('reduced motion: no Hero, page changes jump to the item',
      (tester) async {
    await pumpPager(
      tester,
      items: [for (var i = 1; i <= 5; i++) _item(i, thumb: thumb.path)],
      files: photoFiles,
      initialIndex: 2,
      still: true,
    );
    expect(find.text('3 of 5'), findsOneWidget, reason: 'E10: starts at 3');
    expect(inViewer(find.byType(Hero)), findsNothing);
  });
}

/// Plays nothing; answers controller creation through the plugin seam so
/// the video page can initialize and then be disposed on leave.
class _FakeVideoPlatform extends VideoPlayerPlatform {
  final disposed = <int>[];
  final _events = <int, StreamController<VideoEvent>>{};
  int _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    _events[id] = StreamController<VideoEvent>();
    _events[id]!.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 65),
      size: const Size(320, 180),
    ));
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async => disposed.add(playerId);

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  /// Advances 100 ms per read, like a playing video, so the controller
  /// notifies on every position tick.
  int _reads = 0;
  @override
  Future<Duration> getPosition(int playerId) async =>
      Duration(milliseconds: 100 * ++_reads);

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}