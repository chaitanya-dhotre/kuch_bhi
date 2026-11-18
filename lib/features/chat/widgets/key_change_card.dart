import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';

/// Registry C21 (key-change-warning spec D5): takes the DM composer's place
/// while the contact's new security code is not accepted. No solid primary:
/// accepting must not look like the default.
class KeyChangeCard extends StatelessWidget {
  const KeyChangeCard({
    super.key,
    required this.name,
    required this.onCompare,
    required this.onAccept,
  });

  final String name;
  final VoidCallback onCompare;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final compare = AppButton(
      key: const ValueKey('key-change-compare'),
      variant: AppButtonVariant.tonal,
      expanded: true,
      onPressed: onCompare,
      child: const Text('Compare codes'),
    );
    final accept = AppButton(
      key: const ValueKey('key-change-accept'),
      variant: AppButtonVariant.secondary,
      expanded: true,
      onPressed: onAccept,
      child: const Text('Accept'),
    );
    // D9: at large text the buttons stack instead of squeezing.
    final big = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return SafeArea(
      top: false,
      child: Container(
        key: const ValueKey('key-change-card'),
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
          border: Border.all(color: t.line),
        ),
        // D9: at 200 % on a small phone the copy is taller than half the
        // screen; it scrolls inside the card so the chat keeps its room.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.5,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.shield_outlined,
                      size: 20,
                      color: t.accentText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            "$name's security code changed",
                            style: TextStyle(
                              fontSize: 16,
                              height: 22 / 16,
                              fontWeight: FontWeight.w600,
                              color: t.ink,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'This happens when $name reinstalls kuch bhi or '
                          'starts fresh. It can also mean someone else is '
                          'trying to read this chat. Compare codes before you '
                          'send.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 18 / 13,
                            color: t.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (big) ...[
                compare,
                const SizedBox(height: 8),
                accept,
              ] else
                Row(
                  children: [
                    Expanded(child: compare),
                    const SizedBox(width: 8),
                    Expanded(child: accept),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
