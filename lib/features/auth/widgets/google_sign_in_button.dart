import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/widgets/app_button.dart';

/// R3 secondary with the official 4-colour Google G.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, this.onPressed, this.busy = false});
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      variant: AppButtonVariant.secondary,
      expanded: true,
      busy: busy,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset('assets/icons/google_g.svg', width: 20, height: 20),
          const SizedBox(width: 10),
          const Flexible(child: Text('Continue with Google')),
        ],
      ),
    );
  }
}
