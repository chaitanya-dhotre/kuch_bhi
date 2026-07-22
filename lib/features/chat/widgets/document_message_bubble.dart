import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/media_utils.dart';
import '../providers/chat_provider.dart';

String _formatSize(dynamic raw) {
  final bytes = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
  if (bytes <= 0)        return '';
  if (bytes < 1024)      return '${bytes} B';
  if (bytes < 1048576)   return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

IconData _docIcon(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  return switch (ext) {
    'pdf'                            => Icons.picture_as_pdf_outlined,
    'doc' || 'docx'                  => Icons.description_outlined,
    'xls' || 'xlsx'                  => Icons.table_chart_outlined,
    'ppt' || 'pptx'                  => Icons.slideshow_outlined,
    'zip' || 'rar' || '7z' || 'gz'   => Icons.folder_zip_outlined,
    'txt' || 'md'                    => Icons.text_snippet_outlined,
    _                                => Icons.insert_drive_file_outlined,
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
    this.status,
    this.createdAt,
  });

  final String    conversationId;
  final String    serverId;
  final bool      isMine;
  final bool      isDark;
  final String?   status;
  final DateTime? createdAt;

  @override
  ConsumerState<DocumentMessageBubble> createState() =>
      _DocumentMessageBubbleState();
}

class _DocumentMessageBubbleState
    extends ConsumerState<DocumentMessageBubble> {
  bool _isDownloading = false;

  Future<void> _open() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      // Media is E2E-encrypted: fetch + decrypt to a local file, then open it.
      final media = await ref.read(mediaFileProvider(
          MediaRef(widget.conversationId, widget.serverId)).future);
      if (media == null) throw Exception('File unavailable');
      await OpenFile.open(media.file.path);
    } catch (e) {
      debugPrint('[DocBubble] open error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaAsync = ref.watch(mediaFileProvider(
        MediaRef(widget.conversationId, widget.serverId)));
    final bg        = widget.isMine
        ? AppColors.sentBubble
        : widget.isDark
            ? AppColors.receivedBubbleDark
            : AppColors.receivedBubbleLight;

    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left:   widget.isMine ? 64 : 12,
          right:  widget.isMine ? 12 : 64,
          top:    2,
          bottom: 2,
        ),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color:        bg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset:     const Offset(0, 1),
            ),
          ],
        ),
        child: mediaAsync.when(
          loading: () => _shimmer(),
          error:   (_, __) => _errorTile(),
          data: (media) {
            if (media == null) return _errorTile();
            final fileName   = media.fileName ?? 'file';
            final size       = _formatSize(media.file.existsSync()
                ? media.file.lengthSync()
                : 0);
            final expiresAt  = media.expiresAt;

            if (isExpired(expiresAt)) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_off_outlined, color: Colors.grey, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Media expired',
                      style: TextStyle(
                        color: widget.isMine ? Colors.white54 : Colors.grey,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            }

            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _open,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── File info row ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color:        widget.isMine
                                ? Colors.white.withValues(alpha: 0.2)
                                : AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _docIcon(fileName),
                            color:  widget.isMine ? Colors.white : AppColors.primary,
                            size:   22,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize:       MainAxisSize.min,
                            children: [
                              Text(
                                fileName,
                                maxLines:  2,
                                overflow:  TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize:   13,
                                  fontWeight: FontWeight.w500,
                                  color:      widget.isMine
                                      ? Colors.white
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              if (size.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  size,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:    widget.isMine
                                        ? Colors.white70
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.55),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _isDownloading
                            ? const SizedBox(
                                width: 20, height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color:       AppColors.primary,
                                ),
                              )
                            : Icon(
                                Icons.download_outlined,
                                size:  20,
                                color: widget.isMine ? Colors.white70 : AppColors.primary,
                              ),
                      ],
                    ),
                  ),
                  // ── Timestamp + tick row ──────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (expiresAt != null && expiryBadgeText(expiresAt) != null) ...[
                          Text(
                            expiryBadgeText(expiresAt)!,
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (widget.createdAt != null)
                          Text(
                            DateFormat('HH:mm').format(widget.createdAt!.toLocal()),
                            style: TextStyle(
                              fontSize: 10,
                              color: widget.isMine
                                  ? Colors.white60
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.4),
                            ),
                          ),
                        if (widget.isMine && widget.status != null) ...[
                          const SizedBox(width: 4),
                          _DocTickIndicator(status: widget.status!),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _shimmer() => Shimmer.fromColors(
        baseColor:      Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Container(
          height:           68,
          decoration: BoxDecoration(
            color:        Colors.grey.shade300,
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      );

  Widget _errorTile() => Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined, color: Colors.grey, size: 24),
            const SizedBox(width: 8),
            Text(
              'File unavailable',
              style: TextStyle(
                color: widget.isMine ? Colors.white70 : Colors.grey,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
}

// ── Tick indicator ────────────────────────────────────────────────────────────

class _DocTickIndicator extends StatelessWidget {
  const _DocTickIndicator({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    const color = Colors.white60;
    if (status == 'pending') {
      return const SizedBox(
        width: 10, height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
      );
    }
    if (status == 'read')      return const Icon(Icons.done_all, size: 12, color: Colors.white);
    if (status == 'delivered') return const Icon(Icons.done_all, size: 12, color: color);
    if (status == 'sent')      return const Icon(Icons.done,     size: 12, color: color);
    return const Icon(Icons.schedule, size: 12, color: color);
  }
}
