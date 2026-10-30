import 'package:flutter/material.dart';

import '../../../core/widgets/app_sheet.dart';

/// Registry C12: the ONE reaction emoji list (grep-gated to this file).
const kReactionEmojis = [
  '👍',
  '👎',
  '❤️',
  '🔥',
  '😂',
  '😮',
  '😢',
  '🙏',
  '🎉',
  '💯',
  '😍',
  '🤔',
  '😡',
  '👏',
  '🤣',
  '😊',
  '💪',
  '🫡',
  '✅',
  '❌',
  '⭐',
  '💎',
  '🚀',
  '😴',
  '🥹',
  '🫶',
  '😎',
  '🤯',
  '🥳',
  '👀',
  '💀',
  '🫠',
];

/// Decision 11: the message menu's quick row; the full list stays here.
const kQuickReactions = ['👍', '❤️', '😂', '😮', '😢'];

/// Registry C12: the ONE picker. Returns the picked emoji, or `null` when
/// dismissed. Callers keep their own write.
Future<String?> showReactionPicker(BuildContext context) {
  return showAppSheet<String>(
    context: context,
    builder: (sheetContext) => AppSheetChrome(
      title: 'Add a reaction',
      body: GridView.builder(
        key: const Key('reaction-picker'),
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        // Max-extent cells: 6 across at 360dp, never under 48.
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 60,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: kReactionEmojis.length,
        itemBuilder: (_, i) {
          final emoji = kReactionEmojis[i];
          return Semantics(
            button: true,
            label: emoji,
            // excludeSemantics drops the child's tap; give it back here.
            onTap: () => Navigator.of(sheetContext).pop(emoji),
            excludeSemantics: true,
            child: InkResponse(
              key: ValueKey('reaction-picker-$emoji'),
              onTap: () => Navigator.of(sheetContext).pop(emoji),
              child: Center(
                // The glyph sits in a fixed cell; scaling it only clips it.
                child: Text(
                  emoji,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(fontSize: 26),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
