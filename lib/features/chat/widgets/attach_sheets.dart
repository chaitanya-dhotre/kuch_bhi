import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/app_sheet.dart';

/// Attach source: `'camera'`, `'gallery'`, `'video_camera'`, `'document'`,
/// or `null` when dismissed.
///
/// 12.5 B1: Photo library and Video library are one **Photos and videos**
/// row (`gallery`), which picks up to 20 photos and videos together.
Future<String?> showAttachSourceSheet(BuildContext context) {
  return showAppSheet<String>(
    context: context,
    builder: (sheetContext) {
      Widget row(IconData icon, String label, String value) => SheetActionRow(
            icon: icon,
            label: label,
            onTap: () => Navigator.of(sheetContext).pop(value),
          );
      return AppSheetChrome(
        title: 'Attach',
        children: [
          row(Icons.camera_alt_outlined, 'Take a photo', 'camera'),
          row(Icons.photo_library_outlined, 'Photos and videos', 'gallery'),
          row(Icons.videocam_outlined, 'Record a video', 'video_camera'),
          row(Icons.attach_file_outlined, kMediaRowDocumentLabel, 'document'),
        ],
      );
    },
  );
}

/// Quality: `'normal'`, `'high'`, or `null`. Decision 2: each subtitle says
/// how long the server keeps it (High is kept half as long).
///
/// 12.5 B5: an album asks once. All photos use the photo sheet, all videos
/// the video sheet, and a mixed album uses [mixed] — title **Quality**, with
/// both caps and both retention windows in one subtitle.
Future<String?> showMediaQualitySheet(
  BuildContext context, {
  required bool isVideo,
  bool mixed = false,
}) {
  final String title;
  final String normal;
  final String high;
  if (mixed) {
    title = 'Quality';
    normal =
        'Photos up to ${AppConstants.photoNormalMaxPx}px, videos '
        '${AppConstants.videoNormalQuality} · kept '
        '${AppConstants.retentionPhotoNormalDays} and '
        '${AppConstants.retentionVideoNormalDays} days';
    high =
        'Photos up to ${AppConstants.photoHighMaxPx}px, videos '
        '${AppConstants.videoHighQuality} · kept '
        '${AppConstants.retentionPhotoHighDays} and '
        '${AppConstants.retentionVideoHighDays} days';
  } else if (isVideo) {
    title = 'Video quality';
    normal =
        '${AppConstants.videoNormalQuality} · kept '
        '${AppConstants.retentionVideoNormalDays} days';
    high =
        '${AppConstants.videoHighQuality} · kept '
        '${AppConstants.retentionVideoHighDays} days';
  } else {
    title = 'Photo quality';
    normal =
        '60% quality, up to ${AppConstants.photoNormalMaxPx}px · kept '
        '${AppConstants.retentionPhotoNormalDays} days';
    high =
        '90% quality, up to ${AppConstants.photoHighMaxPx}px · kept '
        '${AppConstants.retentionPhotoHighDays} days';
  }
  return showAppSheet<String>(
    context: context,
    builder: (sheetContext) => AppSheetChrome(
      title: title,
      children: [
        SheetActionRow(
          icon: Icons.compress,
          label: 'Normal',
          subtitle: normal,
          onTap: () => Navigator.of(sheetContext).pop('normal'),
        ),
        SheetActionRow(
          icon: Icons.hd,
          label: 'High',
          subtitle: high,
          onTap: () => Navigator.of(sheetContext).pop('high'),
        ),
      ],
    ),
  );
}
