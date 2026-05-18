import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/message.dart';

/// Compact quote shown inside a message bubble (received) or above the
/// input bar (composing). Pass [compact] = true for the input bar.
class ReplyQuote extends StatelessWidget {
  const ReplyQuote({
    super.key,
    required this.preview,
    required this.senderName,
    this.isMine      = false,
    this.compact     = false,
    this.messageType = 'text',
    this.onCancel,
  });

  final String         preview;
  final String         senderName;
  final bool           isMine;
  final bool           compact;
  final String         messageType;
  final VoidCallback?  onCancel;

  factory ReplyQuote.fromMessage(Message msg, String senderName, {
    bool isMine = false, bool compact = false, VoidCallback? onCancel,
  }) {
    final body = msg.decryptedBody ?? '🔒 Encrypted';
    // Media previews should show a type label, not the (possibly empty) body
    final preview = switch (msg.type) {
      'image' => 'Photo',
      'voice' => body.startsWith('🎤') ? body : '🎤 Voice message',
      _       => body.length > 80 ? '${body.substring(0, 80)}…' : body,
    };
    return ReplyQuote(
      preview:     preview,
      senderName:  senderName,
      isMine:      isMine,
      compact:     compact,
      messageType: msg.type,
      onCancel:    onCancel,
    );
  }

  IconData? get _typeIcon => switch (messageType) {
    'image' => Icons.image_outlined,
    'voice' => Icons.mic_none,
    _       => null,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── Background ──────────────────────────────────────────────
    // Sent bubble reply    : solid dark-purple tint — always visible on any
    //                        scaffold because it has real opacity.
    // Received bubble      : light lavender (light mode) / dark slate (dark mode)
    // Input bar (compact)  : adaptive surface container
    final Color bg;
    if (compact) {
      bg = Theme.of(context).colorScheme.surfaceContainerHighest;
    } else if (isMine) {
      // Use a solid colour derived from the sent-bubble colour so it's always
      // visible regardless of the scaffold bg behind it.
      bg = isDark
          ? const Color(0xFF4A4F9A) // lighter purple for dark mode
          : const Color(0xFF4A55C0); // darker purple for light mode
    } else {
      bg = isDark
          ? const Color(0xFF2A2D4A) // dark-mode received reply bg
          : AppColors.primaryLight;  // light-mode: light lavender
    }

    // ── Text colours ────────────────────────────────────────────
    // Sent bubble  → always white (always high contrast on purple bg).
    // Received + compact → respect actual bg brightness.
    final Color nameColor;
    final Color previewColor;
    final Color iconColor;
    if (isMine && !compact) {
      nameColor    = Colors.white;
      previewColor = Colors.white.withValues(alpha: 0.85);
      iconColor    = Colors.white.withValues(alpha: 0.75);
    } else {
      // Light bg (received light / compact light) → dark text.
      // Dark bg (received dark / compact dark)   → light text.
      final onBg = isDark
          ? const Color(0xFFF1F1F5) // near-white
          : const Color(0xFF1A1A2E); // near-black
      nameColor    = AppColors.primary;
      previewColor = onBg.withValues(alpha: 0.80);
      iconColor    = onBg.withValues(alpha: 0.60);
    }

    final icon = _typeIcon;

    return Container(
      margin:     EdgeInsets.only(bottom: compact ? 0 : 6),
      padding:    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      constraints: compact
          ? null
          : const BoxConstraints(maxWidth: 280),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize:       MainAxisSize.min,
              children: [
                Text(
                  senderName,
                  style: TextStyle(
                    fontSize:   12,
                    fontWeight: FontWeight.w600,
                    color:      nameColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines:  2,
                  overflow:  TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: previewColor),
                ),
              ],
            ),
          ),
          if (onCancel != null)
            IconButton(
              icon:        Icon(Icons.close, size: 18, color: previewColor),
              onPressed:   onCancel,
              padding:     EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
