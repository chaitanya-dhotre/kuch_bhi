import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:video_compress/video_compress.dart';

import '../core/network/pocketbase_client.dart';

class MediaUploadService {
  MediaUploadService(this._pbClient);

  final PocketBaseClient _pbClient;
  PocketBase get _pb => _pbClient.pb;

  /// Uploads a voice recording to the `message_media` PocketBase collection.
  /// Returns the newly created record's ID.
  /// The [messageServerId] must be the server ID of the already-created
  /// message record, since `message_id` is a required field.
  Future<String> uploadVoice(
    File audioFile,
    String conversationId,
    int durationSeconds,
    String messageServerId,
  ) async {
    final fileName  = audioFile.uri.pathSegments.last;
    final fileSize  = await audioFile.length();
    final expiresAt = DateTime.now().add(const Duration(days: 365));

    debugPrint('[Media] Uploading voice: $fileName, size: $fileSize');

    final record = await _pb.collection('message_media').create(
      body: {
        'message_id':       messageServerId,
        'conversation_id':  conversationId,
        'media_type':       'voice',
        'file_name':        fileName,
        'file_size':        fileSize,
        'duration_seconds': durationSeconds,
        'expires_at':       expiresAt.toUtc().toIso8601String(),
        'quality':          'normal',
      },
      files: [
        http.MultipartFile.fromBytes(
          'file',
          await audioFile.readAsBytes(),
          filename: fileName,
        ),
      ],
    );

    debugPrint('[Media] Voice uploaded, mediaId: ${record.id}');
    return record.id;
  }


  // ── Image ────────────────────────────────────────────────────

  /// Compresses an image to the specified quality preset.
  /// Returns a new File in the cache directory.
  Future<File> compressImage(File original, String quality) async {
    final tmpDir   = await getTemporaryDirectory();
    final ts       = DateTime.now().millisecondsSinceEpoch;
    final outPath  = '${tmpDir.path}/img_${quality}_$ts.jpg';

    final minSide  = quality == 'high' ? 2560 : 1280;
    final compQuality = quality == 'high' ? 90 : 60;

    debugPrint('[Media] Compressing image to $quality: ${original.path}');

    final result = await FlutterImageCompress.compressAndGetFile(
      original.absolute.path,
      outPath,
      minWidth:    minSide,
      minHeight:   minSide,
      quality:     compQuality,
      format:      CompressFormat.jpeg,
    );

    if (result == null) throw Exception('Image compression failed');
    debugPrint('[Media] Compressed: ${result.path}');
    return File(result.path);
  }

  /// Generates a 200px thumbnail at 60% quality.
  Future<File> generateImageThumbnail(File image) async {
    final tmpDir  = await getTemporaryDirectory();
    final ts      = DateTime.now().millisecondsSinceEpoch;
    final outPath = '${tmpDir.path}/thumb_$ts.jpg';

    debugPrint('[Media] Generating thumbnail: ${image.path}');

    final result = await FlutterImageCompress.compressAndGetFile(
      image.absolute.path,
      outPath,
      minWidth:    200,
      minHeight:   200,
      quality:     60,
      format:      CompressFormat.jpeg,
    );

    if (result == null) throw Exception('Thumbnail generation failed');
    debugPrint('[Media] Thumbnail: ${result.path}');
    return File(result.path);
  }

