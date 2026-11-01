import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';

import 'package:kuch_bhi/features/media/screens/media_edit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('photo editor exposes crop and draw tools', (tester) async {
    final file = (await tester.runAsync(() => _imageFile(400, 300)))!;
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: warmPopLight(),
        home: MediaEditScreen(file: file, type: 'image'),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    expect(find.text('Crop'), findsOneWidget);
    expect(find.text('Draw'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('Square'), findsOneWidget);
    expect(find.text('Rotate'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('point mapping and clockwise rotation use source image pixels', () {
    expect(
      rotateMediaPointClockwise(const Offset(20, 30), const Size(400, 300)),
      const Offset(270, 20),
    );
    final centered = Matrix4.identity()..setTranslationRaw(-50, 0, 0);
    final point = mediaTouchToImagePixels(
      point: const Offset(50, 50),
      image: const Size(400, 300),
      frame: const Size(300, 300),
      transform: centered,
    );
    expect(point.dx, closeTo(100, .01));
    expect(point.dy, closeTo(50, .01));
    final rect = mediaFrameToSourceRect(
      image: const Size(400, 300),
      frame: const Size(300, 300),
      transform: centered,
    );
    expect(rect, const Rect.fromLTWH(50, 0, 300, 300));
  });

  test('panning changes the exported crop rectangle', () {
    final rect = mediaFrameToSourceRect(
      image: const Size(400, 300),
      frame: const Size(300, 300),
      transform: Matrix4.identity()..setTranslationRaw(-30, 0, 0),
    );
    expect(rect, const Rect.fromLTWH(30, 0, 300, 300));
  });

  test('Square exports a source-resolution square PNG', () async {
    final source = await _makeImage(400, 300);
    final centered = Matrix4.identity()..setTranslationRaw(-50, 0, 0);
    final bytes = await mediaCropPngBytes(
      image: source,
      frame: const Size(300, 300),
      transform: centered,
    );
    final dimensions = await _pngSize(bytes);
    source.dispose();
    expect(dimensions, (300, 300));
  });

  test('Rotate then Original export swaps source dimensions', () async {
    final source = await _makeImage(400, 300);
    final rotated = await rotateMediaImageClockwise(source);
    final bytes = await mediaCropPngBytes(
      image: rotated,
      frame: const Size(300, 400),
      transform: Matrix4.identity(),
    );
    final dimensions = await _pngSize(bytes);
    source.dispose();
    rotated.dispose();
    expect(dimensions, (300, 400));
  });

  test('drawn stroke changes pixels and undo restores the no-stroke PNG', () async {
    final source = await _makeImage(400, 300);
    final transform = Matrix4.identity()..setTranslationRaw(-50, 0, 0);
    final baseline = await mediaCropPngBytes(
      image: source,
      frame: const Size(300, 300),
      transform: transform,
    );
    const stroke = [Offset(200, 150), Offset(210, 150)];
    final drawn = await mediaCropPngBytes(
      image: source,
      frame: const Size(300, 300),
      transform: transform,
      strokes: [stroke],
      strokeColors: const [Color(0xFFFFFFFF)],
    );
    final undone = await mediaCropPngBytes(
      image: source,
      frame: const Size(300, 300),
      transform: transform,
      strokes: const [],
      strokeColors: const [],
    );
    expect(drawn, isNot(equals(baseline)));
    expect(undone, equals(baseline));
    source.dispose();
  });

  // Host that pushes the editor and records what it pops with.
  Future<List<Object?>> openEditor(WidgetTester tester, File file,
      {bool large = false, String? font}) async {
    if (large) {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    final popped = <Object?>[];
    await tester.pumpWidget(MaterialApp(
      theme: warmPopLight(),
      builder: large
          ? (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2)),
                child: DefaultTextStyle.merge(
                    style: TextStyle(fontFamily: font), child: child!),
              )
          : null,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => popped.add(await Navigator.of(context).push(
                MaterialPageRoute<MediaEditResult>(
                    builder: (_) => MediaEditScreen(file: file, type: 'image')))),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    // Build the editor in the real zone so its file read + decode can finish.
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump(const Duration(milliseconds: 400));
    // The load is a chain of real file reads + decodes: each step needs real
    // time, then a pump to run its continuation.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    return popped;
  }

  testWidgets('GIF: no tools, the caption, Send pops with no new file',
      (tester) async {
    final file = File(
        '${Directory.systemTemp.path}/edit_${DateTime.now().microsecondsSinceEpoch}.bin')
      ..writeAsBytesSync(_gif1x1);
    addTearDown(() => file.existsSync() ? file.deleteSync() : null);
    final popped = await openEditor(tester, file);
    expect(find.text('GIFs are sent as they are.'), findsOneWidget);
    for (final tool in ['Crop', 'Draw', 'Rotate', 'Square']) {
      expect(find.text(tool), findsNothing);
    }
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect((popped.single as MediaEditResult?)?.file, isNull,
        reason: 'the GIF goes out as picked');
  });

  testWidgets('Close with no edits pops null without a dialog', (tester) async {
    final file = (await tester.runAsync(() => _imageFile(400, 300)))!;
    addTearDown(() => file.existsSync() ? file.deleteSync() : null);
    final popped = await openEditor(tester, file);
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Discard changes?'), findsNothing);
    expect(popped, [null]);
  });

  testWidgets('Close (or Android back) after Rotate asks first; Discard pops '
      'null', (tester) async {
    final file = (await tester.runAsync(() => _imageFile(400, 300)))!;
    addTearDown(() => file.existsSync() ? file.deleteSync() : null);
    final popped = await openEditor(tester, file);
    await tester.tap(find.text('Rotate'));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.binding.handlePopRoute(); // Android back
    await tester.pump();
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.text('Your crop and drawing will be lost.'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(popped, [null]);
  });

  for (final font in [null, 'PlusJakartaSans']) {
    testWidgets('360dp at 200% text (${font ?? 'system'}): photo editor and '
        'Draw tools fit', (tester) async {
      final file = (await tester.runAsync(() => _imageFile(400, 300)))!;
      addTearDown(() => file.existsSync() ? file.deleteSync() : null);
      await openEditor(tester, file, large: true, font: font);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Draw'));
      await tester.pump();
      expect(find.text('Undo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<ui.Image> _makeImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.orange, BlendMode.src);
  return recorder.endRecording().toImage(width, height);
}

Future<(int, int)> _pngSize(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final image = (await codec.getNextFrame()).image;
  final size = (image.width, image.height);
  image.dispose();
  return size;

}

Future<File> _imageFile(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  canvas.drawColor(Colors.orange, BlendMode.src);
  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(
    '${Directory.systemTemp.path}/edit_test_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file;
}

/// A valid 1×1 GIF89a.
const _gif1x1 = <int>[
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00,
  0x00, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x21, 0xF9, 0x04, 0x01, 0x00,
  0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
  0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3B,
];
