import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/media_utils.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../../../features/media/screens/media_viewer_screen.dart';
import 'expiry_badge.dart';

class ImageMessageBubble extends ConsumerStatefulWidget {
  const ImageMessageBubble({
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
  ConsumerState<ImageMessageBubble> createState() => _ImageMessageBubbleState();
}

class _ImageMessageBubbleState extends ConsumerState<ImageMessageBubble> {
  double _aspectRatio = 4 / 3;

  void _openFullScreen(File fullFile) {
    final heroTag = 'media_${widget.serverId}';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          args: MediaViewerArgs(
            localPath: fullFile.path,
            mediaType: 'image',
            senderName: widget.isMine ? 'You' : 'Photo',
            timestamp: widget.createdAt ?? DateTime.now(),
            heroTag: heroTag,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumbAsync = ref.watch(
      mediaFileProvider(
        MediaRef(widget.conversationId, widget.serverId, thumb: true),
      ),
    );

    return thumbAsync.when(
      loading: () => _BubbleWrapper(
        isMine: widget.isMine,
        runEnd: widget.runEnd,
        createdAt: widget.createdAt,
        status: widget.status,
        child: const _ImageSkeleton(),
      ),
      error: (_, __) => _BubbleWrapper(
        isMine: widget.isMine,
        runEnd: widget.runEnd,
        createdAt: widget.createdAt,
        status: widget.status,
        child: const _ImageUnavailable(),
      ),
      data: (media) {
        if (media == null) {
          return _BubbleWrapper(
            isMine: widget.isMine,
            runEnd: widget.runEnd,
            createdAt: widget.createdAt,
            status: widget.status,
            child: const _ImageUnavailable(),
          );
        }

        // ── Expiry check ───────────────────────────────────────
        final expiresAt = media.expiresAt;
        if (isExpired(expiresAt)) {
          return _BubbleWrapper(
            isMine: widget.isMine,
            runEnd: widget.runEnd,
            createdAt: widget.createdAt,
            status: widget.status,
            child: const SizedBox(
              width: ChatBubbleGeometry.mediaMaxWidth,
              height: 158,
              child: ExpiredPlaceholder(
                glyph: Icons.timer_off_outlined,
                decorate: false,
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

        // ── actual bubble ──────────────────────────────────────
        return Semantics(
          button: true,
          label: 'Open image',
          child: GestureDetector(
            onTap: () async {
              // Fetch the full-res file on tap, then open the viewer.
              final full = await ref.read(
                mediaFileProvider(
                  MediaRef(widget.conversationId, widget.serverId),
                ).future,
              );
              if (full != null && mounted) _openFullScreen(full.file);
            },
            child: _BubbleWrapper(
              isMine: widget.isMine,
              runEnd: widget.runEnd,
              createdAt: widget.createdAt,
              status: widget.status,
              child: Stack(
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ChatBubbleGeometry.mediaMaxWidth,
                    ),
                    child: AspectRatio(
                      aspectRatio: _aspectRatio,
                      child: Hero(
                        tag: 'media_${widget.serverId}',
                        child: Image.file(
                          media.file,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const _ImageUnavailable(),
                        ),
                      ),
                    ),
                  ),
                  // Expiry badge — top right
                  if (expiryLabel != null) ExpiryBadge(label: expiryLabel),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Bubble wrapper — matches _TextBubble styling ────────────────────────────

class _BubbleWrapper extends StatelessWidget {
  const _BubbleWrapper({
    required this.isMine,
    required this.child,
    this.runEnd = true,
    this.createdAt,
    this.status,
  });

  final bool isMine;
  final bool runEnd;
  final Widget child;
  final DateTime? createdAt;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return ChatBubbleFrame(
      isMine: isMine,
      runEnd: runEnd,
      padding: EdgeInsets.zero,
      showTimestamp: true,
      createdAt: createdAt,
      status: status,
      border: isMine ? Border.all(color: context.t.accent, width: 2) : null,
      child: child,
    );
  }
}

class _ImageSkeleton extends StatelessWidget {
  const _ImageSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final surface = SizedBox(
      width: ChatBubbleGeometry.mediaMaxWidth,
      height: 158,
      child: ColoredBox(color: t.surface2),
    );
    if (MediaQuery.disableAnimationsOf(context)) return surface;

    return Shimmer.fromColors(
      baseColor: t.surface2,
      highlightColor: t.line,
      child: surface,
    );
  }
}

class _ImageUnavailable extends StatelessWidget {
  const _ImageUnavailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ChatBubbleGeometry.mediaMaxWidth,
      height: 158,
      color: context.t.surface2,
      alignment: Alignment.center,
      child: Icon(Icons.broken_image_outlined, color: context.t.inkFaint),
    );
  }
}
