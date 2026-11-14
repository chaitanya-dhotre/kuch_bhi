import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/utils/media_utils.dart';
import '../../../services/media_upload_service.dart';
import '../providers/chat_provider.dart';
import 'expiry_badge.dart';
import 'media_retry.dart';
import 'media_upload_disc.dart';

/// E4: "PDF · 2.4 MB": the extension, else the mime subtype, else "File".
String _formatType(String fileName, String? mimeType) {
  final dot = fileName.lastIndexOf('.');
  if (dot >= 0 && dot < fileName.length - 1) {
    return fileName.substring(dot + 1).toUpperCase();
  }
  final sub = mimeType?.split('/').last.trim();
  return sub == null || sub.isEmpty ? 'File' : sub.toUpperCase();
}

IconData _docIcon(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  return switch (ext) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'doc' || 'docx' => Icons.description_outlined,
    'xls' || 'xlsx' => Icons.table_chart_outlined,
    'ppt' || 'pptx' => Icons.slideshow_outlined,
    'zip' || 'rar' || '7z' || 'gz' => Icons.folder_zip_outlined,
    'txt' || 'md' => Icons.text_snippet_outlined,
    _ => Icons.insert_drive_file_outlined,
  };
}

// ── Widget ────────────────────────────────────────────────────────────────────

class DocumentMessageBubble extends ConsumerStatefulWidget {
  const DocumentMessageBubble({
    super.key,
    required this.conversationId,
    required this.serverId,
    required this.isMine,
    required this.isDark,
    this.runStart = true,
    this.status,
    this.createdAt,
    this.localId,
  });

  final String conversationId;
  final String serverId;
  final bool isMine;
  final bool isDark;
  final bool runStart;
  final String? status;
  final DateTime? createdAt;
  final String? localId;

  @override
  ConsumerState<DocumentMessageBubble> createState() =>
      _DocumentMessageBubbleState();
}

class _DocumentMessageBubbleState extends ConsumerState<DocumentMessageBubble> {
  bool _isDownloading = false;

  Future<void> _open(LocalMediaFile media) async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      await OpenFile.open(media.file.path);
    } catch (e) {
      debugPrint('[DocBubble] open error: $e');
      if (mounted) {
        showToast(context, "Couldn't open the file. Try again.", error: true);
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Purged on the server for sure: no download, no retry.
    final gone = isPastRetention('document', widget.createdAt);
    final mediaAsync = gone
        ? const AsyncData(null)
        : ref.watch(
            mediaFileProvider(MediaRef(widget.conversationId, widget.serverId)),
          );
    final t = context.t;
    return ChatBubbleFrame(
      isMine: widget.isMine,
      runStart: widget.runStart,
      width: ChatBubbleGeometry.attachmentWidthOf(context),
      padding: ChatBubbleGeometry.attachmentPadding,
      child: mediaAsync.when(
        loading: () => _loadingRow(),
        error: (_, __) => _retryTile(),
        data: (media) {
          if (gone) return _expired();
          if (media == null) return _retryTile();
          final fileName = media.fileName ?? 'file';
          final size = formatFileSize(
            media.file.existsSync() ? media.file.lengthSync() : 0,
            bytesUnitSpaced: true,
          );
          final type = _formatType(fileName, media.mimeType);
          final expiresAt = media.expiresAt;

          if (isExpired(expiresAt)) return _expired();

          final expiryLabel = compactExpiryLabel(expiresAt);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Semantics(
                button: true,
                label: 'Open document $fileName',
                child: InkWell(
                  borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
                  onTap: () => _open(media),
                  child: Row(
                    children: [
                      _DocTile(
                        child: widget.localId != null
                            ? MediaUploadControl(
                                localId: widget.localId!,
                                status: widget.status,
                                kind: 'Document',
                                size: ChatBubbleGeometry.leadingSize,
                              )
                            : _isDownloading
                            ? BusySpinner(
                                size: 20,
                                strokeWidth: 2,
                                color: t.ink,
                              )
                            : Icon(_docIcon(fileName), color: t.ink, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              middleEllipsis(fileName, 26),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                height: 22 / 15,
                                fontWeight: FontWeight.w600,
                                color: t.ink,
                              ),
                            ),
                            Text(
                              [type, if (size.isNotEmpty) size].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 18 / 13,
                                color: t.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (expiryLabel != null) ExpiryBadge(label: expiryLabel),
            ],
          );
        },
      ),
    );
  }

  Widget _loadingRow() => Row(
    children: [
      const _DocTile(child: SizedBox.shrink()),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Skeleton(height: 14, width: 140),
            SizedBox(height: 6),
            Skeleton(height: 12, width: 80),
          ],
        ),
      ),
    ],
  );

  Widget _expired() => ExpiredPlaceholder(
    glyph: Icons.timer_off_outlined,
    decorate: false,
    inline: true,
  );

  Widget _retryTile() => MediaRetry(
    media: MediaRef(widget.conversationId, widget.serverId),
    what: kMediaRowDocumentLabel,
    icon: Icons.insert_drive_file_outlined,
    ink: context.t.inkSoft,
  );
}

/// E4: the 40 dp icon tile, ink at 8 %, radius 10.
class _DocTile extends StatelessWidget {
  const _DocTile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: ChatBubbleGeometry.leadingSize,
    height: ChatBubbleGeometry.leadingSize,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.t.ink.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
    ),
    child: child,
  );
}

/// E4: "a_very_long_na…me.pdf" keeps the extension in view.
String middleEllipsis(String s, int max) {
  if (s.length <= max || max < 5) return s;
  final tail = (max - 1) ~/ 2;
  final head = max - 1 - tail;
  return '${s.substring(0, head)}…${s.substring(s.length - tail)}';
}
