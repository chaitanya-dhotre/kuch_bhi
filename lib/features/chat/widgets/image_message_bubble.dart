import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/pocketbase_client.dart';
import '../../../core/utils/media_utils.dart';
import '../../../features/chat/providers/chat_provider.dart';
import '../../../features/media/screens/media_viewer_screen.dart';
import '../../../features/media/widgets/expiry_badge.dart';

class ImageMessageBubble extends ConsumerStatefulWidget {
  const ImageMessageBubble({
    super.key,
    required this.serverId,
    required this.isMine,
    required this.isDark,
    this.status,
    this.createdAt,
  });

  final String   serverId;
  final bool     isMine;
  final bool     isDark;
  final String?  status;
  final DateTime? createdAt;

  @override
  ConsumerState<ImageMessageBubble> createState() =>
      _ImageMessageBubbleState();
}

class _ImageMessageBubbleState extends ConsumerState<ImageMessageBubble> {
  // Only aspect-ratio lives here; URL data comes from the cached provider.
  double _aspectRatio = 4 / 3;
  String? _resolvedThumbUrl; // tracks which URL we've already resolved dims for

  /// Reads the thumbnail's natural pixel dimensions via the image stream.
  /// Called once per unique URL after the provider delivers a value.
  void _resolveAspectRatio(String url) {
    if (_resolvedThumbUrl == url) return; // already resolved
    _resolvedThumbUrl = url;
    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (!mounted) return;
        final w = info.image.width;
        final h = info.image.height;
        if (w > 0 && h > 0) setState(() => _aspectRatio = w / h);
        stream.removeListener(listener);
      },
      onError: (_, __) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  void _openFullScreen(String fullUrl) {
    final token = ref.read(pocketbaseClientProvider).pb.authStore.token;
    final heroTag = 'media_${widget.serverId}';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          args: MediaViewerArgs(
            mediaUrl:   fullUrl,
            mediaType:  'image',
            authToken:  token,
            senderName: widget.isMine ? 'You' : 'Photo',
            timestamp:  widget.createdAt ?? DateTime.now(),
            heroTag:    heroTag,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = widget.isDark;
    final urlsAsync = ref.watch(imageUrlsProvider(widget.serverId));

    return urlsAsync.when(
      loading: () => _BubbleWrapper(
        isMine: widget.isMine,
        isDark: isDark,
        child: const SizedBox(
          width: 240, height: 160,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (_, __) => _BubbleWrapper(
        isMine: widget.isMine,
        isDark: isDark,
        child: const SizedBox(
          width: 240, height: 160,
          child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
        ),
      ),
      data: (urls) {
        if (urls == null || !urls.containsKey('thumb')) {
          return _BubbleWrapper(
            isMine: widget.isMine,
            isDark: isDark,
            child: const SizedBox(
              width: 240, height: 160,
              child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
            ),
          );
        }

        // ── Expiry check ───────────────────────────────────────
        final expiresRaw = urls['expires_at'] ?? '';
        final expiresAt  = expiresRaw.isNotEmpty
            ? DateTime.tryParse(expiresRaw)?.toLocal()
            : null;
        if (isExpired(expiresAt)) {
          return _BubbleWrapper(
            isMine: widget.isMine,
            isDark: isDark,
            child: const SizedBox(
              width: 240, height: 160,
              child: ExpiredMediaPlaceholder(width: 240, height: 160),
            ),
          );
        }

        final thumbUrl = urls['thumb']!;
        // Kick off dimension resolution (no-op if already done for this URL)
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => _resolveAspectRatio(thumbUrl));

        final fullUrl = urls['full'];
        if (fullUrl == null) return const SizedBox.shrink();

        // ── actual bubble ──────────────────────────────────────
        return GestureDetector(
          onTap: () => _openFullScreen(fullUrl),
          child: _BubbleWrapper(
            isMine: widget.isMine,
            isDark: isDark,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: AspectRatio(
                      aspectRatio: _aspectRatio,
                      child: Hero(
                        tag: 'media_${widget.serverId}',
                        child: CachedNetworkImage(
                          imageUrl: thumbUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Shimmer.fromColors(
                            baseColor: Colors.grey.shade300,
                            highlightColor: Colors.grey.shade100,
                            child: Container(color: Colors.grey.shade300),
                          ),
                          errorWidget: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Expiry badge — top right
                if (expiresAt != null)
                  ExpiryBadge(expiresAt: expiresAt),
                // Time + tick overlay at bottom-right
                if (widget.status != null)
                  Positioned(
                    right: 8,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.createdAt != null)
                            Text(
                              DateFormat('HH:mm')
                                  .format(widget.createdAt!.toLocal()),
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white70,
                              ),
                            ),
                          if (widget.isMine) ...[
                            if (widget.createdAt != null)
                              const SizedBox(width: 4),
                            _TickIndicator(
                              status: widget.status!,
                              isMine: widget.isMine,
                            ),
                          ],
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
  }
}

// ── Bubble wrapper — matches _TextBubble styling ────────────────────────────

class _BubbleWrapper extends StatelessWidget {
  const _BubbleWrapper({
    required this.isMine,
    required this.isDark,
    required this.child,
  });

  final bool     isMine;
  final bool     isDark;
  final Widget   child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        left:   isMine ? 64 : 12,
        right:  isMine ? 12 : 64,
        top:    2,
        bottom: 2,
      ),
      decoration: BoxDecoration(
        color: isMine
            ? AppColors.sentBubble
            : isDark
                ? AppColors.receivedBubbleDark
                : AppColors.receivedBubbleLight,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset:     const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: child,
      ),
    );
  }
}

// ── Tick indicator (simplified, no isDark needed ───────────────────────────

class _TickIndicator extends StatelessWidget {
  const _TickIndicator({
    required this.status,
    required this.isMine,
  });

  final String status;
  final bool   isMine;

  @override
  Widget build(BuildContext context) {
    const tickColor = Colors.white70;

    if (status == 'sent') {
      return const Icon(Icons.done, size: 12, color: tickColor);
    }
    if (status == 'delivered') {
      return const Icon(Icons.done_all, size: 12, color: tickColor);
    }
    if (status == 'read') {
      return const Icon(Icons.done_all, size: 12, color: Colors.white);
    }
    return const Icon(Icons.schedule, size: 12, color: tickColor);
  }
}

