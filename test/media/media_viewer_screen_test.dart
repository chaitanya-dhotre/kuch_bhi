import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/core/widgets/busy_spinner.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';
import 'package:kuch_bhi/features/media/screens/media_viewer_screen.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

import '../core/sheet_harness.dart' show expectNoTextIn, largeTextFonts;
import 'viewer_harness.dart';

/// A 1×1, 2-frame GIF (black, then white; 100ms each, looping).
final _gif = Uint8List.fromList([
  ...'GIF89a'.codeUnits, 1, 0, 1, 0, 0x80, 0, 0, //
  0, 0, 0, 255, 255, 255, //
  0x21, 0xFF, 0x0B, ...'NETSCAPE2.0'.codeUnits, 3, 1, 0, 0, 0, //
  0x21, 0xF9, 4, 0, 10, 0, 0, 0, 0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0, //
  2, 2, 0x44, 1, 0, //
  0x21, 0xF9, 4, 0, 10, 0, 0, 0, 0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0, //
  2, 2, 0x4C, 1, 0, //
  0x3B,
]);

void main() {
  testWidgets('first frame: thumbnail + R3a while the load is pending',
      (tester) async {
    final pending = Completer<Null>();
    await pumpViewer(tester, load: () => pending.future);

    expect(
        inViewer(find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is FileImage &&
            (w.image as FileImage).file.path == '/nonexistent/thumb.jpg')),
        findsOneWidget);
    expect(inViewer(find.byType(BusySpinner)), findsOneWidget);
    expect(find.byTooltip('Save to gallery'), findsNothing,
        reason: 'B5: no actions on the thumbnail');
    expect(find.text('Waiting for a connection'), findsNothing);
  });

  testWidgets('loaded: full photo, Close/Share/Save buttons, photo node',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpViewer(tester, load: () => mediaFile());

    expect(
        inViewer(find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is FileImage &&
            (w.image as FileImage).file.path == '/nonexistent/full.jpg')),
        findsOneWidget);
    expect(inViewer(find.byType(BusySpinner)), findsNothing);
    for (final label in ['Close', 'Share', 'Save to gallery']) {
      expect(tester.getSemantics(find.byTooltip(label)),
          isSemantics(isButton: true, tooltip: label));
    }
    expect(semanticsStrings(tester),
        contains('Photo from Aanya Kulkarni, Oct 30, 2026 · 14:02'));
    expect(find.text('Aanya Kulkarni'), findsOneWidget);
    expect(find.text('Oct 30, 2026 · 14:02'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('null → Couldn\'t load + Try again, which re-fetches',
      (tester) async {
    var builds = 0;
    await pumpViewer(tester, load: () {
      builds++;
      return null;
    });
    expect(find.text("Couldn't load this photo."), findsOneWidget);
    expect(find.byTooltip('Save to gallery'), findsNothing);
    expect(builds, 1);

    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(builds, 2, reason: 'Try again invalidates the cached failure');
    expect(find.text("Couldn't load this photo."), findsOneWidget);
  });

  testWidgets('offline failure: Try again dimmed once, disabled, hint outside',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpViewer(tester,
        load: () => null, online: Stream.value(false));

    final button = find.widgetWithText(OutlinedButton, 'Try again');
    final dims = find
        .ancestor(of: button, matching: find.byType(Opacity))
        .evaluate()
        .map((e) => (e.widget as Opacity).opacity)
        .where((o) => o < 1);
    expect(dims, [.38]);
    expect(tester.getSemantics(button),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false));
    final hint = find.text('Available online');
    expect(hint, findsOneWidget);
    expect(find.ancestor(of: hint, matching: find.byType(Opacity)), findsNothing);
    semantics.dispose();
  });

  testWidgets('offline while pending: waiting line; back online re-reads',
      (tester) async {
    final online = StreamController<bool>.broadcast();
    addTearDown(online.close);
    var builds = 0;
    final pending = Completer<Null>();
    await pumpViewer(tester, online: online.stream, load: () {
      builds++;
      return pending.future;
    });
    online.add(false);
    await tester.pump();
    expect(find.text('Waiting for a connection'), findsOneWidget);
    expect(builds, 1);

    online.add(true);
    await tester.pump();
    await tester.pump();
    expect(builds, 2, reason: 'D2: invalidate, then read again');
    expect(find.text('Waiting for a connection'), findsNothing);
  });

  testWidgets('blob failed/expired → expired copy, no button', (tester) async {
    await pumpViewer(tester, load: () => null, blob: MediaBlobStatus.expired);
    expect(find.text('This photo has expired.'), findsOneWidget);
    expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a loaded file past its expiry → expired', (tester) async {
    await pumpViewer(tester,
        load: () => mediaFile(
            expiresAt: DateTime.now().subtract(const Duration(hours: 1))));
    expect(find.text('This photo has expired.'), findsOneWidget);
    expect(find.byTooltip('Share'), findsNothing);
  });

  testWidgets("blob failed/decrypt → Can't decrypt, no button", (tester) async {
    await pumpViewer(tester,
        load: () => null, blob: MediaBlobStatus.cantDecrypt);
    expect(find.text("Can't decrypt"), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  // Review fix 2: a blob already failed shows its end state at once, not
  // after the provider's 45s wait.
  testWidgets('blob already expired while the load is pending → expired now',
      (tester) async {
    final pending = Completer<Null>();
    await pumpViewer(tester,
        load: () => pending.future, blob: MediaBlobStatus.expired);
    expect(find.text('This photo has expired.'), findsOneWidget);
    expect(inViewer(find.byType(BusySpinner)), findsNothing);
  });

  // Review fix 3 + D6: an earlier open's result or in-flight load is never
  // reused; the viewer starts its own.
  testWidgets('reopening restarts a cached failure and an in-flight load',
      (tester) async {
    var builds = 0;
    Completer<Null>? pending;
    LocalMediaFile? Function()? now;
    await pumpViewer(tester, load: () {
      builds++;
      final n = now;
      if (n != null) return n();
      return (pending = Completer<Null>()).future;
    });
    expect(builds, 1);
    Future<void> reopen() async {
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      await tester.tap(find.byKey(const Key('open')));
      await settle(tester);
    }

    await reopen();
    expect(builds, 2, reason: 'an in-flight load from the last open restarts');
    expect(pending!.isCompleted, isFalse);

    now = () => null;
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('open')));
    await settle(tester);
    expect(builds, 3);
    expect(find.text("Couldn't load this photo."), findsOneWidget);
    await reopen();
    expect(builds, 4, reason: 'a cached null is cleared on open');
  });

  // Review NIT 5: Media & docs passes the fallback word as the sender.
  testWidgets('no sender: the photo node is not "Photo from Photo"',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpViewer(tester,
        args: viewerArgs(senderName: 'Photo'), load: () => mediaFile());
    expect(semanticsStrings(tester), contains('Photo, Oct 30, 2026 · 14:02'));
    expect(semanticsStrings(tester).where((s) => s.contains('from Photo')),
        isEmpty);
    semantics.dispose();
  });

  // D5 + review NIT 6: a photo that fails to decode gets the load-failed
  // block, and its Try again is local, so it is never dimmed offline.
  testWidgets('decode failure → load-failed block, Try again live offline',
      (tester) async {
    // Fails once the viewer listens (an early error would drop the entry).
    // Earlier tests leave a pending real-IO load under the same path.
    PaintingBinding.instance.imageCache.clear();
    final decode = Completer<ImageInfo>();
    PaintingBinding.instance.imageCache.putIfAbsent(
        FileImage(File('/nonexistent/full.jpg')),
        () => OneFrameImageStreamCompleter(decode.future));
    addTearDown(PaintingBinding.instance.imageCache.clear);
    var builds = 0;
    await pumpViewer(tester, online: Stream.value(false), load: () {
      builds++;
      return mediaFile();
    });
    decode.completeError(Exception('corrupt'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('corrupt'), findsNothing);
    expect(find.text("Couldn't load this photo."), findsOneWidget);
    expect(find.byTooltip('Save to gallery'), findsNothing);
    expect(find.text('Available online'), findsNothing);
    final dims = find
        .ancestor(
            of: find.widgetWithText(OutlinedButton, 'Try again'),
            matching: find.byType(Opacity))
        .evaluate()
        .where((e) => (e.widget as Opacity).opacity < 1);
    expect(dims, isEmpty);
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(builds, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap toggles the chrome (hidden = out of semantics)',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpViewer(tester, load: () => mediaFile());
    expect(semanticsStrings(tester), contains('Close'));

    await tester.tapAt(const Offset(400, 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(semanticsStrings(tester), isNot(contains('Close')));
    expect(semanticsStrings(tester), isNot(contains('Share')));

    await tester.tapAt(const Offset(400, 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200)); // fade-in
    expect(semanticsStrings(tester), contains('Close'));
    semantics.dispose();
  });

  testWidgets('with accessibleNavigation the chrome never hides',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpViewer(tester, load: () => mediaFile(), a11y: true);
    await tester.tapAt(const Offset(400, 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 200)); // fade-in
    expect(semanticsStrings(tester), contains('Close'));
    semantics.dispose();
  });

  testWidgets('save → Saved to gallery; busy blocks a second tap',
      (tester) async {
    final actions = FakeMediaActions()..hold = Completer<void>();
    await pumpViewer(tester, load: () => mediaFile(), actions: actions);
    await tester.tap(find.byTooltip('Save to gallery'));
    await tester.pump();
    expect(
        find.descendant(
            of: find.byTooltip('Save to gallery'),
            matching: find.byType(BusySpinner)),
        findsOneWidget);
    await tester.tap(find.byTooltip('Save to gallery'));
    await tester.pump();
    expect(actions.saves, 1);

    actions.hold!.complete();
    await settle(tester);
    expect(inViewer(find.text('Saved to gallery')), findsOneWidget);
  });

  testWidgets('save refused → settings copy', (tester) async {
    final actions = FakeMediaActions()..saveResult = false;
    await pumpViewer(tester, load: () => mediaFile(), actions: actions);
    await tester.tap(find.byTooltip('Save to gallery'));
    await settle(tester);
    expect(inViewer(find.text('Allow photo access in Settings to save.')), findsOneWidget);
  });

  testWidgets('save throws → fixed copy, never the exception text',
      (tester) async {
    final actions = FakeMediaActions()..saveError = Exception('boom');
    await pumpViewer(tester, load: () => mediaFile(), actions: actions);
    await tester.tap(find.byTooltip('Save to gallery'));
    await settle(tester);
    expect(inViewer(find.text("Couldn't save. Try again.")), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('share throws → Couldn\'t share.', (tester) async {
    final actions = FakeMediaActions()..shareError = Exception('boom');
    await pumpViewer(tester, load: () => mediaFile(), actions: actions);
    await tester.tap(find.byTooltip('Share'));
    await settle(tester);
    expect(actions.shares, 1);
    expect(inViewer(find.text("Couldn't share.")), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('drag 150dp at fit pops', (tester) async {
    await pumpViewer(tester, load: () => mediaFile());
    await tester.drag(find.byType(MediaViewerScreen), const Offset(0, 150));
    await settle(tester);
    expect(find.byType(MediaViewerScreen), findsNothing);
  });

  testWidgets('a short drag snaps back', (tester) async {
    await pumpViewer(tester, load: () => mediaFile());
    await tester.drag(find.byType(MediaViewerScreen), const Offset(0, 60));
    await settle(tester);
    expect(find.byType(MediaViewerScreen), findsOneWidget);
    final shift = tester
        .widget<Transform>(inViewer(find.byType(Transform)).first)
        .transform
        .getTranslation()
        .y;
    expect(shift, 0);
  });

  testWidgets('zoomed by a double tap, the same drag pans and never pops',
      (tester) async {
    await pumpViewer(tester, load: () => mediaFile());
    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(300, 300));
    await settle(tester);
    final zoom = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!
        .value
        .getMaxScaleOnAxis();
    expect(zoom, closeTo(2.5, .01));

    await tester.drag(find.byType(MediaViewerScreen), const Offset(0, 150));
    await settle(tester);
    expect(find.byType(MediaViewerScreen), findsOneWidget);
  });

  testWidgets('Hero on the thumbnail; none under reduced motion',
      (tester) async {
    await pumpViewer(tester, load: () => mediaFile());
    expect(inViewer(find.byType(Hero)), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    await pumpViewer(tester, load: () => mediaFile(), still: true);
    expect(inViewer(find.byType(Hero)), findsNothing);
  });

  testWidgets('system UI: edge-to-edge open, immersive hidden, edge-to-edge closed',
      (tester) async {
    final modes = recordUiModes(tester);
    await pumpViewer(tester, load: () => mediaFile());
    expect(modes, ['SystemUiMode.edgeToEdge']);

    await tester.tapAt(const Offset(400, 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(modes.last, 'SystemUiMode.immersiveSticky');
    await tester.tapAt(const Offset(400, 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(modes.last, 'SystemUiMode.edgeToEdge');

    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    expect(find.byType(MediaViewerScreen), findsNothing);
    expect(modes.last, 'SystemUiMode.edgeToEdge');
  });

  testWidgets('an animated GIF advances a frame',
      timeout: const Timeout(Duration(seconds: 30)), (tester) async {
    // Seed the cache with the real 2-frame codec under the viewer's key, so
    // no file IO is needed; frames still come from the engine decoder.
    const path = '/nonexistent/a.gif';
    final codec = await tester.runAsync(() => ui.instantiateImageCodec(_gif));
    PaintingBinding.instance.imageCache.putIfAbsent(
        FileImage(File(path)),
        () => MultiFrameImageStreamCompleter(
            codec: Future.value(codec!), scale: 1));
    addTearDown(PaintingBinding.instance.imageCache.clear);

    await pumpViewer(tester, load: () => mediaFile(path: path));
    final full = inViewer(find.byWidgetPredicate(
        (w) => w is RawImage && w.image != null));
    Future<void> realWait() => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    for (var i = 0; i < 10 && full.evaluate().isEmpty; i++) {
      await realWait();
      await tester.pump(const Duration(milliseconds: 20));
    }
    final first = tester.widget<RawImage>(full).image!;

    var second = first;
    for (var i = 0; i < 10 && second.isCloneOf(first); i++) {
      await tester.pump(const Duration(milliseconds: 60));
      await realWait();
      await tester.pump();
      second = tester.widget<RawImage>(full).image!;
    }
    expect(second.isCloneOf(first), isFalse, reason: 'C5: the GIF animates');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no text in accent or error (loaded, failed)', (tester) async {
    await pumpViewer(tester,
        load: () => mediaFile(
            expiresAt: DateTime.now().add(const Duration(days: 3))));
    final banned = [WarmPopTokens.accent, WarmPopTokens.error];
    expectNoTextIn(tester, banned, find.byType(MediaViewerScreen));
    await tester.pumpWidget(const SizedBox());

    await pumpViewer(tester, load: () => null, online: Stream.value(false));
    expectNoTextIn(tester, banned, find.byType(MediaViewerScreen));
  });

  testWidgets('expiry line appears once loaded, not before; none without a date',
      (tester) async {
    final pending = Completer<Null>();
    final file = mediaFile(expiresAt: DateTime.now().add(const Duration(days: 3, hours: 2)));
    LocalMediaFile? result;
    await pumpViewer(tester, load: () async {
      await pending.future;
      return result;
    });
    expect(find.textContaining('Expires'), findsNothing);
    result = file;
    pending.complete();
    await settle(tester);
    expect(find.text('Expires in 3 days'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());

    await pumpViewer(tester, load: () => mediaFile());
    expect(find.textContaining('Expires'), findsNothing);
  });

  for (final font in largeTextFonts) {
    final appFont = font == null ? AppFont.system : AppFont.jakarta;
    testWidgets('360dp × 200% text, ${font ?? 'system'}: no overflow',
        (tester) async {
      final longName = viewerArgs(
          senderName: 'Aanya Kulkarni-Deshpande from the Pune office');
      final variants = <(FutureOr<LocalMediaFile?> Function(), MediaBlobStatus, Stream<bool>?)>[
        (() => mediaFile(expiresAt: DateTime.now().add(const Duration(days: 40))), MediaBlobStatus.other, null),
        (() => null, MediaBlobStatus.other, Stream.value(false)),
        (() => null, MediaBlobStatus.expired, null),
        (() => null, MediaBlobStatus.cantDecrypt, null),
        (() => Completer<Null>().future, MediaBlobStatus.other, Stream.value(false)),
      ];
      for (final (load, blob, online) in variants) {
        await pumpViewer(tester,
            args: longName,
            load: load,
            blob: blob,
            online: online,
            large: true,
            font: appFont);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      expect(find.byType(MediaViewerScreen), findsNothing);
    });
  }
}
