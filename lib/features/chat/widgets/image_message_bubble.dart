import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../../../features/media/providers/media_viewer_providers.dart';
import '../../../features/media/screens/media_viewer_screen.dart';
import 'expiry_badge.dart';
import 'media_retry.dart';
import 'media_upload_disc.dart';

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
  final bool runEnd;
  final String? status;
  final DateTime? createdAt;
  final String senderName;
  final String? localId;

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
    bare: widget.onTileTap != null,
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
        bare: widget.onTileTap != null,
        isMine: widget.isMine,
        runEnd: widget.runEnd,
        createdAt: widget.createdAt,
        status: widget.status,
        child: const _ImageSkeleton(),
      ),
      error: (_, __) => _BubbleWrapper(
        bare: widget.onTileTap != null,
        isMine: widget.isMine,
        runEnd: widget.runEnd,
        createdAt: widget.createdAt,
        status: widget.status,
        child: _ImageUnavailable(retry: thumbRef),
      ),
      data: (media) {
        if (media == null) {
          return _BubbleWrapper(
            bare: widget.onTileTap != null,
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

        final hero = Hero(
          tag: mediaHeroTag(widget.serverId),
          // Downloaded: the full photo at bubble size, so it
          // is never the small thumbnail blown up.
          child: full == null
              ? thumbImage
              : Image.file(
                  full,
                  fit: BoxFit.cover,
                  // A collage tile can be the full screen width.
                  cacheWidth:
                      ((widget.onTileTap != null
                                  ? MediaQuery.sizeOf(context).width
                                  : ChatBubbleGeometry.mediaMaxWidth) *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                  frameBuilder: (_, child, frame, sync) =>
                      sync || frame != null ? child : thumbImage,
                  errorBuilder: (_, __, ___) => thumbImage,
                ),
        );

        // ── actual bubble ──────────────────────────────────────
        return Semantics(
          button: true,
          label:
              widget.tileLabel ??
              (notDownloaded ? 'Open image, not downloaded' : 'Open image'),
          child: GestureDetector(
            // Opens at once on the thumbnail; the viewer loads the full file.
            onTap: widget.onTileTap ?? () => _openFullScreen(media.file),
            child: _BubbleWrapper(
              bare: widget.onTileTap != null,
              isMine: widget.isMine,
              runEnd: widget.runEnd,
              createdAt: widget.createdAt,
              status: widget.status,
              child: Stack(
                // A tile is sized by the album; the photo covers it.
                fit: widget.onTileTap != null
                    ? StackFit.expand
                    : StackFit.loose,
                children: [
                  if (widget.onTileTap != null)
                    hero
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: ChatBubbleGeometry.mediaMaxWidth,
                      ),
                      child: AspectRatio(
                        aspectRatio: _aspectRatio,
                        child: hero,
                      ),
                    ),
                  if (widget.localId != null)
                    Positioned.fill(
                      child: Center(
                        child: MediaUploadControl(
                          localId: widget.localId!,
                          status: widget.status,
                          kind: 'Photo',
                        ),
                      ),
                    )
                  else if (notDownloaded)
                    const Positioned.fill(
                      child: MediaDisc(icon: Icons.download_rounded),
                    ),
                  // Expiry badge — top right (an album shows one for all)
                  if (expiryLabel != null && widget.onTileTap == null)
                    ExpiryBadge(label: expiryLabel),
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
    this.bare = false,
  });

  final bool isMine;
  final bool runEnd;
  final Widget child;
  final DateTime? createdAt;
  final String? status;

  /// An album tile: the album draws the shell.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    if (bare) return child;
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
  Widget build(BuildContext context) => SizedBox(
    width: ChatBubbleGeometry.mediaMaxWidth,
    height: 158,
    child: const Skeleton.fill(radius: 0),
  );
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
