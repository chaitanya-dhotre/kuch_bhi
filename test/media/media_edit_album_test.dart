/// Albums 12.5 B4 / C14 amendment: the editor's album mode — a strip of
/// thumbnails, per-item state, Remove, GIF handling and a list result.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/media/screens/media_edit_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1 item in album mode → strip of 1, the first selected', (tester) async {
    final files = [(await tester.runAsync(() => _imageFile(0, w: 100, h: 100)))!];
    addTearDown(() {
      for (final f in files) {
        if (f.existsSync()) f.deleteSync();
      }
    });

    await tester.pumpWidget(MaterialApp(
      theme: warmPopLight(),
      home: MediaEditScreen.album(items: [
        for (final f in files) MediaEditItem(file: f, type: 'image'),
      ]),
    ));

    // Wait for the strip to render
    await _pumpLoaded(tester);

    expect(find.bySemanticsLabel(RegExp('Item .* of .*')), findsNothing,
        reason: 'single-item editor does not show the album strip');
    expect(find.text('Crop'), findsOneWidget, reason: 'tools for the current');
    expect(find.text('Send'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('3 items → a strip of 3, the first selected', (tester) async {
    final files = [for (var i = 0; i < 3; i++) (await tester.runAsync(() => _imageFile(i, w: 100, h: 100)))!];
    addTearDown(() {
      for (final f in files) {
        if (f.existsSync()) f.deleteSync();
      }
    });

    await tester.pumpWidget(MaterialApp(
      theme: warmPopLight(),
      home: MediaEditScreen.album(items: [
        for (final f in files) MediaEditItem(file: f, type: 'image'),
      ]),
    ));

    await _pumpLoaded(tester);

    // The strip's three tap targets (Item 1..3 of 3).
    for (var i = 1; i <= 3; i++) {
      expect(find.bySemanticsLabel(RegExp('Item $i of 3')), findsWidgets,
          reason: 'strip item $i');
    }
    expect(find.text('Crop'), findsOneWidget, reason: 'tools for the current');
    expect(find.text('Send'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Send returns the three source paths in pick order',
      (tester) async {
    final files = [for (var i = 0; i < 3; i++)
      (await tester.runAsync(() => _imageFile(i, w: 100, h: 100)))!];
    addTearDown(() {
      for (final f in files) {
        if (f.existsSync()) f.deleteSync();
      }
    });
    List<MediaEditResult>? result;
    await tester.pumpWidget(_albumHost(files, (value) => result = value));
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpLoaded(tester);
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(result?.map((r) => r.sourcePath).toList(),
        files.map((f) => f.path).toList());
    expect(result?.every((r) => r.file == null), isTrue);
  });

  testWidgets('Rotate on item 2 exports only item 2', (tester) async {
    final files = [for (var i = 0; i < 3; i++)
      (await tester.runAsync(() => _imageFile(i, w: 100, h: 100)))!];
    addTearDown(() {
      for (final f in files) {
        if (f.existsSync()) f.deleteSync();
      }
    });
    List<MediaEditResult>? result;
    await tester.pumpWidget(_albumHost(files, (value) => result = value));
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpLoaded(tester);
    await tester.tap(find.bySemanticsLabel(RegExp('Item 2 of 3')).first);
    await _pumpLoaded(tester);
    await tester.ensureVisible(find.text('Rotate'));
    await tester.ensureVisible(find.text('Rotate'));
    await tester.tap(find.text('Rotate'));
    await tester.pump();
    await tester.tap(find.text('Send'));
    // The PNG export is real engine work: let it run, then let the pop land.
    for (var i = 0; i < 20 && result == null; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(result?.map((r) => r.file == null).toList(), [true, false, true]);
    expect(result?[1].sourcePath, files[1].path);
  });

  testWidgets('Remove down to 1 → the strip hides and the editor is single',
      (tester) async {
    final files = [for (var i = 0; i < 3; i++) (await tester.runAsync(() => _imageFile(i, w: 100, h: 100)))!];
    addTearDown(() {
      for (final f in files) {
        if (f.existsSync()) f.deleteSync();
      }
    });

    await tester.pumpWidget(MaterialApp(
      theme: warmPopLight(),
      home: MediaEditScreen.album(items: [
        for (final f in files) MediaEditItem(file: f, type: 'image'),
      ]),
    ));

    await _pumpLoaded(tester);

    // The selected item (1) carries the Remove control; tap it twice.
    for (var remaining = 3; remaining >= 2; remaining--) {
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pump();
      if (remaining == 3) {
        expect(find.bySemanticsLabel(RegExp('Item .* of 2')), findsWidgets,
            reason: 'the strip remains with two items');
      }
    }
    expect(find.bySemanticsLabel(RegExp('Item 1 of 1')), findsNothing,
        reason: 'B4: the strip is hidden with one item left');
    expect(find.text('Crop'), findsOneWidget, reason: 'single editor remains');
    expect(find.text('Rotate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Remove down to 1, then Send → a list of the one left',
      (tester) async {
    final files = [for (var i = 0; i < 3; i++)
      (await tester.runAsync(() => _imageFile(i, w: 100, h: 100)))!];
    addTearDown(() {
      for (final f in files) {
        if (f.existsSync()) f.deleteSync();
      }
    });
    List<MediaEditResult>? result;
    await tester.pumpWidget(_albumHost(files, (value) => result = value));
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpLoaded(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pump();
    }
    await _pumpLoaded(tester);
    await tester.tap(find.text('Send'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(result, hasLength(1));
  });

  testWidgets('a GIF item keeps the no-tools caption while the strip stays',
      (tester) async {
    final gif = File(
        '${Directory.systemTemp.path}/album_edit_${DateTime.now().microsecondsSinceEpoch}.gif')
      ..writeAsBytesSync(_gif1x1);
    addTearDown(() {
      if (gif.existsSync()) gif.deleteSync();
    });
    final photo = (await tester.runAsync(() => _imageFile(0, w: 100, h: 100)))!;
    addTearDown(() {
      if (photo.existsSync()) photo.deleteSync();
    });

    await tester.pumpWidget(MaterialApp(
      theme: warmPopLight(),
      home: MediaEditScreen.album(items: [
        MediaEditItem(file: photo, type: 'image'),
        MediaEditItem(file: gif, type: 'image'),
      ]),
    ));

    await _pumpLoaded(tester);

    // Select the GIF (item 2): no tools, the caption, and the strip stays.
    await tester.tap(find.bySemanticsLabel(RegExp('Item 2 of 2')).first);
    await _pumpLoaded(tester);
    expect(find.text('GIFs are sent as they are.'), findsOneWidget);
    expect(find.text('Crop'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Item 1 of 2')), findsWidgets,
        reason: 'the strip is still there');
    expect(find.text('Send'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('close with an edit → Discard changes?', (tester) async {
    final files = [for (var i = 0; i < 2; i++) (await tester.runAsync(() => _imageFile(i, w: 100, h: 100)))!];
    addTearDown(() {
      for (final f in files) {
        if (f.existsSync()) f.deleteSync();
      }
    });

    List<MediaEditResult>? result;
    await tester.pumpWidget(_albumHost(files, (value) => result = value));
    await tester.tap(find.text('Open'));
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpLoaded(tester);

    await tester.tap(find.text('Rotate'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pump();
    await tester.pump();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final font in [null, 'PlusJakartaSans']) {
    testWidgets('360×200% (${font ?? 'system'}): the album editor fits',
        (tester) async {
      final files = [for (var i = 0; i < 3; i++) (await tester.runAsync(() => _imageFile(i, w: 100, h: 100)))!];
      addTearDown(() {
        for (final f in files) {
          if (f.existsSync()) f.deleteSync();
        }
      });

      await tester.pumpWidget(MaterialApp(
        theme: warmPopLight(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: DefaultTextStyle.merge(
              style: TextStyle(fontFamily: font), child: child!),
        ),
        home: MediaEditScreen.album(items: [
          for (final f in files) MediaEditItem(file: f, type: 'image'),
        ]),
      ));

      await _pumpLoaded(tester);
      expect(tester.takeException(), isNull);

      expect(tester.takeException(), isNull);
    });
  }
}

Widget _albumHost(
  List<File> files,
  void Function(List<MediaEditResult>?) onResult,
) =>
    MaterialApp(
      theme: warmPopLight(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await Navigator.of(context)
                  .push<List<MediaEditResult>>(
                MaterialPageRoute(
                  builder: (_) => MediaEditScreen.album(items: [
                    for (final f in files)
                      MediaEditItem(file: f, type: 'image'),
                  ]),
                ),
              );
              onResult(result);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

Future<void> _pumpLoaded(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)));
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
}

Future<File> _imageFile(int i, {int w = 100, int h = 100}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  canvas.drawColor(Colors.orange.shade300, BlendMode.src);
  final image = await recorder.endRecording().toImage(w, h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File(
    '${Directory.systemTemp.path}/edit_album_${i}_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(Uint8List.fromList(bytes!.buffer.asUint8List()));
  return file;
}

/// A valid 1×1 GIF89a.
const _gif1x1 = <int>[
  0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00,
  0x00, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x21, 0xF9, 0x04, 0x01, 0x00,
  0x00, 0x00, 0x00, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
  0x00, 0x02, 0x02, 0x44, 0x01, 0x00, 0x3B,
];
