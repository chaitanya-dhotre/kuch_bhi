import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Registry R15: the app mark — the launcher icon's picture (mascot.md K6,
/// option A: the Front capybara on bath teal), radiusXl. Splash, lock steps,
/// privacy cover, app-lock settings. The PNG is written by
/// `docs/design/mascot/phase5/icon.py --ship`.
class AppLogoTile extends StatelessWidget {
  const AppLogoTile({super.key, this.size = 88});
  final double size;

  /// `ic_launcher_background` in android/app/src/main/res/values/colors.xml.
  static const background = Color(0xFFA9DCD6);
  static const asset = 'assets/icons/app_logo.png';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusXl),
      ),
      // Same teal under the picture, so a frame before the PNG decodes reads as the icon plate.
      child: Image.asset(asset, width: size, height: size, excludeFromSemantics: true),
    );
  }
}
