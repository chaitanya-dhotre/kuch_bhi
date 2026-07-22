import 'dart:convert';
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

import '../core/constants/app_constants.dart';
import '../core/network/pocketbase_client.dart';
import 'encryption_service.dart';

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
  });
  final File file;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final DateTime? expiresAt;
  final String? mimeType;
  final String? fileName;
}

class MediaUploadService {
  MediaUploadService(this._pbClient, this._encryption);

  final PocketBaseClient _pbClient;
  final EncryptionService _encryption;
  PocketBase get _pb => _pbClient.pb;

  /// Retention per bible §11: expires_at is set at upload time by type+quality.
  static DateTime retentionExpiry(String mediaType, String quality) {
    final days = switch (mediaType) {
      'voice'    => AppConstants.retentionVoiceDays,
      'image'    => quality == 'high'
          ? AppConstants.retentionPhotoHighDays
          : AppConstants.retentionPhotoNormalDays,
      'video'    => quality == 'high'
          ? AppConstants.retentionVideoHighDays
          : AppConstants.retentionVideoNormalDays,
      'document' => AppConstants.retentionVoiceDays, // docs: 60 days
      _          => AppConstants.retentionVideoNormalDays,
    };
    return DateTime.now().add(Duration(days: days));
  }

  // ── E2E media encryption helpers ──────────────────────────────────────

  /// Encrypts [bytes] with [convKey]; returns (encryptedBytes, ivBase64).
  Future<(Uint8List, String)> _encryptFileBytes(
      List<int> bytes, List<int> convKey) async {
    final res = await _encryption.encryptBytes(bytes, convKey);
    // encryptBytes returns base64 ciphertext; we upload the RAW encrypted
    // bytes (decoded) to avoid a 33% base64 size penalty on the server.
    return (Uint8List.fromList(base64Decode(res.ciphertext)), res.iv);
  }

  static Uint8List base64Decode(String s) =>
      Uint8List.fromList(const Base64Decoder().convert(s));

  // ── Voice ─────────────────────────────────────────────────────────────

