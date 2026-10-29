import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/features/profile/screens/crop_photo_screen.dart';

// 1×1 PNG.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

File _tmp(String name, List<int> bytes) =>
    File('${Directory.systemTemp.createTempSync().path}/$name')
      ..writeAsBytesSync(bytes);

void main() {
  group('cropRectInImage', () {
    test('square image, no transform = the whole image', () {
      expect(
        cropRectInImage(
            image: const Size(1000, 1000), viewport: 300, m: Matrix4.identity()),
        const Rect.fromLTWH(0, 0, 1000, 1000),
      );
    });

    test('landscape image opened centred = the middle square', () {
      // cover = 0.3 → laid out 600×300; centring shifts x by -150.
      expect(
        cropRectInImage(
          image: const Size(2000, 1000),
          viewport: 300,
          m: Matrix4.translationValues(-150, 0, 0),
        ),
        const Rect.fromLTWH(500, 0, 1000, 1000),
      );
    });

    test('2× zoom halves the side and follows the pan', () {
      final m = Matrix4.translationValues(-300, -300, 0)
        ..multiply(Matrix4.diagonal3Values(2, 2, 1));
      expect(
        cropRectInImage(image: const Size(1000, 1000), viewport: 300, m: m),
        const Rect.fromLTWH(500, 500, 500, 500),
      );
    });

    test('never leaves the image', () {
      final r = cropRectInImage(
        image: const Size(1000, 1000),
        viewport: 300,
        m: Matrix4.translationValues(40, -5000, 0),
      );
      expect(r.left, 0);
      expect(r.bottom, lessThanOrEqualTo(1000));
    });
  });

  Future<Object?> openCrop(WidgetTester tester, File file) async {
    Object? result = 'not popped';
    await tester.pumpWidget(MaterialApp(
      theme: warmPopLight(),
      // The editor's Scaffold hosts the toast in the app.
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<File>(
                MaterialPageRoute(builder: (_) => CropPhotoScreen(file: file)),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Real file IO + image decoding need real async, one hop per await
    // (read, codec, frame), each continued by a pump.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('loads the photo; Cancel returns null', (tester) async {
    Object? result;
    await openCrop(tester, _tmp('p.png', _png)).then((r) => result = r);
    expect(find.text('Move and scale'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(CropPhotoScreen), findsNothing);
    expect(result, isNot(isA<File>()));
  });

  testWidgets('an unreadable photo toasts and closes', (tester) async {
    await openCrop(tester, _tmp('bad.png', [1, 2, 3, 4]));
    expect(find.byType(CropPhotoScreen), findsNothing);
    expect(find.text("Couldn't use that photo."), findsOneWidget);
  });
}
