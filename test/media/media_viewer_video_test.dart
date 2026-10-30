import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/widgets/busy_spinner.dart';
import 'package:kuch_bhi/features/media/screens/media_viewer_screen.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../core/sheet_harness.dart' show largeTextFonts;
import 'viewer_harness.dart';

/// Plays nothing; answers the controller through the plugin's own seam.
class _FakeVideoPlatform extends VideoPlayerPlatform {
  bool failCreate = false;
  bool holdInit = false;
  final _events = <int, StreamController<VideoEvent>>{};
  final disposed = <int>[];
  int _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (failCreate) throw PlatformException(code: 'bad_file');
    final id = _next++;
    _events[id] = StreamController<VideoEvent>();
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    final c = _events[playerId]!;
    if (!holdInit) initialize(playerId);
    return c.stream;
  }

  void initialize(int playerId) => _events[playerId]!.add(VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 65),
        size: const Size(320, 180),
      ));

  void complete(int playerId) => _events[playerId]!
      .add(VideoEvent(eventType: VideoEventType.completed));

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
  @override
  Future<Duration> getPosition(int playerId) async =>
      const Duration(seconds: 12);
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();
}

void main() {
  late _FakeVideoPlatform fake;
  setUp(() => VideoPlayerPlatform.instance = fake = _FakeVideoPlatform());

  Future<void> open(WidgetTester tester,
      {bool large = false,
      AppFont font = AppFont.system,
      Stream<bool>? online}) async {
    await pumpViewer(tester,
        args: viewerArgs(mediaType: 'video'),
        load: () => mediaFile(path: '/nonexistent/v.mp4'),
        online: online,
        large: large,
        font: font);
    await tester.pump();
  }

  testWidgets('poster + R3a until initialised', (tester) async {
    fake.holdInit = true;
    await open(tester);
    expect(inViewer(find.byType(BusySpinner)), findsOneWidget);
    expect(find.byTooltip('Pause'), findsNothing);
    expect(inViewer(find.byType(Hero)), findsOneWidget);

    fake.initialize(0);
    await tester.pump();
    await tester.pump();
    expect(inViewer(find.byType(BusySpinner)), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget, reason: 'E2: autoplay');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('init throws → Couldn\'t play this video. + Try again',
      (tester) async {
    fake.failCreate = true;
    await open(tester);
    expect(find.text("Couldn't play this video."), findsOneWidget);
    expect(find.byTooltip('Save to gallery'), findsNothing);

    fake.failCreate = false;
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text("Couldn't play this video."), findsNothing);
    expect(find.byTooltip('Pause'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disc: Pause playing, Play paused, Play again at the end',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);
    expect(tester.getSemantics(find.byTooltip('Pause')),
        isSemantics(isButton: true, tooltip: 'Pause'));

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(find.byTooltip('Play'), findsOneWidget);

    await tester.tap(find.byTooltip('Play'));
    await tester.pump();
    fake.complete(0);
    await tester.pump();
    await tester.pump();
    expect(find.byTooltip('Play again'), findsOneWidget);
    expect(find.text('1:05'), findsWidgets);
    expect(semanticsStrings(tester), contains('Video position'));
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  // Review fix 1 (E6): the plugin's own observer plays again on resume.
  testWidgets('app to background pauses; back stays paused', (tester) async {
    await open(tester);
    expect(find.byTooltip('Pause'), findsOneWidget);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  // Review fix 4: a loaded file initialising offline is not a network wait.
  testWidgets('offline, file loaded, still initialising: no waiting line',
      (tester) async {
    fake.holdInit = true;
    await open(tester, online: Stream.value(false));
    expect(inViewer(find.byType(BusySpinner)), findsOneWidget);
    expect(find.text('Waiting for a connection'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('swipe-down pops and disposes the controller', (tester) async {
    await open(tester);
    // Off the play disc, which owns its own touches.
    await tester.dragFrom(const Offset(400, 200), const Offset(0, 150));
    await settle(tester);
    expect(find.byType(MediaViewerScreen), findsNothing);
    // controller.dispose() reaches the platform after an async cancel.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(fake.disposed, [0]);
  });

  for (final font in largeTextFonts) {
    testWidgets('360dp × 200% text, ${font ?? 'system'}: strip fits',
        (tester) async {
      await open(tester,
          large: true,
          font: font == null ? AppFont.system : AppFont.jakarta);
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
