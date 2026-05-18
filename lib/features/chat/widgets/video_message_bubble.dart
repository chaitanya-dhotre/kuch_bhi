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

class VideoMessageBubble extends ConsumerStatefulWidget {
  const VideoMessageBubble({
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
  ConsumerState<VideoMessageBubble> createState() => _VideoMessageBubbleState();
}

class _VideoMessageBubbleState extends ConsumerState<VideoMessageBubble> {
  // Only aspect-ratio lives here; URL/duration data comes from the cached provider.
  double  _aspectRatio      = 16 / 9;
  String? _resolvedThumbUrl;

  void _resolveThumbAspectRatio(String url) {
    if (_resolvedThumbUrl == url) return;
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

  String _durationText(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bg     = widget.isMine ? AppColors.sentBubble : (widget.isDark ? AppColors.receivedBubbleDark : AppColors.receivedBubbleLight);
    final shadow = widget.isMine
        ? BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))
        : BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2));

    final urlsAsync = ref.watch(videoUrlsProvider(widget.serverId));

    Widget content = urlsAsync.when(
      loading: () => Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Container(color: Colors.grey),
      ),
      error: (_, __) => Container(
        color: Colors.grey.shade800,
        child: const Center(child: Icon(Icons.videocam_off, color: Colors.white54, size: 48)),
      ),
      data: (urls) {
        final thumbUrl    = urls?['thumb'];
        final videoUrl    = urls?['full'];
        final durationSec = int.tryParse(urls?['duration'] ?? '0') ?? 0;
        final expiresRaw  = urls?['expires_at'] ?? '';
        final expiresAt   = expiresRaw.isNotEmpty
            ? DateTime.tryParse(expiresRaw)?.toLocal()
            : null;

        // ── Expired state ──────────────────────────────────────
        if (isExpired(expiresAt)) {
          return const ExpiredMediaPlaceholder();
        }

        if (thumbUrl != null && thumbUrl.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => _resolveThumbAspectRatio(thumbUrl));
        }

        if (thumbUrl == null) {
          return Container(
            color: Colors.grey.shade800,
            child: const Center(child: Icon(Icons.videocam_off, color: Colors.white54, size: 48)),
          );
        }

        return GestureDetector(
          onTap: videoUrl != null
              ? () {
                  final token =
                      ref.read(pocketbaseClientProvider).pb.authStore.token;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MediaViewerScreen(
                        args: MediaViewerArgs(
                          mediaUrl:   videoUrl,
                          mediaType:  'video',
                          authToken:  token,
                          senderName: widget.isMine ? 'You' : 'Video',
                          timestamp:  widget.createdAt ?? DateTime.now(),
                        ),
                      ),
                    ),
                  );
                }
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: thumbUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => Shimmer.fromColors(
                  baseColor: Colors.grey.shade300,
                  highlightColor: Colors.grey.shade100,
                  child: Container(color: Colors.grey),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey.shade800,
                  child: const Center(child: Icon(Icons.broken_image, color: Colors.white54)),
                ),
              ),
              Center(
                child: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 28),
                ),
              ),
              // Expiry badge — top right
              if (expiresAt != null)
                ExpiryBadge(expiresAt: expiresAt),
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end:   Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.videocam, size: 10, color: Colors.white70),
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
                      const Spacer(),
                      if (widget.status != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.createdAt != null)
                                Text(
                                  DateFormat('HH:mm').format(widget.createdAt!.toLocal()),
                                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                                ),
                              if (widget.isMine) ...[
                                if (widget.createdAt != null) const SizedBox(width: 4),
                                _TickIndicator(status: widget.status!, isMine: widget.isMine),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    return Align(
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin:  const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        constraints: const BoxConstraints(maxWidth: 240),
        decoration: BoxDecoration(
          color:        bg,
          borderRadius: BorderRadius.circular(18),
          boxShadow:    [shadow],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: _aspectRatio,
            child: content,
          ),
        ),
      ),
    );
  }
}

// ── Tick indicator ───────────────────────────────────────────────────────

class _TickIndicator extends StatelessWidget {
  const _TickIndicator({required this.status, required this.isMine});

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
