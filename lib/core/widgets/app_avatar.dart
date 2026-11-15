import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

/// First character of the trimmed [name], upper-cased, or [fallback].
String initialsOf(String name, {String fallback = '?'}) {
  final n = name.trim();
  return n.isEmpty
      ? fallback
      : String.fromCharCode(n.runes.first).toUpperCase();
}

/// Two letters for a name of two words or more ("New Group" → NG), else
/// one. The Home row and the chat's app bar both use it.
String nameInitials(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  if (words.first.isEmpty) return '?';
  final first = String.fromCharCode(words.first.runes.first);
  if (words.length < 2) return first.toUpperCase();
  return (first + String.fromCharCode(words[1].runes.first)).toUpperCase();
}

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

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.url,
    required this.initials,
    this.radius = 20,
    this.accentSoft = false,
    this.image,
  });
  final String? url;

  /// Local preview (e.g. a picked file); wins over [url].
  final ImageProvider? image;
  final String initials;
  final double radius;
  final bool accentSoft;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final photo =
        image ?? (url != null ? CachedNetworkImageProvider(url!) : null);
    // Initials always sit under the photo, so a slow or failed load (404,
    // offline) shows initials instead of an empty disc.
    return CircleAvatar(
      radius: radius,
      backgroundColor: accentSoft ? t.accentSoft : t.surface2,
      foregroundImage: photo,
      onForegroundImageError: photo == null ? null : (_, __) {},
      child: Text(
        initials,
        style: TextStyle(
          color: accentSoft ? _readableAccentForeground(t) : t.inkSoft,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.75,
        ),
      ),
    );
  }

  static Color _readableAccentForeground(ColorTokens tokens) {
    final candidates = <Color>[
      tokens.ink,
      tokens.inkSoft,
      tokens.onAccent,
      tokens.surface,
      tokens.bg,
    ];
    var best = candidates.first;
    var bestRatio = _contrastRatio(best, tokens.accentSoft);
    for (final candidate in candidates.skip(1)) {
      final ratio = _contrastRatio(candidate, tokens.accentSoft);
      if (ratio > bestRatio) {
        best = candidate;
        bestRatio = ratio;
      }
    }
    return best;
  }

  static double _contrastRatio(Color foreground, Color background) {
    final foregroundLuminance = foreground.computeLuminance();
    final backgroundLuminance = background.computeLuminance();
    final lighter = foregroundLuminance > backgroundLuminance
        ? foregroundLuminance
        : backgroundLuminance;
    final darker = foregroundLuminance > backgroundLuminance
        ? backgroundLuminance
        : foregroundLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }
}
