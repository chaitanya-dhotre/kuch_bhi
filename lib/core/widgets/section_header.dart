import 'package:flutter/material.dart';
import '../../core/theme/tokens.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.count});
  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Wraps instead of overflowing at large text sizes (I2).
            Flexible(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.27,
                  letterSpacing: .1,
                  color: t.inkFaint,
                ),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.27,
                    color: t.inkSoft,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
