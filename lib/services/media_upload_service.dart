import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:video_compress/video_compress.dart';

import '../core/constants/app_constants.dart';
import '../core/network/pocketbase_client.dart';
import 'encryption_service.dart';
import 'upload_progress.dart';

/// Info about a decrypted (or legacy plaintext) media file on local disk.
class LocalMediaFile {
  const LocalMediaFile({
    required this.file,
    this.width,
    this.height,
    this.durationSeconds,
    this.expiresAt,
    this.mimeType,
    this.fileName,
    this.fileSize,
  });
  final File file;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final DateTime? expiresAt;
  final String? mimeType;
  final String? fileName;

  /// The full file's size from the server row (E2: "0:42 · 8.1 MB").
  final int? fileSize;
}

typedef ImageCompressor =
    Future<XFile?> Function(
      String source,
      String target, {
      required int minWidth,
      required int minHeight,
      required int quality,
      required CompressFormat format,
    });

bool mediaTooBig(File file) =>
    file.existsSync() &&
    file.lengthSync() > AppConstants.maxFileSizeMb * 1024 * 1024;

class MediaUploadService {
  MediaUploadService(
    this._pbClient,
    this._encryption, {
    this.imageCompressor,
    this.temporaryDirectoryProvider,
  });

  final PocketBaseClient _pbClient;
  final EncryptionService _encryption;
  final ImageCompressor? imageCompressor;
  final Future<Directory> Function()? temporaryDirectoryProvider;
  PocketBase get _pb => _pbClient.pb;

  /// Retention per bible §11: expires_at is set at upload time by type+quality.
  static DateTime retentionExpiry(String mediaType, String quality) {
    final days = switch (mediaType) {
      'voice' => AppConstants.retentionVoiceDays,
      'image' =>
        quality == 'high'
            ? AppConstants.retentionPhotoHighDays
            : AppConstants.retentionPhotoNormalDays,
      'video' =>
        quality == 'high'
            ? AppConstants.retentionVideoHighDays
            : AppConstants.retentionVideoNormalDays,
      'document' => AppConstants.retentionVoiceDays, // docs: 60 days
      _ => AppConstants.retentionVideoNormalDays,
    };
    return DateTime.now().add(Duration(days: days));
  }

  // ── E2E media encryption helpers ──────────────────────────────────────

  /// Encrypts [bytes] with [convKey]; returns (encryptedBytes, ivBase64).
  Future<(Uint8List, String)> _encryptFileBytes(
    List<int> bytes,
    List<int> convKey,
  ) async {
    final res = await _encryption.encryptBytes(bytes, convKey);
    // encryptBytes returns base64 ciphertext; we upload the RAW encrypted
    // bytes (decoded) to avoid a 33% base64 size penalty on the server.
    return (Uint8List.fromList(base64Decode(res.ciphertext)), res.iv);
  }

  static Uint8List base64Decode(String s) =>
      Uint8List.fromList(const Base64Decoder().convert(s));

  /// With a ticket the encrypted bytes go out as a counted stream (upload
  /// progress, cancel, stall bound); without one, exactly as before.
  static http.MultipartFile _part(
    String field,
    Uint8List bytes,
    String name,
    UploadTicket? ticket,
  ) => ticket == null
      ? http.MultipartFile.fromBytes(field, bytes, filename: name)
      : http.MultipartFile(
          field,
          ticket.counted(bytes),
          bytes.length,
          filename: name,
        );

  static Future<T> _guarded<T>(UploadTicket? ticket, Future<T> request) =>
      ticket == null ? request : ticket.guard(request);

  // ── Voice ─────────────────────────────────────────────────────────────

  /// Uploads an E2E-encrypted voice recording. Returns the record ID.
  Future<String> uploadVoice(
    File audioFile,
    String conversationId,
    int durationSeconds,
    String messageServerId,
    List<int> convKey, {
    UploadTicket? ticket,
    String? sentName,
  }) async {
    final fileName = sentName ?? audioFile.uri.pathSegments.last;
    final rawBytes = await audioFile.readAsBytes();
    final (encBytes, iv) = await _encryptFileBytes(rawBytes, convKey);
    final expiresAt = retentionExpiry('voice', 'normal');

    debugPrint(
      '[Media] Uploading encrypted voice: $fileName, size: ${encBytes.length}',
    );

    ticket?.total = encBytes.length;

    final record = await _guarded(
      ticket,
      _pb
          .collection('message_media')
          .create(
            body: {
              'message_id': messageServerId,
              'conversation_id': conversationId,
              'media_type': 'voice',
              'file_name': fileName,
              'file_size': rawBytes.length,
              'duration_seconds': durationSeconds,
              'expires_at': expiresAt.toUtc().toIso8601String(),
              'quality': 'normal',
              'file_iv': iv,
            },
            files: [_part('file', encBytes, '$fileName.enc', ticket)],
          ),
    );

    debugPrint('[Media] Voice uploaded, mediaId: ${record.id}');
    return record.id;
  }

