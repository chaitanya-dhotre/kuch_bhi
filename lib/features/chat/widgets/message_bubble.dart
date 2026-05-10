import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  final Message message;
  final bool    isMine;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left:   isMine ? 64 : 12,
          right:  isMine ? 12 : 64,
          top: 2, bottom: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMine
              ? AppColors.sentBubble
              : isDark
                  ? AppColors.receivedBubbleDark
                  : AppColors.receivedBubbleLight,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.isDeletedForEveryone)
              Text(
                '🚫 Message deleted',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: isMine
                      ? Colors.white70
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              )
            else
              Text(
                message.decryptedBody ?? '🔒 Encrypted',
                style: TextStyle(
                  color: isMine
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 15,
                ),
              ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(message.createdAt.toLocal()),
                  style: TextStyle(
                    fontSize: 11,
                    color: isMine
                        ? Colors.white60
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4),
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  _TickIndicator(status: message.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TickIndicator extends StatelessWidget {
  const _TickIndicator({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    if (status == 'pending') {
      return const SizedBox(
        width: 12, height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: Colors.white54,
        ),
      );
    }

    if (status == 'failed') {
      return const Icon(Icons.error_outline, size: 14, color: Colors.red);
    }

    // Ticks always appear on the sent (indigo) bubble.
    // Use WHITE for read so it's visible against the indigo background.
    // AppColors.tickRead (also indigo) would be invisible here.
    final Color color;
    switch (status) {
      case 'read':
        color = Colors.white;        // White tick = read, visible on indigo
      case 'delivered':
        color = Colors.white54;      // Dimmer white = delivered
      default:
        color = Colors.white38;      // Dimmest = sent only
    }

    if (status == 'sent') {
      return Icon(Icons.check, size: 14, color: color);
    }

    // Delivered or read — overlapping double check.
    return SizedBox(
      width: 18,
      child: Stack(
        children: [
          Icon(Icons.check, size: 14, color: color),
          Positioned(
            left: 5,
            child: Icon(Icons.check, size: 14, color: color),
          ),
        ],
      ),
    );
  }
}
