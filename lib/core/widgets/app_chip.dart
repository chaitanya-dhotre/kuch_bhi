import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';
import 'press_scale.dart';

class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.onTap,
    required this.child,
    this.selected = false,
  });
  final VoidCallback onTap;
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return PressScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? t.accentSoft : t.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? t.accent : t.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.ink,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