  // ── Image ────────────────────────────────────────────────────

  /// Compresses an image to the specified quality preset.
  /// Returns a new File in the cache directory.
  Future<File> compressImage(
    File original,
    String quality, {
    String? formatHint,
  }) async {
    final bytes = await original.readAsBytes();
    final isGif = _isGif(bytes);
    final isWebp = _isWebp(bytes);
    final animatedWebp = isWebp && _isAnimatedWebp(bytes);
    if (isGif || animatedWebp) return original;
    final tmpDir =
        await (temporaryDirectoryProvider ?? getTemporaryDirectory)();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final kind = formatHint ?? imageFormatHint(bytes);
    final format = kind == 'png'
        ? CompressFormat.png
        : kind == 'webp'
        ? CompressFormat.webp
        : CompressFormat.jpeg;
    final extension = switch (format) {
      CompressFormat.png => 'png',
      CompressFormat.webp => 'webp',
      _ => 'jpg',
    };
    final outPath = '${tmpDir.path}/img_${quality}_$ts.$extension';

    final minSide = quality == 'high' ? 2560 : 1280;
    final compQuality = quality == 'high' ? 90 : 60;

    final result = await (imageCompressor ?? _defaultImageCompressor)(
      original.absolute.path,
      outPath,
      minWidth: minSide,
      minHeight: minSide,
      quality: compQuality,
      format: format,
    );

    if (result == null) throw Exception('Image compression failed');
    return File(result.path);
  }

  static Future<XFile?> _defaultImageCompressor(
    String source,
    String target, {
    required int minWidth,
    required int minHeight,
    required int quality,
    required CompressFormat format,
  }) => FlutterImageCompress.compressAndGetFile(
    source,
    target,
    minWidth: minWidth,
    minHeight: minHeight,
    quality: quality,
    format: format,
  );

  static bool _isWebp(List<int> bytes) =>
      bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';

  static String imageFormatHint(List<int> bytes) {
    if (_isWebp(bytes)) return 'webp';
    if (bytes.length >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50) {
      return 'png';
    }
    return 'jpeg';
  }

  static bool _isAnimatedWebp(List<int> bytes) {
    if (!_isWebp(bytes)) return false;
    for (var i = 12; i + 8 <= bytes.length;) {
      final tag = String.fromCharCodes(bytes.sublist(i, i + 4));
      final length =
          bytes[i + 4] |
          bytes[i + 5] << 8 |
          bytes[i + 6] << 16 |
          bytes[i + 7] << 24;
      if (tag == 'ANIM') {
        return true;
      }
      if (tag == 'VP8X' &&
          length > 0 &&
          i + 8 < bytes.length &&
          bytes[i + 8] & 0x02 != 0) {
        return true;
      }
      i += 8 + length + (length.isOdd ? 1 : 0);
    }
    return false;
  }

  /// [seconds] → video_compress's thumbnail position. Its Android side hands
  /// the value straight to getFrameAtTime, which takes MICROseconds (the
  /// Dart doc says milliseconds; iOS reads milliseconds).
  static int _thumbPosition(int seconds) =>
      seconds < 0 ? -1 : seconds * (Platform.isAndroid ? 1000000 : 1000);

  static bool _isGif(List<int> bytes) =>
      bytes.length >= 6 && String.fromCharCodes(bytes.sublist(0, 3)) == 'GIF';

  static Future<bool> isAnimatedImage(File file) async {
    final bytes = await file.readAsBytes();
    return _isGif(bytes) || _isAnimatedWebp(bytes);
  }

  /// Generates a 640px thumbnail at 70% quality: a 210dp bubble is ~630px on
  /// a 3x screen, and the old 200px one read as pixelated.
  Future<File> generateImageThumbnail(File image) async {
    final tmpDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final outPath = '${tmpDir.path}/thumb_$ts.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      image.absolute.path,
      outPath,
      minWidth: 640,
      minHeight: 640,
      quality: 70,
      format: CompressFormat.jpeg,
    );

