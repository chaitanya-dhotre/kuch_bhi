import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';

import '../offline/char_harness.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CharHarness harness;
  late Directory temp;

  setUp(() async {
    harness = charHarness();
    temp = await Directory.systemTemp.createTemp('media-format-');
  });

  tearDown(() async {
    await harness.close();
    await temp.delete(recursive: true);
  });

  test('GIF and animated WebP are returned unchanged', () async {
    final gif = File('${temp.path}/arbitrary-name.bin');
    final gifBytes = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61];
    await gif.writeAsBytes(gifBytes);
    var called = false;
    final service = MediaUploadService(
      harness.pbClient,
      harness.encryption,
      imageCompressor:
          (
            _,
            __, {
            required minWidth,
            required minHeight,
            required quality,
            required format,
          }) async {
            called = true;
            return XFile(__);
          },
      temporaryDirectoryProvider: () async => temp,
    );
    expect(await service.compressImage(gif, 'normal'), same(gif));
    expect(await gif.readAsBytes(), gifBytes);
    final webp = File('${temp.path}/animated.webp');
    await webp.writeAsBytes(_animatedWebp());
    expect(await service.compressImage(webp, 'normal'), same(webp));
    expect(called, isFalse);
  });

  test(
    'PNG, WebP, JPEG and HEIC choose the matching compressor format',
    () async {
      final png = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
      final webp = _staticWebp();
      final jpeg = <int>[0xff, 0xd8, 0xff, 0xd9];
      final heic = <int>[
        0,
        0,
        0,
        0,
        0x66,
        0x74,
        0x79,
        0x70,
        0x68,
        0x65,
        0x69,
        0x63,
      ];
      final expected = <String, CompressFormat>{
        'png': CompressFormat.png,
        'webp': CompressFormat.webp,
        'jpeg': CompressFormat.jpeg,
        'heic': CompressFormat.jpeg,
      };
      for (final entry in expected.entries) {
        final file = File('${temp.path}/input.${entry.key}');
        await file.writeAsBytes(switch (entry.key) {
          'png' => png,
          'webp' => webp,
          'jpeg' => jpeg,
          _ => heic,
        });
        CompressFormat? actual;
        String? outputPath;
        final service = MediaUploadService(
          harness.pbClient,
          harness.encryption,
          imageCompressor:
              (
                _,
                target, {
                required minWidth,
                required minHeight,
                required quality,
                required format,
              }) async {
                actual = format;
                outputPath = target;
                return XFile(target);
              },
          temporaryDirectoryProvider: () async => temp,
        );
        final result = await service.compressImage(file, 'normal');
        expect(actual, entry.value);
        expect(
          result.path,
          endsWith(
            '.${entry.key == 'jpeg' || entry.key == 'heic' ? 'jpg' : entry.key}',
          ),
        );
        expect(outputPath, result.path);
      }
    },
  );

  test('animated WebP is detected from VP8X flag or ANIM chunk', () async {
    for (final bytes in [_vp8xAnimatedWebp(), _animWebp()]) {
      final file = File('${temp.path}/animated-${bytes.length}.bin');
      await file.writeAsBytes(bytes);
      var called = false;
      final service = MediaUploadService(
        harness.pbClient,
        harness.encryption,
        imageCompressor:
            (
              _,
              target, {
              required minWidth,
              required minHeight,
              required quality,
              required format,
            }) async {
              called = true;
              return XFile(target);
            },
        temporaryDirectoryProvider: () async => temp,
      );
      expect(await service.compressImage(file, 'normal'), same(file));
      expect(called, isFalse);
    }
  });

  test('101 MB is refused before compression', () async {
    final file = File('${temp.path}/large.jpg');
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(101 * 1024 * 1024);
    await handle.close();
    var called = false;
    final service = MediaUploadService(
      harness.pbClient,
      harness.encryption,
      imageCompressor:
          (
            _,
            target, {
            required minWidth,
            required minHeight,
            required quality,
            required format,
          }) async {
            called = true;
            return XFile(target);
          },
      temporaryDirectoryProvider: () async => temp,
    );
    expect(mediaTooBig(file), isTrue);
    if (!mediaTooBig(file)) await service.compressImage(file, 'normal');
    expect(called, isFalse);
  });
}

List<int> _staticWebp() => _webpChunk('VP8 ', [1, 2, 3, 4]);

List<int> _animatedWebp() => [
  ..._riffHeader(10 + 8 + 8 + 4),
  ...'VP8X'.codeUnits,
  10,
  0,
  0,
  0,
  0x02,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  ...'ANIM'.codeUnits,
  0,
  0,
  0,
  0,
];

List<int> _vp8xAnimatedWebp() => [
  ..._riffHeader(18),
  ...'VP8X'.codeUnits,
  10,
  0,
  0,
  0,
  0x02,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
];

List<int> _animWebp() => [
  ..._riffHeader(12),
  ...'ANIM'.codeUnits,
  4,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
];

List<int> _webpChunk(String tag, List<int> content) => [
  ..._riffHeader(4 + 8 + content.length),
  ...tag.codeUnits,
  content.length,
  0,
  0,
  0,
  ...content,
];

List<int> _riffHeader(int size) => [
  ...'RIFF'.codeUnits,
  size & 0xff,
  (size >> 8) & 0xff,
  (size >> 16) & 0xff,
  (size >> 24) & 0xff,
  ...'WEBP'.codeUnits,
];
