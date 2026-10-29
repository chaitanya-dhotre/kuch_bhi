import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Registry R15: the app mark — accent tile, radiusXl, lock glyph at half
/// size in onAccent. About and Splash.
class AppLogoTile extends StatelessWidget {
  const AppLogoTile({super.key, this.size = 88});
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: t.accent,
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusXl),
      ),
      child: Icon(Icons.lock_outline, color: t.onAccent, size: size / 2),
    );
  }
}
