import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../chat/message_offline_policy.dart';

/// A4: the auth screens' side gutter.
const kAuthGutter = 24.0;

/// A3 / I1: h1 24/30 w700 ink, announced as a heading.
class AuthTitle extends StatelessWidget {
  const AuthTitle(this.text, {super.key, this.align = TextAlign.center});
  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(
            fontSize: 24,
            height: 30 / 24,
            fontWeight: FontWeight.w700,
            color: context.t.ink,
          ),
        ),
      );
}

/// A3: body 15/22 inkSoft.
TextStyle authBodyStyle(BuildContext context) =>
    TextStyle(fontSize: 15, height: 22 / 15, color: context.t.inkSoft);

/// G5: a network action offline gets exactly one 38% dim (the caller also
/// disables it).
class OfflineDim extends StatelessWidget {
  const OfflineDim({super.key, required this.online, required this.child});
  final bool online;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: online ? 1 : .38, child: child);
}

/// G5: the screen's single offline hint, centred under the primary button.
class OfflineActionHint extends StatelessWidget {
  const OfflineActionHint({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          kOfflineActionHint,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 13, height: 18 / 13, color: context.t.inkSoft),
        ),
      );
}

/// C2 / D5: prompt + R3 text link, wrapping at large text sizes.
class AuthFooter extends StatelessWidget {
  const AuthFooter({
    super.key,
    required this.prompt,
    required this.action,
    required this.onPressed,
  });
  final String prompt;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(prompt, style: authBodyStyle(context)),
          AppButton(
            variant: AppButtonVariant.text,
            onPressed: onPressed,
            child: Text(action),
          ),
        ],
      );
}

/// C5: the show-password toggle.
class PasswordToggle extends StatelessWidget {
  const PasswordToggle(
      {super.key, required this.obscured, required this.onPressed});
  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: obscured ? 'Show password' : 'Hide password',
        icon: Icon(
          obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: context.t.inkSoft,
        ),
        onPressed: onPressed,
      );
}
