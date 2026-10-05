import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import '../../features/mascot/capybara.dart';

/// Empty/error state with the mascot slot (spec: slots, not decisions).
/// Never used inside message bubbles or behind readable text.
class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.title,
      this.subtitle,
      this.action,
      this.withMascot = true,
      this.mood = CapyMood.neutral,
      this.mascot});
  final String title;
  final String? subtitle;
  final Widget? action;
  final bool withMascot;
  final CapyMood mood;
  final Widget? mascot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = context.t;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mascot != null)
              mascot!
            else if (withMascot)
              Capybara(mood: mood, size: const Size(180, 152)),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: t.inkSoft)),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
