import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Re-encodes a picked photo as JPEG with NO metadata: image_picker's resize
/// keeps EXIF, GPS included, and the server copy (avatar, group icon) is
/// readable by every friend or member. Never falls back to the original
/// bytes.
Future<Uint8List> jpegWithoutExif(File file) async {
  final bytes = await FlutterImageCompress.compressWithFile(
    file.absolute.path,
    minWidth: 1024,
    minHeight: 1024,
    quality: 80,
    format: CompressFormat.jpeg,
    keepExif: false,
  );
  if (bytes == null) throw StateError('Photo re-encode failed');
  return bytes;
}