  /// Uploads an E2E-encrypted voice recording. Returns the record ID.
  Future<String> uploadVoice(
    File audioFile,
    String conversationId,
    int durationSeconds,
    String messageServerId,
    List<int> convKey,
  ) async {
    final fileName  = audioFile.uri.pathSegments.last;
    final rawBytes  = await audioFile.readAsBytes();
    final (encBytes, iv) = await _encryptFileBytes(rawBytes, convKey);
    final expiresAt = retentionExpiry('voice', 'normal');

    debugPrint('[Media] Uploading encrypted voice: $fileName, size: ${encBytes.length}');

    final record = await _pb.collection('message_media').create(
      body: {
        'message_id':       messageServerId,
        'conversation_id':  conversationId,
        'media_type':       'voice',
        'file_name':        fileName,
        'file_size':        rawBytes.length,
        'duration_seconds': durationSeconds,
        'expires_at':       expiresAt.toUtc().toIso8601String(),
        'quality':          'normal',
        'file_iv':          iv,
      },
      files: [
        http.MultipartFile.fromBytes('file', encBytes, filename: '$fileName.enc'),
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

    final result = await FlutterImageCompress.compressAndGetFile(
      original.absolute.path,
      outPath,
      minWidth:    minSide,
      minHeight:   minSide,
      quality:     compQuality,
      format:      CompressFormat.jpeg,
    );

    if (result == null) throw Exception('Image compression failed');
    return File(result.path);
  }

  /// Generates a 200px thumbnail at 60% quality.
  Future<File> generateImageThumbnail(File image) async {
    final tmpDir  = await getTemporaryDirectory();
    final ts      = DateTime.now().millisecondsSinceEpoch;
    final outPath = '${tmpDir.path}/thumb_$ts.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      image.absolute.path,
      outPath,
      minWidth:    200,
      minHeight:   200,
      quality:     60,
      format:      CompressFormat.jpeg,
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
    List<int> convKey,
  ) async {
    final fileName  = compressed.uri.pathSegments.last;
    final thumbName = thumbnail.uri.pathSegments.last;
    final rawBytes  = await compressed.readAsBytes();
    final thumbRaw  = await thumbnail.readAsBytes();
    final expiresAt = retentionExpiry('image', quality);
    final mimeType  = lookupMimeType(compressed.path) ?? 'image/jpeg';

    // Decode image dimensions so the bubble can render the correct aspect ratio
    int? imgWidth;
    int? imgHeight;
    try {
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      imgWidth  = frame.image.width;
      imgHeight = frame.image.height;
      frame.image.dispose();
      codec.dispose();
    } catch (e) {
      debugPrint('[Media] Could not decode image dimensions: $e');
    }

    final (encBytes, fileIv)   = await _encryptFileBytes(rawBytes, convKey);
    final (encThumb, thumbIv)  = await _encryptFileBytes(thumbRaw, convKey);

    debugPrint('[Media] Uploading encrypted image: $fileName (${encBytes.length} bytes)');

    final record = await _pb.collection('message_media').create(
      body: {
        'message_id':       messageServerId,
        'conversation_id':  conversationId,
        'media_type':       'image',
        'file_name':        fileName,
        'file_size':        rawBytes.length,
        'duration_seconds': 0,
        'expires_at':       expiresAt.toUtc().toIso8601String(),
        'quality':          quality,
        'mime_type':        mimeType,
        'file_iv':          fileIv,
        'thumb_iv':         thumbIv,
        if (imgWidth  != null) 'image_width':  imgWidth,
        if (imgHeight != null) 'image_height': imgHeight,
      },
      files: [
        http.MultipartFile.fromBytes('file', encBytes, filename: '$fileName.enc'),
        http.MultipartFile.fromBytes('thumbnail', encThumb, filename: '$thumbName.enc'),
      ],
    );

    debugPrint('[Media] Image uploaded, mediaId: ${record.id}');
    return record.id;
  }

  // ── Video ──────────────────────────────────────────────────────

  /// Compresses a video to the specified quality preset.
  Future<File> compressVideo(File original, String quality) async {
    final videoQuality = quality == 'high'
        ? VideoQuality.Res1920x1080Quality // 1080p
        : VideoQuality.Res1280x720Quality;   // 720p

    final info = await VideoCompress.compressVideo(
      original.absolute.path,
      quality: videoQuality,
      deleteOrigin: true,
      includeAudio: true,
    );

    if (info == null || info.file == null) {
      throw Exception('Video compression failed');
    }
    return info.file!;
  }

  /// Generates a thumbnail from a video file.
  Future<File> generateVideoThumbnail(File videoFile) async {
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
      return file;
    }

    try {
      final thumbFile = await VideoCompress.getFileThumbnail(
        videoFile.path,
        quality: 75,
        position: -1,
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
  }) async {
    final fileName  = compressed.uri.pathSegments.last;
    final thumbName = thumbnail.uri.pathSegments.last;
    final rawBytes  = await compressed.readAsBytes();
    final thumbRaw  = await thumbnail.readAsBytes();
    final expiresAt = retentionExpiry('video', quality);
    final mimeType  = lookupMimeType(compressed.path) ?? 'video/mp4';

    final (encBytes, fileIv)  = await _encryptFileBytes(rawBytes, convKey);
    final (encThumb, thumbIv) = await _encryptFileBytes(thumbRaw, convKey);

    debugPrint('[Media] Uploading encrypted video: $fileName (${encBytes.length} bytes)');

    final record = await _pb.collection('message_media').create(
      body: {
        'message_id':       messageServerId,
        'conversation_id':  conversationId,
        'media_type':       'video',
        'file_name':        fileName,
        'file_size':        rawBytes.length,
        'duration_seconds': durationSeconds,
        'expires_at':       expiresAt.toUtc().toIso8601String(),
        'quality':          quality,
        'mime_type':        mimeType,
        'file_iv':          fileIv,
        'thumb_iv':         thumbIv,
        if (videoWidth  != null) 'video_width':  videoWidth,
        if (videoHeight != null) 'video_height': videoHeight,
      },
      files: [
        http.MultipartFile.fromBytes('file', encBytes, filename: '$fileName.enc'),
        http.MultipartFile.fromBytes('thumbnail', encThumb, filename: '$thumbName.enc'),
      ],
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
    List<int> convKey,
  ) async {
    final fileName = docFile.uri.pathSegments.last;
    final rawBytes = await docFile.readAsBytes();
    final mimeType = lookupMimeType(docFile.path) ?? 'application/octet-stream';
    final expiresAt = retentionExpiry('document', 'normal');

    final (encBytes, fileIv) = await _encryptFileBytes(rawBytes, convKey);

    debugPrint('[Media] Uploading encrypted document: $fileName (${encBytes.length} bytes)');

    final record = await _pb.collection('message_media').create(
      body: {
        'message_id':      messageServerId,
        'conversation_id': conversationId,
        'media_type':      'document',
        'file_name':       fileName,
        'file_size':       rawBytes.length,
        'expires_at':      expiresAt.toUtc().toIso8601String(),
        'quality':         'normal',
        'mime_type':       mimeType,
        'file_iv':         fileIv,
      },
      files: [
        http.MultipartFile.fromBytes('file', encBytes, filename: '$fileName.enc'),
      ],
    );

    debugPrint('[Media] Document uploaded, mediaId: ${record.id}');
    return record.id;
  }

  // ── Download + decrypt (viewer path) ──────────────────────────────────

  /// Fetches the media record for [messageServerId], downloads the encrypted
  /// file (or thumbnail), decrypts it off the UI isolate, caches the clear
  /// bytes on disk, and returns the local file + metadata.
  ///
  /// Legacy plaintext media (empty IV) is downloaded and cached as-is, so
  /// existing chats keep working.
  Future<LocalMediaFile?> getDecryptedMedia(
    String messageServerId,
    List<int> convKey, {
    bool thumb = false,
  }) async {
    try {
      final record = await _pb.collection('message_media').getFirstListItem(
        'message_id="$messageServerId"',
      );

      String? readFile(dynamic data) {
        if (data is String) return data;
        if (data is List && data.isNotEmpty) return data.first.toString();
        return null;
      }

      final storedName =
          readFile(record.data[thumb ? 'thumbnail' : 'file']);
      if (storedName == null || storedName.isEmpty) return null;

      final iv = record
          .getStringValue(thumb ? 'thumb_iv' : 'file_iv');

      // Cache key: record id + variant. Cleartext cache lives in app cache dir.
      final cacheDir = await getTemporaryDirectory();
      final mediaCache = Directory('${cacheDir.path}/media_clear');
      if (!await mediaCache.exists()) await mediaCache.create(recursive: true);
      // Strip the .enc suffix for the local file so viewers/open-external
      // get a sensible extension.
      final localName = storedName.endsWith('.enc')
          ? storedName.substring(0, storedName.length - 4)
          : storedName;
      final localFile =
          File('${mediaCache.path}/${record.id}_${thumb ? 't_' : ''}$localName');

      if (!await localFile.exists()) {
        final url =
            '${_pb.baseUrl}/api/files/message_media/${record.id}/$storedName';
        final resp = await http.get(
          Uri.parse(url),
          headers: {'Authorization': _pb.authStore.token},
        );
        if (resp.statusCode != 200) {
          debugPrint('[Media] download failed ${resp.statusCode} for $url');
          return null;
        }
        List<int> clear;
        if (iv.isEmpty) {
          // Legacy plaintext upload.
          clear = resp.bodyBytes;
        } else {
          final dec = await _encryption.decryptBytes(
            resp.bodyBytes, iv, convKey);
          if (dec == null) {
            debugPrint('[Media] decrypt failed for ${record.id} (thumb=$thumb)');
            return null;
          }
          clear = dec;
        }
        await localFile.writeAsBytes(clear, flush: true);
      }

      final expiresRaw = record.data['expires_at']?.toString() ?? '';
      int? asInt(dynamic v) =>
          v == null ? null : int.tryParse(v.toString());
      return LocalMediaFile(
        file:            localFile,
        width:           asInt(record.data['image_width']) ??
                         asInt(record.data['video_width']),
        height:          asInt(record.data['image_height']) ??
                         asInt(record.data['video_height']),
        durationSeconds: asInt(record.data['duration_seconds']),
        expiresAt:       expiresRaw.isEmpty
            ? null
            : DateTime.tryParse(expiresRaw)?.toLocal(),
        mimeType:        record.data['mime_type']?.toString(),
        fileName:        record.getStringValue('file_name'),
      );
    } catch (e) {
      debugPrint('[Media] getDecryptedMedia error: $e');
      return null;
    }
  }

  /// Returns the expires_at DateTime for a media record, or null.
  Future<DateTime?> getMediaExpiry(String messageServerId) async {
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