    if (result == null) throw Exception('Thumbnail generation failed');
    return File(result.path);
  }

  /// Uploads an E2E-encrypted image + thumbnail. Returns the record ID.
  Future<String> uploadImage(
    File compressed,
    File thumbnail,
    String conversationId,
    String quality,
    String messageServerId,
    List<int> convKey, {
    UploadTicket? ticket,
    String? sentName,
    String? sentThumbName,
  }) async {
    final fileName = sentName ?? compressed.uri.pathSegments.last;
    final thumbName = sentThumbName ?? thumbnail.uri.pathSegments.last;
    final rawBytes = await compressed.readAsBytes();
    final thumbRaw = await thumbnail.readAsBytes();
    final expiresAt = retentionExpiry('image', quality);
    final mimeType = lookupMimeType(compressed.path) ?? 'image/jpeg';

    // Decode image dimensions so the bubble can render the correct aspect ratio
    int? imgWidth;
    int? imgHeight;
    try {
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      imgWidth = frame.image.width;
      imgHeight = frame.image.height;
      frame.image.dispose();
      codec.dispose();
    } catch (e) {
      debugPrint('[Media] Could not decode image dimensions: $e');
    }

    final (encBytes, fileIv) = await _encryptFileBytes(rawBytes, convKey);
    final (encThumb, thumbIv) = await _encryptFileBytes(thumbRaw, convKey);

    debugPrint(
      '[Media] Uploading encrypted image: $fileName (${encBytes.length} bytes)',
    );
    ticket?.total = encBytes.length + encThumb.length;

    final record = await _guarded(
      ticket,
      _pb
          .collection('message_media')
          .create(
            body: {
              'message_id': messageServerId,
              'conversation_id': conversationId,
              'media_type': 'image',
              'file_name': fileName,
              'file_size': rawBytes.length,
              'duration_seconds': 0,
              'expires_at': expiresAt.toUtc().toIso8601String(),
              'quality': quality,
              'mime_type': mimeType,
              'file_iv': fileIv,
              'thumb_iv': thumbIv,
              if (imgWidth != null) 'image_width': imgWidth,
              if (imgHeight != null) 'image_height': imgHeight,
            },
            files: [
              _part('file', encBytes, '$fileName.enc', ticket),
              _part('thumbnail', encThumb, '$thumbName.enc', ticket),
            ],
          ),
    );

    debugPrint('[Media] Image uploaded, mediaId: ${record.id}');
    return record.id;
  }

  // ── Video ──────────────────────────────────────────────────────

  /// Compresses a video to the specified quality preset.
  Future<File> compressVideo(
    File original,
    String quality, {
    int? startTime,
    int? endTime,
    int? sourceDuration,
  }) async {
    final videoQuality = quality == 'high'
        ? VideoQuality
              .Res1920x1080Quality // 1080p
        : VideoQuality.Res1280x720Quality; // 720p

    final info = await VideoCompress.compressVideo(
      original.absolute.path,
      quality: videoQuality,
      deleteOrigin: true,
      includeAudio: true,
      startTime: startTime,
      // Android Transcoder treats duration as time cut from the END.
      duration: startTime == null || endTime == null || sourceDuration == null
          ? null
          : sourceDuration - endTime,
    );

    if (info == null || info.file == null) {
      throw Exception('Video compression failed');
    }
    return info.file!;
  }

  /// Generates a thumbnail from a video file.
  Future<File> generateVideoThumbnail(
    File videoFile, {
    int position = -1,
  }) async {
    Uint8List? thumbBytes;
    try {
      thumbBytes = await VideoCompress.getByteThumbnail(
        videoFile.path,
        quality: 75,
        position: _thumbPosition(position),
      );
    } catch (e) {
      debugPrint('[Media] getByteThumbnail failed: $e');
    }

    if (thumbBytes != null && thumbBytes.isNotEmpty) {
      final tmpDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final outPath = '${tmpDir.path}/vthumb_$ts.jpg';
      final file = File(outPath);
      await file.writeAsBytes(thumbBytes);
      return file;
    }

    try {
      final thumbFile = await VideoCompress.getFileThumbnail(
        videoFile.path,
        quality: 75,
        position: _thumbPosition(position),
      );
      return thumbFile;
    } catch (e) {
      throw Exception('Could not generate video thumbnail: $e');
    }
  }

  /// Uploads an E2E-encrypted video + thumbnail. Returns the record ID.
  Future<String> uploadVideo(
    File compressed,
    File thumbnail,
    String conversationId,
    String quality,
    int durationSeconds,
    String messageServerId,
    List<int> convKey, {
    int? videoWidth,
    int? videoHeight,
    UploadTicket? ticket,
    String? sentName,
    String? sentThumbName,
  }) async {
    final fileName = sentName ?? compressed.uri.pathSegments.last;
    final thumbName = sentThumbName ?? thumbnail.uri.pathSegments.last;
    final rawBytes = await compressed.readAsBytes();
    final thumbRaw = await thumbnail.readAsBytes();
    final expiresAt = retentionExpiry('video', quality);
    final mimeType = lookupMimeType(compressed.path) ?? 'video/mp4';

    final (encBytes, fileIv) = await _encryptFileBytes(rawBytes, convKey);
    final (encThumb, thumbIv) = await _encryptFileBytes(thumbRaw, convKey);

    debugPrint(
      '[Media] Uploading encrypted video: $fileName (${encBytes.length} bytes)',
    );
    ticket?.total = encBytes.length + encThumb.length;

    final record = await _guarded(
      ticket,
      _pb
          .collection('message_media')
          .create(
            body: {
              'message_id': messageServerId,
              'conversation_id': conversationId,
              'media_type': 'video',
              'file_name': fileName,
              'file_size': rawBytes.length,
              'duration_seconds': durationSeconds,
              'expires_at': expiresAt.toUtc().toIso8601String(),
              'quality': quality,
              'mime_type': mimeType,
              'file_iv': fileIv,
              'thumb_iv': thumbIv,
              if (videoWidth != null) 'video_width': videoWidth,
              if (videoHeight != null) 'video_height': videoHeight,
            },
            files: [
              _part('file', encBytes, '$fileName.enc', ticket),
              _part('thumbnail', encThumb, '$thumbName.enc', ticket),
            ],
          ),
    );

    debugPrint('[Media] Video uploaded, mediaId: ${record.id}');
    return record.id;
  }

  // ── Document ────────────────────────────────────────────────────────────

  /// Uploads an E2E-encrypted document. Returns the record ID.
  Future<String> uploadDocument(
    File docFile,
    String conversationId,
    String messageServerId,
    List<int> convKey, {
    UploadTicket? ticket,
    String? sentName,
  }) async {
    final fileName = sentName ?? docFile.uri.pathSegments.last;
    final rawBytes = await docFile.readAsBytes();
    final mimeType = lookupMimeType(docFile.path) ?? 'application/octet-stream';
    final expiresAt = retentionExpiry('document', 'normal');

    final (encBytes, fileIv) = await _encryptFileBytes(rawBytes, convKey);

    debugPrint(
      '[Media] Uploading encrypted document: $fileName (${encBytes.length} bytes)',
    );
    ticket?.total = encBytes.length;

    final record = await _guarded(
      ticket,
      _pb
          .collection('message_media')
          .create(
            body: {
              'message_id': messageServerId,
              'conversation_id': conversationId,
              'media_type': 'document',
              'file_name': fileName,
              'file_size': rawBytes.length,
              'expires_at': expiresAt.toUtc().toIso8601String(),
              'quality': 'normal',
              'mime_type': mimeType,
              'file_iv': fileIv,
            },
            files: [_part('file', encBytes, '$fileName.enc', ticket)],
          ),
    );

    debugPrint('[Media] Document uploaded, mediaId: ${record.id}');
    return record.id;
  }

  // ── Download + decrypt (viewer path) ──────────────────────────────────
  // MOVED (Task 5): getDecryptedMedia's download+verify+decrypt body now
  // lives in `infrastructure/media/media_blob_store.dart` — MediaBlobStore
  // is the SOLE writer of blob files (spec §4). Callers re-pointed:
  // MessageRepositoryImpl.getDecryptedMedia + mediaFileProvider →
  // MediaBlobStore.requestBlob.

  /// Returns the expires_at DateTime for a media record, or null.
  Future<DateTime?> getMediaExpiry(String messageServerId) async {
    try {
      final record = await _pb
          .collection('message_media')
          .getFirstListItem('message_id="$messageServerId"');
      final raw = record.data['expires_at']?.toString() ?? '';
      return raw.isNotEmpty ? DateTime.tryParse(raw)?.toLocal() : null;
    } catch (_) {
      return null;
    }
  }

  /// Legacy alias used by voice bubbles.
  Future<DateTime?> getVoiceExpiry(String messageServerId) =>
      getMediaExpiry(messageServerId);
}

final mediaUploadServiceProvider = Provider<MediaUploadService>((ref) {
  return MediaUploadService(
    ref.watch(pocketbaseClientProvider),
    ref.watch(encryptionServiceProvider),
  );
});
