import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

/// [nameInitials] of the trimmed [name], or [fallback] when it is empty.
/// One rule everywhere, so a person reads "BM" on Home and in Requests alike.
String initialsOf(String name, {String fallback = '?'}) {
  final n = name.trim();
  return n.isEmpty ? fallback : nameInitials(n);
}

/// Two letters for a name of two words or more ("New Group" → NG), else
/// one. The Home row and the chat's app bar both use it.
String nameInitials(String name) {
  final all = name.trim().split(RegExp(r'\s+'));
  if (all.first.isEmpty) return '?';
  // Only words that start with a letter count, so "Raj 🦫" stays "R", not "R🦫".
  final words = all.where((w) => _letter.hasMatch(w)).toList();
  if (words.isEmpty) return String.fromCharCode(all.first.runes.first);
  final first = String.fromCharCode(words.first.runes.first);
  if (words.length < 2) return first.toUpperCase();
  return (first + String.fromCharCode(words[1].runes.first)).toUpperCase();
}

final _letter = RegExp(r'^\p{L}', unicode: true);

/// Motion B3: one Hero tag per chat, shared by its Home row and app bar.
String chatAvatarHeroTag(String conversationId) =>
    'chat-avatar-$conversationId';
String chatNameHeroTag(String conversationId) => 'chat-name-$conversationId';
const offlineBannerHeroTag = 'offline-banner';

/// Motion B3: [child] flies between Home and the chat on page changes. The
/// flight cross-fades the two looks (Home's avatar with its badge or online
/// dot, the app bar's), each scaled down to the flying box. Off under
/// reduced motion. [crossFade] false = the destination's look only (a Rive
/// mascot inside must not run twice).
class ChatHero extends StatelessWidget {
  const ChatHero({
    super.key,
    required this.tag,
    required this.child,
    this.crossFade = true,
  });

  final Object tag;
  final Widget child;
  final bool crossFade;

  static Widget _shuttle(
    BuildContext context,
    Animation<double> a,
    HeroFlightDirection direction,
    BuildContext from,
    BuildContext to,
  ) {
    Widget look(BuildContext c) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: (c.widget as Hero).child,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(opacity: ReverseAnimation(a), child: look(from)),
        FadeTransition(opacity: a, child: look(to)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return Hero(
      tag: tag,
      curve: WarmPopTokens.curveMove,
      flightShuttleBuilder: crossFade ? _shuttle : null,
      // The flight runs in the root overlay: without a Material its text
      // falls back to the debug style (yellow underline).
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// Registry R1 (calm-rest A2): a photo, or initials in `inkSoft` 600 on a
/// `surface2` disc with a 1 dp `line` ring. Photos keep no ring.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.url,
    required this.initials,
    this.radius = 20,
    this.image,
  });
  final String? url;

  /// Local preview (e.g. a picked file); wins over [url].
  final ImageProvider? image;
  final String initials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final photo =
        image ?? (url != null ? CachedNetworkImageProvider(url!) : null);
    // Initials always sit under the photo, so a slow or failed load (404,
    // offline) shows initials instead of an empty disc.
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: t.surface2,
      foregroundImage: photo,
      onForegroundImageError: photo == null ? null : (_, __) {},
      child: Text(
        initials,
        style: TextStyle(
          color: t.inkSoft,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.75,
        ),
      ),
    );
    if (photo != null) return avatar;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: t.line, width: 1),
      ),
      child: avatar,
    );
  }
}