  /// Uploads a compressed image + thumbnail to `message_media`.
  /// Returns the created record's ID.
  Future<String> uploadImage(
    File compressed,
    File thumbnail,
    String conversationId,
    String quality,
    String messageServerId,
  ) async {
    final fileName      = compressed.uri.pathSegments.last;
    final thumbName     = thumbnail.uri.pathSegments.last;
    final fileSize      = await compressed.length();
    final thumbSize     = await thumbnail.length();
    final expiresAt     = DateTime.now().add(const Duration(days: 365));
    final mimeType      = lookupMimeType(compressed.path) ?? 'image/jpeg';

    // Decode image dimensions so the bubble can render the correct aspect ratio
    int? imgWidth;
    int? imgHeight;
    try {
      final codec = await ui.instantiateImageCodec(
        await compressed.readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      imgWidth  = frame.image.width;
      imgHeight = frame.image.height;
      frame.image.dispose();
      codec.dispose();
    } catch (e) {
      debugPrint('[Media] Could not decode image dimensions: $e');
    }

    debugPrint('[Media] Uploading image: $fileName ($fileSize bytes) + thumb: $thumbName ($thumbSize bytes)');

    final record = await _pb.collection('message_media').create(
      body: {
        'message_id':       messageServerId,
        'conversation_id':  conversationId,
        'media_type':       'image',
        'file_name':        fileName,
        'file_size':        fileSize,
        'duration_seconds': 0,
        'expires_at':       expiresAt.toUtc().toIso8601String(),
        'quality':          quality,
        'mime_type':        mimeType,
        if (imgWidth  != null) 'image_width':  imgWidth,
        if (imgHeight != null) 'image_height': imgHeight,
      },
      files: [
        http.MultipartFile.fromBytes(
          'file',
          await compressed.readAsBytes(),
          filename: fileName,
        ),
        http.MultipartFile.fromBytes(
          'thumbnail',
          await thumbnail.readAsBytes(),
          filename: thumbName,
        ),
      ],
    );

    debugPrint('[Media] Image uploaded, mediaId: ${record.id}');
    return record.id;
  }

  /// Returns thumbnail and full image URLs for a message server ID.
  /// thumb: /api/files/message_media/{id}/{thumbName}?thumb=200x200
  Future<Map<String, String>?> getImageUrls(String messageServerId) async {
    try {
      final record = await _pb.collection('message_media').getFirstListItem(
        'message_id="$messageServerId"',
      );

      String? readFile(dynamic data) {
        if (data is String) return data;
        if (data is List && data.isNotEmpty) return data.first.toString();
        return null;
      }

      final fileName  = readFile(record.data['file']);
      final thumbName = readFile(record.data['thumbnail']);

      if (fileName == null || fileName.isEmpty) return null;

      final base = '${_pb.baseUrl}/api/files/message_media/${record.id}';
      final w = record.data['image_width'];
      final h = record.data['image_height'];
      final expiresRaw = record.data['expires_at']?.toString() ?? '';
      return {
        'full':       '$base/$fileName',
        if (thumbName != null) 'thumb': '$base/$thumbName?thumb=200x200',
        'width':      w?.toString() ?? '0',
        'height':     h?.toString() ?? '0',
        'expires_at': expiresRaw,
      };
    } catch (e) {
      debugPrint('[Media] getImageUrls error: $e');
      return null;
    }
  }

  // ── Video ──────────────────────────────────────────────────────

  /// Compresses a video to the specified quality preset.
  /// Returns a new File. Deletes the original temp file after compression.
  Future<File> compressVideo(File original, String quality) async {
    final videoQuality = quality == 'high'
        ? VideoQuality.Res1920x1080Quality // 1080p
        : VideoQuality.Res1280x720Quality;   // 720p

    debugPrint('[Media] Compressing video to $quality: ${original.path}');

    final info = await VideoCompress.compressVideo(
      original.absolute.path,
      quality: videoQuality,
      deleteOrigin: true,
      includeAudio: true,
    );

    if (info == null || info.file == null) {
      throw Exception('Video compression failed');
    }
    debugPrint('[Media] Compressed: ${info.file!.path}');
    return info.file!;
  }

  /// Generates a thumbnail from a video file at the 1-second mark.
  /// Returns a JPEG File in the cache directory, 200px wide.
  Future<File> generateVideoThumbnail(File videoFile) async {
    // position: -1 means the plugin picks a frame from the middle of the video,
    // which is more reliable than a fixed ms offset that may exceed the duration.
    Uint8List? thumbBytes;
    try {
      thumbBytes = await VideoCompress.getByteThumbnail(
        videoFile.path,
        quality: 75,
        position: -1,
      );
    } catch (e) {
      debugPrint('[Media] getByteThumbnail failed: $e');
    }

    if (thumbBytes != null && thumbBytes.isNotEmpty) {
      final tmpDir  = await getTemporaryDirectory();
      final ts      = DateTime.now().millisecondsSinceEpoch;
      final outPath = '${tmpDir.path}/vthumb_$ts.jpg';
      final file = File(outPath);
      await file.writeAsBytes(thumbBytes);
      debugPrint('[Media] Video thumbnail (bytes): $outPath');
      return file;
    }

    // Fallback: native plugin writes the file for us
    try {
      debugPrint('[Media] Falling back to getFileThumbnail');
      final thumbFile = await VideoCompress.getFileThumbnail(
        videoFile.path,
        quality: 75,
        position: -1,
      );
      debugPrint('[Media] Video thumbnail (file): ${thumbFile.path}');
      return thumbFile;
    } catch (e) {
      debugPrint('[Media] getFileThumbnail also failed: $e');
      throw Exception('Could not generate video thumbnail: $e');
    }
  }

  /// Uploads a compressed video + thumbnail to `message_media`.
  /// Returns the created record's ID.
  Future<String> uploadVideo(
    File compressed,
    File thumbnail,
    String conversationId,
    String quality,
    int durationSeconds,
    String messageServerId, {
    int? videoWidth,
    int? videoHeight,
  }) async {
    final fileName  = compressed.uri.pathSegments.last;
    final thumbName = thumbnail.uri.pathSegments.last;
    final fileSize  = await compressed.length();
    final thumbSize = await thumbnail.length();
    final expiresAt = DateTime.now().add(const Duration(days: 365));
    final mimeType  = lookupMimeType(compressed.path) ?? 'video/mp4';

    debugPrint('[Media] Uploading video: $fileName ($fileSize bytes) + thumb: $thumbName ($thumbSize bytes)');

    final record = await _pb.collection('message_media').create(
      body: {
        'message_id':       messageServerId,
        'conversation_id':  conversationId,
        'media_type':       'video',
        'file_name':        fileName,
        'file_size':        fileSize,
        'duration_seconds': durationSeconds,
        'expires_at':       expiresAt.toUtc().toIso8601String(),
        'quality':          quality,
        'mime_type':        mimeType,
        if (videoWidth  != null) 'video_width':  videoWidth,
        if (videoHeight != null) 'video_height': videoHeight,
      },
      files: [
        http.MultipartFile.fromBytes(
          'file',
          await compressed.readAsBytes(),
          filename: fileName,
        ),
        http.MultipartFile.fromBytes(
          'thumbnail',
          await thumbnail.readAsBytes(),
          filename: thumbName,
        ),
      ],
    );

    debugPrint('[Media] Video uploaded, mediaId: ${record.id}');
    return record.id;
  }

  /// Returns thumbnail and full video URLs for a message server ID.
  Future<Map<String, String>?> getVideoUrls(String messageServerId) async {
    try {
      final record = await _pb.collection('message_media').getFirstListItem(
        'message_id="$messageServerId"',
      );

      String? readFile(dynamic data) {
        if (data is String) return data;
        if (data is List && data.isNotEmpty) return data.first.toString();
        return null;
      }

      final fileName  = readFile(record.data['file']);
      final thumbName = readFile(record.data['thumbnail']);

      if (fileName == null || fileName.isEmpty) return null;

      final base = '${_pb.baseUrl}/api/files/message_media/${record.id}';
      final dur = record.data['duration_seconds'];
      final w   = record.data['video_width'];
      final h   = record.data['video_height'];
      final expiresRaw = record.data['expires_at']?.toString() ?? '';
      return {
        'full':       '$base/$fileName',
        if (thumbName != null) 'thumb': '$base/$thumbName',
        'duration':   dur?.toString() ?? '0',
        'width':      w?.toString() ?? '0',
        'height':     h?.toString() ?? '0',
        'expires_at': expiresRaw,
      };
    } catch (e) {
      debugPrint('[Media] getVideoUrls error: $e');
      return null;
    }
  }

  // ── Voice URL ──────────────────────────────────────────────────

  /// Fetches a `message_media` record for the given message server ID and
  /// returns the public file URL.
  Future<String?> getVoiceUrl(String messageServerId) async {
    try {
      final record = await _pb.collection('message_media').getFirstListItem(
        'message_id="$messageServerId"',
      );

      debugPrint('[Media] getVoiceUrl record data: ${record.data}');
      debugPrint('[Media] getVoiceUrl record id: ${record.id}');

      // PocketBase stores the actual filename in the 'file' field data.
      // The URL format for PocketBase 0.21+ is:
      // /api/files/{collection}/{recordId}/{filename}
      final fileData = record.data['file'];
      String? storedFileName;
      if (fileData is String) {
        storedFileName = fileData;
      } else if (fileData is List && fileData.isNotEmpty) {
        storedFileName = fileData.first.toString();
      }

      debugPrint('[Media] getVoiceUrl storedFileName: $storedFileName');

      if (storedFileName == null || storedFileName.isEmpty) return null;

      final url = '${_pb.baseUrl}/api/files/message_media/${record.id}/$storedFileName';
      debugPrint('[Media] getVoiceUrl constructed URL: $url');
      return url;
    } catch (e) {
      debugPrint('[Media] getVoiceUrl error: $e');
      return null;
    }
  }

  /// Returns the expires_at DateTime for a voice message_media record, or null.
  Future<DateTime?> getVoiceExpiry(String messageServerId) async {
    try {
      final record = await _pb.collection('message_media').getFirstListItem(
        'message_id="$messageServerId"',
      );
      final raw = record.data['expires_at']?.toString() ?? '';
      return raw.isNotEmpty ? DateTime.tryParse(raw)?.toLocal() : null;
    } catch (_) {
      return null;
    }
  }

  // ── Document ────────────────────────────────────────────────────────────

  /// Uploads a document file (any type, no compression) to `message_media`.
  /// Returns the created record's ID.
  Future<String> uploadDocument(
    File docFile,
    String conversationId,
    String messageServerId,
  ) async {
    final fileName = docFile.uri.pathSegments.last;
    final fileSize = await docFile.length();
    final mimeType = lookupMimeType(docFile.path) ?? 'application/octet-stream';
    final expiresAt = DateTime.now().add(const Duration(days: 365));

    debugPrint('[Media] Uploading document: $fileName ($fileSize bytes)');

    final record = await _pb.collection('message_media').create(
      body: {
        'message_id':      messageServerId,
        'conversation_id': conversationId,
        'media_type':      'document',
        'file_name':       fileName,
        'file_size':       fileSize,
        'expires_at':      expiresAt.toUtc().toIso8601String(),
        'quality':         'normal',
        'mime_type':       mimeType,
      },
      files: [
        http.MultipartFile.fromBytes(
          'file',
          await docFile.readAsBytes(),
          filename: fileName,
        ),
      ],
    );

    debugPrint('[Media] Document uploaded, mediaId: ${record.id}');
    return record.id;
  }
}

final mediaUploadServiceProvider = Provider<MediaUploadService>((ref) {
  return MediaUploadService(ref.watch(pocketbaseClientProvider));
});
