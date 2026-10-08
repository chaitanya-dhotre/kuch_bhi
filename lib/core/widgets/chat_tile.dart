import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'app_avatar.dart';
import 'app_badge.dart';

/// Home list row (spec component set: ChatTile). Approved mockup row:
/// surface card, 40px avatar, w700 name, ellipsis preview, faint time,
/// Marigold unread pill. Group rows overlay a small group glyph.
class ChatTile extends StatelessWidget {
  const ChatTile(
      {super.key,
      required this.title,
      required this.subtitle,
      this.subtitleWidget,
      this.avatarUrl,
      this.time,
      this.unreadCount = 0,
      this.subtitleColor,
      this.isGroup = false,
      this.onTap,
      this.onLongPress});
  final String title;
  final String subtitle;

  /// T9: when provided, renders INSTEAD of the [subtitle] string — the
  /// conversation list feeds it `ConversationPreviewText` (provider-driven
  /// placeholder → fill). String callers (friends tiles, tests) unchanged.
  final Widget? subtitleWidget;
  final String? avatarUrl;
  final String? time;
  final int unreadCount;
  final Color? subtitleColor;
  final bool isGroup;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                AppAvatar(
                    url: avatarUrl,
                    initials: title.isEmpty ? '?' : title[0].toUpperCase(),
                    radius: 20),
                if (isGroup)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration:
                          BoxDecoration(color: t.bg, shape: BoxShape.circle),
                      child: Icon(Icons.group, size: 12, color: t.accent),
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                if (time != null)
                  Text(time!,
                      style: TextStyle(fontSize: 11, color: t.inkFaint)),
              ],
            ),
            subtitle: Row(
              children: [
                Expanded(
                  child: subtitleWidget ??
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: subtitleColor ?? t.inkSoft)),
                ),
                if (unreadCount > 0) AppBadge(count: unreadCount),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
