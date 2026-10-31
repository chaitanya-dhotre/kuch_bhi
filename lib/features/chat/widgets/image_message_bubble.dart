import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/media_utils.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../../../features/media/providers/media_viewer_providers.dart';
import '../../../features/media/screens/media_viewer_screen.dart';
import 'expiry_badge.dart';
import 'media_retry.dart';

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
  ConsumerState<ImageMessageBubble> createState() => _ImageMessageBubbleState();
}

class _ImageMessageBubbleState extends ConsumerState<ImageMessageBubble> {
  double _aspectRatio = 4 / 3;

  void _openFullScreen(File thumb) {
    pushMediaViewer(
      context,
      MediaViewerArgs(
        conversationId: widget.conversationId,
        serverId: widget.serverId,
        mediaType: 'image',
        senderName: widget.isMine
            ? 'You'
            : widget.senderName.isEmpty
            ? kMediaRowPhotoLabel
            : widget.senderName,
        timestamp: widget.createdAt ?? DateTime.now(),
        heroTag: mediaHeroTag(widget.serverId),
        thumbPath: thumb.path,
      ),
    );
  }

  Widget _expired() => _BubbleWrapper(
    isMine: widget.isMine,
    runEnd: widget.runEnd,
    createdAt: widget.createdAt,
    status: widget.status,
    child: SizedBox(
      width: ChatBubbleGeometry.mediaMaxWidth,
      height: 158,
      child: ExpiredPlaceholder(
        glyph: Icons.timer_off_outlined,
        decorate: false,
        ink: widget.isMine ? context.t.onAccent.withValues(alpha: 0.70) : null,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Purged on the server for sure: no download, no retry.
    if (isPastRetention('image', widget.createdAt)) return _expired();
    final thumbRef = MediaRef(
      widget.conversationId,
      widget.serverId,
      thumb: true,
    );
    final thumbAsync = ref.watch(mediaFileProvider(thumbRef));

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
        child: _ImageUnavailable(retry: thumbRef),
      ),
      data: (media) {
        if (media == null) {
          return _BubbleWrapper(
            isMine: widget.isMine,
            runEnd: widget.runEnd,
            createdAt: widget.createdAt,
            status: widget.status,
            child: _ImageUnavailable(retry: thumbRef),
          );
        }

        // ── Expiry check ───────────────────────────────────────
        final expiresAt = media.expiresAt;
        if (isExpired(expiresAt)) return _expired();

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
        // Only on a positive "not on disk": an unknown row shows no disc.
        final notDownloaded = local.hasValue && local.value == null;
        final full = local.valueOrNull;
        final thumbImage = Image.file(
          media.file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _ImageUnavailable(),
        );

        // ── actual bubble ──────────────────────────────────────
        return Semantics(
          button: true,
          label: notDownloaded ? 'Open image, not downloaded' : 'Open image',
          child: GestureDetector(
            // Opens at once on the thumbnail; the viewer loads the full file.
            onTap: () => _openFullScreen(media.file),
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
                        tag: mediaHeroTag(widget.serverId),
                        // Downloaded: the full photo at bubble size, so it
                        // is never the small thumbnail blown up.
                        child: full == null
                            ? thumbImage
                            : Image.file(
                                full,
                                fit: BoxFit.cover,
                                cacheWidth: (ChatBubbleGeometry.mediaMaxWidth *
                                        MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                                frameBuilder: (_, child, frame, sync) =>
                                    sync || frame != null ? child : thumbImage,
                                errorBuilder: (_, __, ___) => thumbImage,
                              ),
                      ),
                    ),
                  ),
                  if (notDownloaded)
                    const Positioned.fill(
                      child: MediaDisc(icon: Icons.download_rounded),
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
  const _ImageUnavailable({this.retry});

  /// Set when the load came back empty (a retry can help, not a bad file).
  final MediaRef? retry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ChatBubbleGeometry.mediaMaxWidth,
      height: 158,
      color: context.t.surface2,
      alignment: Alignment.center,
      child: retry == null
          ? Icon(Icons.broken_image_outlined, color: context.t.inkFaint)
          : MediaRetry(
              media: retry!,
              what: kMediaRowPhotoLabel,
              icon: Icons.broken_image_outlined,
            ),
    );
  }
}
