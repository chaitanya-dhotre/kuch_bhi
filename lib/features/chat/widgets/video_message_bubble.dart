import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/media_utils.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../../../features/media/providers/media_viewer_providers.dart';
import '../../../features/media/screens/media_viewer_screen.dart';
import 'expiry_badge.dart';

class VideoMessageBubble extends ConsumerStatefulWidget {
  const VideoMessageBubble({
    super.key,
    required this.conversationId,
    required this.serverId,
    required this.isMine,
    required this.isDark,
    this.runEnd = true,
    this.status,
    this.createdAt,
    this.senderName = '',
  });

  final String conversationId;
  final String serverId;
  final bool isMine;
  final bool isDark;
  final bool runEnd;
  final String? status;
  final DateTime? createdAt;
  final String senderName;

  @override
  ConsumerState<VideoMessageBubble> createState() => _VideoMessageBubbleState();
}

class _VideoMessageBubbleState extends ConsumerState<VideoMessageBubble> {
  double _aspectRatio = 16 / 9;

  String _durationText(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final thumbAsync = ref.watch(
      mediaFileProvider(
        MediaRef(widget.conversationId, widget.serverId, thumb: true),
      ),
    );

    Widget content = thumbAsync.when(
      loading: () => Shimmer.fromColors(
        baseColor: context.t.surface2,
        highlightColor: context.t.line,
        child: ColoredBox(color: context.t.surface2),
      ),
      error: (_, __) => Container(
        color: context.t.surface2,
        child: Center(
          child: Icon(Icons.videocam_off, color: context.t.inkFaint, size: 48),
        ),
      ),
      data: (media) {
        final durationSec = media?.durationSeconds ?? 0;
        final expiresAt = media?.expiresAt;

        // ── Expired state ──────────────────────────────────────
        if (isExpired(expiresAt)) {
          return const ExpiredPlaceholder(
            glyph: Icons.timer_off_outlined,
            decorate: false,
          );
        }

        if (media == null) {
          return Container(
            color: context.t.surface2,
            child: Center(
              child: Icon(
                Icons.videocam_off,
                color: context.t.inkFaint,
                size: 48,
              ),
            ),
          );
        }

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
          label: notDownloaded ? 'Open video, not downloaded' : 'Open video',
          child: GestureDetector(
            // Opens at once on the poster; the viewer loads the full file.
            onTap: () => pushMediaViewer(
              context,
              MediaViewerArgs(
                conversationId: widget.conversationId,
                serverId: widget.serverId,
                mediaType: 'video',
                senderName: widget.isMine
                    ? 'You'
                    : widget.senderName.isEmpty
                    ? 'Video'
                    : widget.senderName,
                timestamp: widget.createdAt ?? DateTime.now(),
                heroTag: 'media_${widget.serverId}',
                thumbPath: media.file.path,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: 'media_${widget.serverId}',
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
                MediaDisc(
                  icon: notDownloaded
                      ? Icons.download_rounded
                      : Icons.play_arrow,
                ),
                // Expiry badge — top right
                if (expiryLabel != null) ExpiryBadge(label: expiryLabel),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.videocam,
                                size: 10,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                _durationText(durationSec),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    return ChatBubbleFrame(
      isMine: widget.isMine,
      runEnd: widget.runEnd,
      padding: EdgeInsets.zero,
      showTimestamp: true,
      createdAt: widget.createdAt,
      status: widget.status,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ChatBubbleGeometry.mediaMaxWidth,
        ),
        child: AspectRatio(aspectRatio: _aspectRatio, child: content),
      ),
    );
  }
}
