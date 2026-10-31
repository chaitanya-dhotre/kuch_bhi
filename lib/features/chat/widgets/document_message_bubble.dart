import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/utils/media_utils.dart';
import '../providers/chat_provider.dart';
import 'expiry_badge.dart';
import 'media_retry.dart';

String _formatType(String fileName, String? mimeType) {
  final mime = mimeType?.trim();
  if (mime != null && mime.isNotEmpty) return mime;
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return 'File';
  return '${fileName.substring(dot + 1).toUpperCase()} file';
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
    this.runEnd = true,
    this.status,
    this.createdAt,
  });

  final String conversationId;
  final String serverId;
  final bool isMine;
  final bool isDark;
  final bool runEnd;
  final String? status;
  final DateTime? createdAt;

  @override
  ConsumerState<DocumentMessageBubble> createState() =>
      _DocumentMessageBubbleState();
}

class _DocumentMessageBubbleState extends ConsumerState<DocumentMessageBubble> {
  bool _isDownloading = false;

  Future<void> _open() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      // Media is E2E-encrypted: fetch + decrypt to a local file, then open it.
      final media = await ref.read(
        mediaFileProvider(
          MediaRef(widget.conversationId, widget.serverId),
        ).future,
      );
      if (media == null) throw Exception('File unavailable');
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
    return ChatBubbleFrame(
      isMine: widget.isMine,
      runEnd: widget.runEnd,
      fillWidth: true,
      padding: const EdgeInsets.only(bottom: 8),
      showTimestamp: true,
      timestampOverlay: false,
      timestampPadding: const EdgeInsets.symmetric(horizontal: 12),
      createdAt: widget.createdAt,
      status: widget.status,
      child: mediaAsync.when(
        loading: () => _shimmer(),
        error: (_, __) => _retryTile(),
        data: (media) {
          if (gone) {
            return _expired();
          }
          if (media == null) return _retryTile();
          final fileName = media.fileName ?? 'file';
          final size = formatFileSize(
            media.file.existsSync() ? media.file.lengthSync() : 0,
            bytesUnitSpaced: true,
          );
          final type = _formatType(fileName, media.mimeType);
          final expiresAt = media.expiresAt;

          if (isExpired(expiresAt)) {
            return _expired();
          }

          final expiryLabel = compactExpiryLabel(expiresAt);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Semantics(
                button: true,
                label: 'Open document $fileName',
                child: InkWell(
                  borderRadius: ChatBubbleGeometry.radius(
                    isMine: widget.isMine,
                    runEnd: widget.runEnd,
                  ),
                  onTap: _open,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── File info row ─────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: widget.isMine
                                    ? context.t.onAccent.withValues(alpha: 0.16)
                                    : context.t.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _docIcon(fileName),
                                color: widget.isMine
                                    ? context.t.onAccent
                                    : context.t.accent,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    fileName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: widget.isMine
                                          ? context.t.onAccent
                                          : Theme.of(
                                              context,
                                            ).colorScheme.onSurface,
                                    ),
                                  ),
                                  if (size.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                  ],
                                  Text(
                                    [
                                      if (size.isNotEmpty) size,
                                      type,
                                    ].join(' · '),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: widget.isMine
                                          ? context.t.onAccent.withValues(
                                              alpha: 0.70,
                                            )
                                          : Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.55),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _isDownloading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: context.t.accent,
                                    ),
                                  )
                                : Icon(
                                    Icons.download_outlined,
                                    size: 20,
                                    color: widget.isMine
                                        ? context.t.onAccent.withValues(
                                            alpha: 0.70,
                                          )
                                        : context.t.accent,
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

  Widget _shimmer() => Shimmer.fromColors(
    baseColor: context.t.line,
    highlightColor: context.t.surface2,
    child: const SizedBox(height: 68, width: double.infinity),
  );

  Widget _expired() => ExpiredPlaceholder(
    glyph: Icons.timer_off_outlined,
    decorate: false,
    inline: true,
    ink: widget.isMine ? context.t.onAccent.withValues(alpha: 0.70) : null,
  );

  Widget _retryTile() => MediaRetry(
    media: MediaRef(widget.conversationId, widget.serverId),
    what: kMediaRowDocumentLabel,
    icon: Icons.insert_drive_file_outlined,
    ink: widget.isMine
        ? context.t.onAccent.withValues(alpha: 0.70)
        : context.t.inkSoft,
  );
}
