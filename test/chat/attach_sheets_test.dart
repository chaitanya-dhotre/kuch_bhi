import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/constants/app_constants.dart';
import 'package:kuch_bhi/features/chat/widgets/attach_sheets.dart';

import '../core/sheet_harness.dart';

Future<Future<String?> Function()> _open(
  WidgetTester tester,
  Future<String?> Function(BuildContext) show, {
  bool large = false,
  String? fontFamily,
}) async {
  Future<String?>? result;
  await pumpHost(
    tester,
    SheetLauncher((context, _) => result = show(context)),
    large: large,
    fontFamily: fontFamily,
  );
  await tapOpen(tester);
  return () => result!;
}

void main() {
  const sources = {
    'Take a photo': 'camera',
    'Photo library': 'gallery',
    'Record a video': 'video_camera',
    'Video library': 'video_gallery',
    'Document': 'document',
  };
  for (final MapEntry(key: label, value: value) in sources.entries) {
    testWidgets('Attach → "$label" returns $value', (tester) async {
      final result = await _open(tester, showAttachSourceSheet);
      expect(find.text('Attach'), findsOneWidget);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(await result(), value);
      expect(find.text('Attach'), findsNothing);
    });
  }

  for (final isVideo in [false, true]) {
    for (final (label, value) in [('Normal', 'normal'), ('High', 'high')]) {
      testWidgets('${isVideo ? 'Video' : 'Photo'} quality → $label',
          (tester) async {
        final result = await _open(
            tester, (c) => showMediaQualitySheet(c, isVideo: isVideo));
        expect(find.text(isVideo ? 'Video quality' : 'Photo quality'),
            findsOneWidget);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(await result(), value);
      });
    }
  }

  testWidgets('dismiss returns null', (tester) async {
    final result = await _open(tester, showAttachSourceSheet);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(await result(), isNull);
  });

  testWidgets('decision 2: photo subtitles carry the AppConstants retention days',
      (tester) async {
    await _open(tester, (c) => showMediaQualitySheet(c, isVideo: false));
    expect(
        find.text('60% quality, up to 1280px · kept '
            '${AppConstants.retentionPhotoNormalDays} days'),
        findsOneWidget);
    expect(
        find.text('90% quality, up to 2560px · kept '
            '${AppConstants.retentionPhotoHighDays} days'),
        findsOneWidget);
  });

  testWidgets('decision 2: video subtitles carry the retention days',
      (tester) async {
    await _open(tester, (c) => showMediaQualitySheet(c, isVideo: true));
    expect(
        find.text('720p · kept ${AppConstants.retentionVideoNormalDays} days'),
        findsOneWidget);
    expect(
        find.text('1080p · kept ${AppConstants.retentionVideoHighDays} days'),
        findsOneWidget);
  });

  for (final font in largeTextFonts) {
    testWidgets('360×200% (${font ?? 'system'}): attach + quality fit',
        (tester) async {
      await _open(tester, showAttachSourceSheet, large: true, fontFamily: font);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Document'), 100,
          scrollable: find.byType(Scrollable).last);
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await _open(tester, (c) => showMediaQualitySheet(c, isVideo: false),
          large: true, fontFamily: font);
      expect(tester.takeException(), isNull);
    });
  }
}
