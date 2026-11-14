import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/media_utils.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../../../features/media/providers/media_viewer_providers.dart';
import '../../../features/media/screens/media_viewer_screen.dart';
import 'expiry_badge.dart';
import 'media_retry.dart';
import 'media_upload_disc.dart';

class VideoMessageBubble extends ConsumerStatefulWidget {
  const VideoMessageBubble({
    super.key,
    required this.conversationId,
    required this.serverId,
    required this.isMine,
    required this.isDark,
    this.runStart = true,
    this.status,
    this.createdAt,
    this.senderName = '',
    this.localId,
    this.onTileTap,
    this.tileLabel,
  });

  /// Set = an album tile (12.5 D3): no bubble shell or own expiry badge,
  /// and a tap opens the album instead of the viewer.
  final VoidCallback? onTileTap;
  final String? tileLabel;

  final String conversationId;
  final String serverId;
  final bool isMine;
  final bool isDark;
  final bool runStart;
  final String? status;
  final DateTime? createdAt;
  final String senderName;
  final String? localId;

  @override
  ConsumerState<VideoMessageBubble> createState() => _VideoMessageBubbleState();
}

class _VideoMessageBubbleState extends ConsumerState<VideoMessageBubble> {
  double _aspectRatio = 16 / 9;

  @override
  Widget build(BuildContext context) {
    final thumbRef = MediaRef(
      widget.conversationId,
      widget.serverId,
      thumb: true,
    );
    // Purged on the server for sure: no download, no retry.
    final gone = isPastRetention('video', widget.createdAt);
    final thumbAsync = gone
        ? const AsyncData(null)
        : ref.watch(mediaFileProvider(thumbRef));
    Widget unavailable() => ColoredBox(
      color: context.t.surface2,
      child: MediaRetry(
        media: thumbRef,
        what: kMediaRowVideoLabel,
        icon: Icons.videocam_off,
      ),
    );

    Widget content = thumbAsync.when(
      // F: a flat box with the video glyph until the poster lands.
      loading: () => Center(
        child: Icon(
          Icons.videocam_outlined,
          size: 28,
          color: context.t.inkFaint,
        ),
      ),
      error: (_, __) => unavailable(),
      data: (media) {
        final durationSec = media?.durationSeconds ?? 0;
        final expiresAt = media?.expiresAt;

        // ── Expired state ──────────────────────────────────────
        if (gone || isExpired(expiresAt)) {
          return const ExpiredPlaceholder(
            glyph: Icons.timer_off_outlined,
            decorate: false,
          );
        }

        if (media == null) return unavailable();

        if (media.width != null &&
            media.height != null &&
            media.width! > 0 &&
            media.height! > 0) {
          _aspectRatio = media.width! / media.height!;
        }

        final expiryLabel = compactExpiryLabel(expiresAt);
        final local = ref.watch(
          mediaFullLocalProvider(
            MediaRef(widget.conversationId, widget.serverId),
          ),
        );
        // Only on a positive "not on disk": an unknown row keeps Play.
        final notDownloaded = local.hasValue && local.value == null;

        return Semantics(
          button: true,
          label:
              widget.tileLabel ??
              (notDownloaded ? 'Open video, not downloaded' : 'Open video'),
          child: GestureDetector(
            // Opens at once on the poster; the viewer loads the full file.
            onTap: widget.onTileTap ?? () => pushMediaViewer(
              context,
              MediaViewerArgs(
                conversationId: widget.conversationId,
                serverId: widget.serverId,
                mediaType: 'video',
                senderName: widget.isMine
                    ? 'You'
                    : widget.senderName.isEmpty
                    ? kMediaRowVideoLabel
                    : widget.senderName,
                timestamp: widget.createdAt ?? DateTime.now(),
                heroTag: mediaHeroTag(widget.serverId),
                thumbPath: media.file.path,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: mediaHeroTag(widget.serverId),
                  child: Image.file(
                    media.file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: context.t.surface2,
                      child: Center(
                        child: Icon(
                          Icons.broken_image,
                          color: context.t.inkFaint,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.localId != null)
                  Center(
                    child: MediaUploadControl(
                      localId: widget.localId!,
                      status: widget.status,
                      kind: 'Video',
                    ),
                  )
                else
                  const MediaDisc(icon: Icons.play_arrow),
                // Expiry badge — top right (an album shows one for all)
                if (expiryLabel != null && widget.onTileTap == null)
                  ExpiryBadge(label: expiryLabel),
                // E2: duration, plus the size only on a known "not on disk".
                Positioned(
                  left: 8,
                  bottom: 8,
                  // Its text joins the tile's label (album D7: "… 0:14").
                  child: MediaOverlayPill(
                    child: Text(
                      videoPillLabel(
                        durationSec,
                        notDownloaded ? media.fileSize : null,
                      ),
                      style: const TextStyle(
                        fontSize: ChatBubbleGeometry.timestampFontSize,
                        height: ChatBubbleGeometry.timestampLineHeight,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (widget.onTileTap != null) return content;
    final width = ChatBubbleGeometry.attachmentWidthOf(context);
    // E1/E2: edge to edge, B1 radius, no border.
    return ChatBubbleFrame(
      isMine: widget.isMine,
      runStart: widget.runStart,
      padding: EdgeInsets.zero,
      background: context.t.surface2,
      border: const Border(),
      child: SizedBox(
        width: width,
        height: ChatBubbleGeometry.mediaHeight(width, _aspectRatio),
        child: content,
      ),
    );
  }
}

/// E2: "0:42" or "0:42 · 8.1 MB" (size only when the file is known to be
/// missing and its size is known).
String videoPillLabel(int seconds, int? bytes) => [
  formatMmSs(seconds),
  if (bytes != null && bytes > 0) formatFileSize(bytes, bytesUnitSpaced: true),
].join(' · ');
