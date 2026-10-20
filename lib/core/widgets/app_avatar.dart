import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    this.url,
    required this.initials,
    this.radius = 20,
    this.accentSoft = false,
  });
  final String? url;
  final String initials;
  final double radius;
  final bool accentSoft;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return CircleAvatar(
      radius: radius,
      backgroundColor: accentSoft ? t.accentSoft : t.surface2,
      backgroundImage: url != null ? CachedNetworkImageProvider(url!) : null,
      child: url != null
          ? null
          : Text(
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
