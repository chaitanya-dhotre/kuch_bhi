import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import 'delivery_tick.dart';
import '../message_offline_policy.dart';

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

/// Shared geometry for every non-system chat message surface (chat calm
/// §A–§C). `W` is the screen width in dp.
class ChatBubbleGeometry {
  ChatBubbleGeometry._();

  /// A7: the bubble's own side; the far side is what A1/A2 leave.
  static const double nearMargin = 12;

  /// C1 / C2: between bubbles of one run, and before a new run.
  static const double runGap = 2;
  static const double newRunGap = 12;

  /// B2: the time line sits this far under a run's last bubble.
  static const double metaGap = 4;

  /// B5: the time line's type, 11/14.
  static const double timestampFontSize = 11;
  static const double timestampLineHeight = 14 / 11;

  /// C4: text bubbles. C5: voice and document bubbles.
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 9,
  );
  static const EdgeInsets attachmentPadding = EdgeInsets.all(10);

  /// C6: the leading disc or tile in voice and document bubbles.
  static const double leadingSize = 40;

  /// C9: the group sender disc, and the slot it takes beside the bubble.
  static const double senderDisc = 28;
  static const double senderSlot = nearMargin + senderDisc;

  /// A1: text bubble max width.
  static double textMaxWidth(double w) => math.min(w * 0.78, 420);

  /// A2: photo, video, album, voice, document, link card.
  static double attachmentWidth(double w) =>
      (w * 0.66).clamp(240.0, 340.0).toDouble();

  /// A3: photo and video height for [aspect] = width / height.
  static double mediaHeight(double width, double aspect) =>
      (width / (aspect > 0 ? aspect : 4 / 3))
          .clamp(0.56 * width, 1.25 * width)
          .toDouble();

  /// A5: album tile height.
  static double albumTileHeight(double width) => 0.72 * width;

  static double maxWidth(BuildContext context) =>
      textMaxWidth(MediaQuery.sizeOf(context).width);

  static double attachmentWidthOf(BuildContext context) =>
      attachmentWidth(MediaQuery.sizeOf(context).width);

  static EdgeInsets margin({required bool isMine}) => EdgeInsets.only(
    left: isMine ? 0 : nearMargin,
    right: isMine ? nearMargin : 0,
  );

  /// B1: radius 18; on the sender's side the bottom corner is always 6 and
  /// the top is 6 unless the bubble starts a run. Far side always 18.
  static BorderRadius radius({required bool isMine, required bool runStart}) {
    const tail = Radius.circular(WarmPopTokens.radiusBubbleTail);
    const full = Radius.circular(WarmPopTokens.radiusBubble);
    final top = runStart ? full : tail;
    return BorderRadius.only(
      topLeft: isMine ? full : top,
      topRight: isMine ? top : full,
      bottomLeft: isMine ? full : tail,
      bottomRight: isMine ? tail : full,
    );
  }
}

/// K2 (mascot spec §K2): while on, every bubble shows its time and ticks,
/// not only a run's last one. Only shows (V2): nothing is sent or saved.
class ChatInfoMode extends InheritedWidget {
  const ChatInfoMode({super.key, required this.on, required super.child});

  final bool on;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatInfoMode>()?.on ?? false;

  @override
  bool updateShouldNotify(ChatInfoMode old) => on != old.on;
}

/// The single outer frame used by text, media, voice, and documents. It
/// holds only content: the time lives on the line under the run (B2).
class ChatBubbleFrame extends StatelessWidget {
  /// Motion C1: the [MetaData] tag on the bubble's own box.
  static const box = #chatBubbleBox;

  const ChatBubbleFrame({
    super.key,
    required this.isMine,
    this.runStart = true,
    required this.child,
    this.chrome = true,
    this.padding = ChatBubbleGeometry.contentPadding,
    this.width,
    this.background,
    this.border,
  });

  final bool isMine;
  final bool runStart;
  final Widget child;
  final bool chrome;
  final EdgeInsets? padding;

  /// A fixed width (A2 attachments); null = shrink-wrap up to A1.
  final double? width;
  final Color? background;

