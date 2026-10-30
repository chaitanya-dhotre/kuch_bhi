import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import 'delivery_tick.dart';

String? compactExpiryLabel(DateTime? expiresAt) {
  if (expiresAt == null) return null;
  final remaining = expiresAt.difference(DateTime.now());
  if (remaining.isNegative || remaining.inDays > 7) return null;
  if (remaining.inHours < 24) {
    final hours = remaining.inHours < 1 ? 1 : remaining.inHours;
    return '${hours}h';
  }
  final days = remaining.inDays < 1 ? 1 : remaining.inDays;
  return '${days}d';
}

/// The fullscreen viewer's line saying when the server drops the media.
/// Same thresholds as [compactExpiryLabel], but always shown (null only when
/// there is no date or it has passed).
String? viewerExpiryLabel(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return null;
  now ??= DateTime.now();
  final remaining = expiresAt.difference(now);
  if (remaining.isNegative) return null;
  if (remaining.inDays > 7) {
    final local = expiresAt.toLocal();
    final pattern = local.year == now.toLocal().year ? 'MMM d' : 'MMM d, yyyy';
    return 'Expires ${DateFormat(pattern).format(local)}';
  }
  if (remaining.inHours < 24) {
    final hours = remaining.inHours < 1 ? 1 : remaining.inHours;
    return 'Expires in $hours ${hours == 1 ? 'hour' : 'hours'}';
  }
  final days = remaining.inDays;
  return 'Expires in $days ${days == 1 ? 'day' : 'days'}';
}

/// Shared geometry for every non-system chat message surface.
///
/// Keeping the frame here prevents each media type from inventing its own
/// margins, width cap, radius, shadow, and metadata rhythm.
class ChatBubbleGeometry {
  ChatBubbleGeometry._();

  static const double maxWidthFactor = 0.84;
  static const double nearMargin = 12;
  static const double farMargin = 64;
  static const double verticalMargin = 2;
  static const double mediaMaxWidth = 210;
  static const double timestampFontSize = 10.5;
  static const double metadataGap = 2;
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );

  static double maxWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width * maxWidthFactor;

  static EdgeInsets margin({required bool isMine}) => EdgeInsets.only(
    left: isMine ? farMargin : nearMargin,
    right: isMine ? nearMargin : farMargin,
    top: verticalMargin,
    bottom: verticalMargin,
  );

  static BorderRadius radius({required bool isMine, required bool runEnd}) {
    final tail = const Radius.circular(WarmPopTokens.radiusBubbleTail);
    final full = const Radius.circular(WarmPopTokens.radiusBubble);
    return BorderRadius.only(
      topLeft: full,
      topRight: full,
      bottomLeft: !isMine && runEnd ? tail : full,
      bottomRight: isMine && runEnd ? tail : full,
    );
  }

  static List<BoxShadow> shadow(
    BuildContext context, {
    required bool isMine,
    bool enabled = true,
  }) {
    if (!enabled || !isMine) return const [];
    return [
      BoxShadow(
        color: context.t.shadow,
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }
}

/// The single outer frame used by text, emoji, media, voice, and documents.
class ChatBubbleFrame extends StatelessWidget {
  const ChatBubbleFrame({
    super.key,
    required this.isMine,
    required this.runEnd,
    required this.child,
    this.chrome = true,
    this.padding = ChatBubbleGeometry.contentPadding,
    this.fillWidth = false,
    this.showShadow = true,
    this.showTimestamp = false,
    this.timestampOverlay = true,
    this.timestampPadding = EdgeInsets.zero,
    this.createdAt,
    this.status,
    this.background,
    this.border,
  });

  final bool isMine;
  final bool runEnd;
  final Widget child;
  final bool chrome;
  final EdgeInsets? padding;
  final bool fillWidth;
  final bool showShadow;
  final bool showTimestamp;
  final bool timestampOverlay;
  final EdgeInsets timestampPadding;
  final DateTime? createdAt;
  final String? status;
  final Color? background;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final bubbleRadius = ChatBubbleGeometry.radius(
      isMine: isMine,
      runEnd: runEnd,
    );
    Widget content = child;
    final hasTimestamp =
        showTimestamp && runEnd && (createdAt != null || status != null);
    if (hasTimestamp && !timestampOverlay) {
      Widget timestamp = Align(
        alignment: Alignment.centerRight,
        child: ChatBubbleTimestamp(
          isMine: isMine,
          createdAt: createdAt,
          status: status,
        ),
      );
      if (timestampPadding != EdgeInsets.zero) {
        timestamp = Padding(padding: timestampPadding, child: timestamp);
      }
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          const SizedBox(height: ChatBubbleGeometry.metadataGap),
          timestamp,
        ],
      );
    }
    if (padding != null) content = Padding(padding: padding!, child: content);
    if (fillWidth) content = SizedBox(width: double.infinity, child: content);
    if (hasTimestamp && timestampOverlay) {
      content = Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned(
            right: 8,
            bottom: 6,
            child: ChatBubbleTimestamp(
              isMine: isMine,
              createdAt: createdAt,
              status: status,
              overlay: true,
            ),
          ),
        ],
      );
    }
    if (chrome) {
      content = ClipRRect(borderRadius: bubbleRadius, child: content);
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: ChatBubbleGeometry.margin(isMine: isMine),
        constraints: BoxConstraints(
          maxWidth: ChatBubbleGeometry.maxWidth(context),
        ),
        decoration: chrome
            ? BoxDecoration(
                color:
                    background ??
                    (isMine ? context.t.accent : context.t.surface),
                border: border,
                borderRadius: bubbleRadius,
                boxShadow: ChatBubbleGeometry.shadow(
                  context,
                  isMine: isMine,
                  enabled: showShadow,
                ),
              )
            : null,
        child: content,
      ),
    );
  }
}

