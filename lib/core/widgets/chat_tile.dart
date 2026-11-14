import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'app_avatar.dart';
import 'app_badge.dart';

/// Home list row (spec component set: ChatTile).
///
/// The row is intentionally shared by conversation and friend faces. Home
/// supplies the optional presence/pin state while preview derivation remains
/// in [ConversationPreviewText].
class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.subtitleWidget,
    this.avatarUrl,
    this.time,
    this.unreadCount = 0,
    this.subtitleColor,
    this.isGroup = false,
    this.isPinned = false,
    this.isOnline,
    this.semanticSubtitle,
    this.onTap,
    this.onLongPress,
  });
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
  final bool isPinned;
  final bool? isOnline;

  /// Optional stable text for the merged accessibility label. The visible
  /// subtitle can be a decrypting/provider-backed widget, so callers may pass
  /// the law-prescribed fallback while that widget resolves.
  final String? semanticSubtitle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final unread = unreadCount > 0;
    final semanticParts = <String>[title];
    final semanticText = semanticSubtitle ?? subtitle;
    if (semanticText.isNotEmpty) semanticParts.add(semanticText);
    if (isOnline == true && semanticText != 'Online') {
      semanticParts.add('Online');
    }
    if (time != null && time!.isNotEmpty) semanticParts.add(time!);
    if (unread) semanticParts.add('$unreadCount unread');
    if (isPinned) semanticParts.add('pinned');

    final actionable = onTap != null || onLongPress != null;
    return Semantics(
      container: true,
      button: actionable,
      label: semanticParts.join(', '),
      onTap: onTap,
      onLongPress: onLongPress,
      child: ExcludeSemantics(
        child: Material(
          color: t.surface,
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 0,
                ),
                minVerticalPadding: 0,
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppAvatar(
                      url: avatarUrl,
                      initials: _initials(title),
                      radius: 20,
                    ),
                    if (isGroup)
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: Container(
                          width: 17,
                          height: 17,
                          decoration: BoxDecoration(
                            color: t.bg,
                            shape: BoxShape.circle,
                            border: Border.all(color: t.surface, width: 2),
                          ),
                          child: Icon(Icons.group, size: 9, color: t.inkSoft),
                        ),
                      )
                    else if (isOnline == true)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: t.success,
                            shape: BoxShape.circle,
                            border: Border.all(color: t.surface, width: 2.5),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Row(
                  children: [
                    if (isPinned) ...[
                      Icon(Icons.push_pin, size: 12, color: t.inkFaint),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.ink,
                        ),
                      ),
                    ),
                    if (time != null)
                      Text(
                        time!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w400,
                          // Chat calm D3: grey; marigold text only when unread.
                          color: unread ? t.accentText : t.inkSoft,
                        ),
                      ),
                  ],
                ),
                subtitle: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child:
                          subtitleWidget ??
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: unread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color:
                                  subtitleColor ?? (unread ? t.ink : t.inkSoft),
                            ),
                          ),
                    ),
                    if (unreadCount > 0) AppBadge(count: unreadCount),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length > 1) {
      return '${words.first[0]}${words[1][0]}'.toUpperCase();
    }
    return words.first[0].toUpperCase();
  }
}