  /// Null = the default: a 1 dp line on their bubble in light mode (D-5).
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final bubbleRadius = ChatBubbleGeometry.radius(
      isMine: isMine,
      runStart: runStart,
    );
    Widget content = child;
    if (padding != null) content = Padding(padding: padding!, child: content);
    if (width != null) content = SizedBox(width: width, child: content);
    if (chrome) {
      content = ClipRRect(borderRadius: bubbleRadius, child: content);
    }
    final light = Theme.of(context).brightness == Brightness.light;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: ChatBubbleGeometry.margin(isMine: isMine),
        // Motion C1: marks the bubble's own box for the send flight.
        child: MetaData(
          metaData: ChatBubbleFrame.box,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: math.max(
                ChatBubbleGeometry.maxWidth(context),
                width ?? 0,
              ),
            ),
            foregroundDecoration: chrome
                ? BoxDecoration(
                    border:
                        border ??
                        (!isMine && light ? Border.all(color: t.line) : null),
                    borderRadius: bubbleRadius,
                  )
                : null,
            decoration: chrome
                ? BoxDecoration(
                    color: background ?? (isMine ? t.bubbleMine : t.surface),
                    borderRadius: bubbleRadius,
                  )
                : null,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// B2/B4: the quiet line under a run's last bubble: time, ticks on own
/// runs, a star when starred. 11/14 inkSoft; a failed send shows its ⚠ tick.
class ChatBubbleTimestamp extends StatelessWidget {
  const ChatBubbleTimestamp({
    super.key,
    required this.isMine,
    this.createdAt,
    this.status,
    this.starred = false,
  });

  final bool isMine;
  final DateTime? createdAt;
  final String? status;
  final bool starred;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (starred) ...[
            Icon(Icons.star_rounded, size: 12, color: t.inkSoft),
            const SizedBox(width: 2),
          ],
          if (createdAt != null)
            Text(
              DateFormat('HH:mm').format(createdAt!.toLocal()),
              style: TextStyle(
                fontSize: ChatBubbleGeometry.timestampFontSize,
                height: ChatBubbleGeometry.timestampLineHeight,
                color: t.inkSoft,
              ),
            ),
          if (isMine && status != null) ...[
            if (createdAt != null) const SizedBox(width: 3),
            DeliveryTick(status: status!, size: 13),
          ],
        ],
      ),
    );
  }
}

/// The dark pill media overlays put their small white labels on (the time
/// pill, an album's count pill).
class MediaOverlayPill extends StatelessWidget {
  const MediaOverlayPill({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(10),
    ),
    child: IconTheme.merge(
      data: const IconThemeData(color: Colors.white),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: child,
      ),
    ),
  );
}

/// Compact expiry affordance for media overlays.
///
/// The widget is positioned so media stacks can add it directly as a child,
/// matching the chat spec's top-right placement.
class ExpiryBadge extends StatelessWidget {
  const ExpiryBadge({super.key, required this.label, this.bottomLeft = false});

  final String label;

  /// An album keeps top-right for its count pill (12.5 D2).
  final bool bottomLeft;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Positioned(
      top: bottomLeft ? null : 6,
      right: bottomLeft ? null : 6,
      left: bottomLeft ? 8 : null,
      bottom: bottomLeft ? 8 : null,
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
  const MediaDisc({
    super.key,
    required this.icon,
    this.background,
    this.foreground,
    this.iconSize = 26,
  });

  final IconData icon;
  final Color? background;
  final Color? foreground;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: background ?? Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: foreground ?? Colors.white, size: iconSize),
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
    this.inline = false,
    this.ink,
  });

  final IconData glyph;
  final bool decorate;

  /// A left-aligned row, for full-width voice and document bubbles.
  final bool inline;

  /// Ink override; null = inkSoft (ink on the tint, chat calm E7).
  final Color? ink;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final dimmedInk = ink ?? t.inkSoft.withValues(alpha: 0.5);
    if (inline) {
      return SizedBox(
        height: ChatBubbleGeometry.leadingSize,
        child: Row(
          children: [
            Icon(glyph, color: ink ?? t.inkSoft, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                kMediaExpired,
                style: TextStyle(
                  color: ink ?? t.inkSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(glyph, color: dimmedInk, size: 20),
        const SizedBox(height: 5),
        Text(
          kMediaExpired,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: dimmedInk,
            fontSize: 12,
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