/// Canonical timestamp/tick row. Media can opt into the same row in an
/// image/video overlay while text-like bubbles keep it on the bubble surface.
class ChatBubbleTimestamp extends StatelessWidget {
  const ChatBubbleTimestamp({
    super.key,
    required this.isMine,
    this.createdAt,
    this.status,
    this.overlay = false,
  });

  final bool isMine;
  final DateTime? createdAt;
  final String? status;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final color = overlay
        ? Colors.white.withValues(alpha: 0.66)
        : isMine
        ? context.t.onAccent.withValues(alpha: 0.66)
        : context.t.inkFaint.withValues(alpha: 0.66);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (createdAt != null)
          Text(
            DateFormat('HH:mm').format(createdAt!.toLocal()),
            style: TextStyle(
              fontSize: ChatBubbleGeometry.timestampFontSize,
              color: color,
            ),
          ),
        if (isMine && status != null) ...[
          if (createdAt != null)
            const SizedBox(width: ChatBubbleGeometry.metadataGap),
          DeliveryTick(status: status!, size: 12),
        ],
      ],
    );

    if (!overlay) return ExcludeSemantics(child: row);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ExcludeSemantics(child: row),
    );
  }
}

/// Compact expiry affordance for media overlays.
///
/// The widget is positioned so media stacks can add it directly as a child,
/// matching the chat spec's top-right placement.
class ExpiryBadge extends StatelessWidget {
  const ExpiryBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Positioned(
      top: 6,
      right: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ).copyWith(color: t.accentSoft),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 11, color: t.accentPressed),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: t.ink,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centre disc on a media bubble: play, or download when the full file is
/// not on the phone yet (the thumbnail alone must not look loaded).
class MediaDisc extends StatelessWidget {
  const MediaDisc({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );
  }
}

/// Shared expired-media placeholder for every media type.
class ExpiredPlaceholder extends StatelessWidget {
  const ExpiredPlaceholder({
    super.key,
    required this.glyph,
    this.decorate = true,
  });

  final IconData glyph;
  final bool decorate;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final dimmedInk = t.inkSoft.withValues(alpha: 0.5);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(glyph, color: dimmedInk, size: 20),
        const SizedBox(height: 5),
        Text(
          'Media expired',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: dimmedInk,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    if (!decorate) return content;
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusBubble),
      ),
      child: content,
    );
  }
}
