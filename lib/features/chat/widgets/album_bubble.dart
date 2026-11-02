
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../domain/entities/message.dart';
import '../providers/chat_provider.dart';
import '../providers/upload_progress_provider.dart';
import 'expiry_badge.dart';
import 'image_message_bubble.dart';
import 'video_message_bubble.dart';

/// C16 (12.5): one bubble for 2–20 photos and videos sent together. The
/// tiles scroll sideways; the count, time and expiry pills stay put. Each
/// tile is the single photo/video bubble in tile mode, so its states are
/// that bubble's rules, not a copy.
class AlbumBubble extends ConsumerWidget {
  const AlbumBubble({
    super.key,
    required this.rows,
    required this.isMine,
    this.runEnd = true,
    this.senderName = '',
    this.onOpen,
  });

  /// In album order (grouping sorts them).
  final List<Message> rows;
  final bool isMine;
  final bool runEnd;
  final String senderName;

  /// Tap on tile i (D5).
  final ValueChanged<int>? onOpen;

  static const tileHeight = 180.0;
  static const _pad = 4.0;
  static const _gap = 4.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const width = ChatBubbleGeometry.mediaMaxWidth;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputs = [
      for (final m in rows) mediaBubbleInputs(ref, m, isMine: isMine),
    ];
    // The tiles watch the same thumbnails; this reads size and expiry.
    final metas = [
      for (var i = 0; i < rows.length; i++)
        inputs[i].mediaId == null ||
                isPastRetention(rows[i].type, rows[i].createdAt)
            ? null
            : ref
                  .watch(
                    mediaFileProvider(
                      MediaRef(
                        rows[i].conversationId,
                        inputs[i].mediaId!,
                        thumb: true,
                      ),
                    ),
                  )
                  .valueOrNull,
    ];

    // D2: ticks = the least advanced item; a clock until all are sent.
    const rank = {'sent': 1, 'delivered': 2, 'read': 3};
    final least = inputs
        .map((x) => x.status)
        .reduce((a, b) => (rank[a] ?? 0) <= (rank[b] ?? 0) ? a : b);
    final status = (rank[least] ?? 0) == 0 ? 'pending' : least;
    final earliest = rows
        .map((m) => m.createdAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    DateTime? expiresAt;
    for (final e in metas.map((m) => m?.expiresAt)) {
      if (e == null || isExpired(e)) continue;
      if (expiresAt == null || e.isBefore(expiresAt)) expiresAt = e;
    }
    final expiryLabel = compactExpiryLabel(expiresAt);

    Widget tile(int i) {
      final m = rows[i];
      final input = inputs[i];
      final meta = metas[i];
      final w = meta?.width ?? 0;
      final h = meta?.height ?? 0;
      final aspect = w > 0 && h > 0 ? w / h : 1.0;
      final video = m.type == 'video';
      final label = albumTileLabel(
        index: i,
        count: rows.length,
        video: video,
        sending: input.uploadLocalId != null && input.status != 'failed',
        failed: input.status == 'failed',
      );
      void open() => onOpen?.call(i);
      final Widget child;
      if (input.mediaId == null) {
        child = const Skeleton.fill(radius: 0);
      } else if (video) {
        child = VideoMessageBubble(
          conversationId: m.conversationId,
          serverId: input.mediaId!,
          isMine: isMine,
          isDark: isDark,
          status: input.status,
          createdAt: m.createdAt,
          senderName: senderName,
          localId: input.uploadLocalId,
          onTileTap: open,
          tileLabel: label,
        );
      } else {
        child = ImageMessageBubble(
          conversationId: m.conversationId,
          serverId: input.mediaId!,
          isMine: isMine,
          isDark: isDark,
          status: input.status,
          createdAt: m.createdAt,
          senderName: senderName,
          localId: input.uploadLocalId,
          onTileTap: open,
          tileLabel: label,
        );
      }
      // Loading / ended tiles have no tap of their own; buttons on a tile
      // (cancel, Try again) win the arena first.
      return GestureDetector(
        key: ValueKey(m.localId),
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: (tileHeight * aspect).clamp(100.0, width - 40),
            height: tileHeight,
            child: child,
          ),
        ),
      );
    }

    return ChatBubbleFrame(
      isMine: isMine,
      runEnd: runEnd,
      padding: EdgeInsets.zero,
      showTimestamp: true,
      createdAt: earliest,
      status: status,
      border: isMine ? Border.all(color: context.t.accent, width: 2) : null,
      child: Stack(
        children: [
          SizedBox(
            width: width,
            height: tileHeight + 2 * _pad,
            // D8: no flight from the chat into the collage.
            child: HeroMode(
              enabled: false,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(_pad),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(width: _gap),
                itemBuilder: (_, i) => tile(i),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 56, maxHeight: 22),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: MediaOverlayPill(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.collections_outlined, size: 11),
                        const SizedBox(width: 3),
                        Text(
                          '${rows.length}',
                          style: const TextStyle(
                            fontSize: ChatBubbleGeometry.timestampFontSize,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (expiryLabel != null)
            ExpiryBadge(label: expiryLabel, bottomLeft: true),
        ],
      ),
    );
  }
}

/// D7: "Photo 1 of 5" / "Video 2 of 5", plus the tile's state. A video
/// tile's length chip adds its own text ("0:14") to the same node.
String albumTileLabel({
  required int index,
  required int count,
  required bool video,
  bool sending = false,
  bool failed = false,
}) {
  final kind = video ? kMediaRowVideoLabel : kMediaRowPhotoLabel;
  return [
    '$kind ${index + 1} of $count',
    if (sending) 'sending',
    if (failed) 'not sent',
  ].join(', ');
}
