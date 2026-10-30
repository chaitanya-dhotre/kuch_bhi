import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/app_sheet.dart';

/// Attach source: `'camera'`, `'gallery'`, `'video_camera'`,
/// `'video_gallery'`, `'document'`, or `null` when dismissed.
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
          row(Icons.photo_library_outlined, 'Photo library', 'gallery'),
          row(Icons.videocam_outlined, 'Record a video', 'video_camera'),
          row(Icons.video_library_outlined, 'Video library', 'video_gallery'),
          row(Icons.attach_file_outlined, 'Document', 'document'),
        ],
      );
    },
  );
}

/// Quality: `'normal'`, `'high'`, or `null`. Decision 2: each subtitle says
/// how long the server keeps it (High is kept half as long).
Future<String?> showMediaQualitySheet(
  BuildContext context, {
  required bool isVideo,
}) {
  final normal = isVideo
      ? '720p · kept ${AppConstants.retentionVideoNormalDays} days'
      : '60% quality, up to 1280px · kept '
          '${AppConstants.retentionPhotoNormalDays} days';
  final high = isVideo
      ? '1080p · kept ${AppConstants.retentionVideoHighDays} days'
      : '90% quality, up to 2560px · kept '
          '${AppConstants.retentionPhotoHighDays} days';
  return showAppSheet<String>(
    context: context,
    builder: (sheetContext) => AppSheetChrome(
      title: isVideo ? 'Video quality' : 'Photo quality',
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
