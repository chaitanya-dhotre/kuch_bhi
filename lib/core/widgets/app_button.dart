import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

enum AppButtonVariant { primary, secondary, text }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = AppButtonVariant.primary,
    this.busy = false,
    this.expanded = false,
  });
  final VoidCallback? onPressed;
  final Widget child;
  final AppButtonVariant variant;
  final bool busy;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final enabled = onPressed != null && !busy;
    final content = busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2))
        : child;
    final base = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: enabled ? null : t.inkFaint, // disabled: inkFaint on surface2
    );

    final Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: t.accent,
            foregroundColor: t.onAccent,
            disabledBackgroundColor: t.surface2,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(WarmPopTokens.radiusMd)),
            textStyle: base,
          ),
          child: content,
        ),
      AppButtonVariant.secondary => OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            backgroundColor: t.surface,
            foregroundColor: t.ink,
            disabledForegroundColor: t.inkFaint,
            disabledBackgroundColor: t.surface2,
            minimumSize: const Size(0, 48),
            side:
                BorderSide(color: enabled ? t.line : t.surface2, width: 1.5),
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(WarmPopTokens.radiusMd)),
            textStyle: base,
          ),
          child: content,
        ),
      AppButtonVariant.text => TextButton(
          onPressed: enabled ? onPressed : null,
          style: TextButton.styleFrom(
            foregroundColor: t.ink,
            disabledForegroundColor: t.inkFaint,
            minimumSize: const Size(0, 40),
            textStyle: base,
          ),
          child: content,
        ),
    };
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
