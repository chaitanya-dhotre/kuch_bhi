import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/emoji_utils.dart';
import '../../../domain/entities/message.dart';
import 'link_preview_card.dart';
import 'document_message_bubble.dart';
import 'image_message_bubble.dart';
import 'video_message_bubble.dart';
import 'voice_message_bubble.dart';
import 'reaction_bar.dart';
import 'reply_quote.dart';
import 'swipe_to_reply.dart';
import 'message_context_menu.dart';

// 8 deterministic sender name colors per Task 6
const List<Color> _kSenderColors = [
  Colors.red,
  Colors.pink,
  Colors.purple,
  Colors.indigo,
  Colors.teal,
  Colors.green,
  Colors.orange,
  Colors.brown,
];

Color _colorForSender(String senderId) =>
    _kSenderColors[senderId.hashCode.abs() % _kSenderColors.length];

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.senderName = 'Unknown',
    this.isGroup    = false,
    this.onReply,
    this.onReplyTap,
  });

  final Message      message;
  final bool         isMine;
  final String       senderName;
  final bool         isGroup;
  final VoidCallback? onReply;
  final VoidCallback? onReplyTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body      = message.decryptedBody ?? '';
    final emojiOnly = isEmojiOnly(body) && message.type == 'text';
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final url       = extractFirstUrl(body);

    // ── System / info bubbles — no reply, no long-press, no sender meta ─
    if (message.type == 'system') {
      return _SystemMessageBubble(body: body);
    }

    final bubble = GestureDetector(
      onLongPress: () => showMessageMenu(
        context:    context,
        ref:        ref,
        message:    message,
        isMine:     isMine,
        senderName: senderName,
      ),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // ── Group sender name ────────────────────────────────
          if (isGroup && !isMine)
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 1, top: 4),
              child: Text(
                senderName,
                style: TextStyle(
                  fontSize:   11,
                  fontWeight: FontWeight.w600,
                  color:      _colorForSender(message.senderId),
                ),
              ),
            ),

          // ── Reply quote ──────────────────────────────────────
          if (message.replyPreview != null)
            GestureDetector(
              onTap: onReplyTap,
              child: Padding(
                padding: EdgeInsets.only(
                  left:  isMine ? 64 : 12,
                  right: isMine ? 12 : 64,
                  top:   2,
                ),
                child: ReplyQuote(
                  preview:    message.replyPreview!,
                  // The quote shows WHO was replied to, not who sent THIS message.
                  // If I sent this message, I replied to the other user → show their name.
                  // If other user sent this message, they replied to me → show 'You'.
                  senderName: isMine ? senderName : 'You',
                  isMine:     isMine,
                  // Let the quote resolve the original message type from
                  // Drift via its server id; the emoji-prefix heuristic is
                  // only the fallback when the row isn't found locally.
                  replyToId:      message.replyToId,
                  conversationId: message.conversationId,
                  messageType: message.replyPreview!.startsWith('🎤')
                      ? 'voice'
                      : message.replyPreview!.startsWith('📷')
                          ? 'image'
                          : 'text',
                ),
              ),
            ),

          // ── Bubble ──────────────────────────────────────────
          if (message.type == 'voice' && message.serverId != null)
            Align(
              alignment:
                  isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  left:   isMine ? 64 : 12,
                  right:  isMine ? 12 : 64,
                  top:    2,
                  bottom: 2,
                ),
                child: VoiceMessageBubble(
                  conversationId: message.conversationId,
                  serverId:     message.serverId!,
                  isMine:       isMine,
                  durationText: message.decryptedBody,
                  status:       message.status,
                  createdAt:    message.createdAt,
                ),
              ),
            )
          else if (message.type == 'image' && message.serverId != null)
            Align(
              alignment:
                  isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  left:   isMine ? 64 : 12,
                  right:  isMine ? 12 : 64,
                  top:    2,
                  bottom: 2,
                ),
                child: ImageMessageBubble(
                  conversationId: message.conversationId,
                  serverId:  message.serverId!,
                  isMine:    isMine,
                  isDark:    isDark,
                  status:    message.status,
                  createdAt: message.createdAt,
                ),
              ),
            )
          else if (message.type == 'video' && message.serverId != null)
            Align(
              alignment:
                  isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  left:   isMine ? 64 : 12,
                  right:  isMine ? 12 : 64,
                  top:    2,
                  bottom: 2,
                ),
                child: VideoMessageBubble(
                  conversationId: message.conversationId,
                  serverId:  message.serverId!,
                  isMine:    isMine,
                  isDark:    isDark,
                  status:    message.status,
                  createdAt: message.createdAt,
                ),
              ),
            )
          else if (message.type == 'document' && message.serverId != null)
            Align(
              alignment:
                  isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: DocumentMessageBubble(
                conversationId: message.conversationId,
                serverId:  message.serverId!,
                isMine:    isMine,
                isDark:    isDark,
                status:    message.status,
                createdAt: message.createdAt,
              ),
            )
          else if (message.serverId == null &&
              const {'image', 'video', 'voice', 'document'}
                  .contains(message.type))
            // Optimistic upload in flight (serverId not stamped yet) —
            // spinner placeholder, never ciphertext or an empty bubble.
            Align(
              alignment:
                  isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  left:   isMine ? 64 : 12,
                  right:  isMine ? 12 : 64,
                  top:    2,
                  bottom: 2,
                ),
                child: Container(
                  width:  140,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                ),
              ),
            )
          else if (emojiOnly)
            _EmojiOnlyBubble(message: message, isMine: isMine)
          else
            _TextBubble(
              message: message,
              isMine:  isMine,
              isDark:  isDark,
              url:     url,
            ),

          // ── Reactions ────────────────────────────────────────
          if (message.serverId != null)
            ReactionBar(messageServerId: message.serverId!, isMine: isMine),
        ],
      ),
    );

    return SwipeToReply(
      isMine:  isMine,
      onReply: onReply ?? () {},
      child:   bubble,
    );
  }
}

// ── Emoji-only (no bubble, large font) ────────────────────────────────────

class _EmojiOnlyBubble extends StatelessWidget {
  const _EmojiOnlyBubble({required this.message, required this.isMine});
  final Message message;
  final bool    isMine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left:   isMine ? 64 : 12,
          right:  isMine ? 12 : 64,
          top:    2,
          bottom: 2,
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.decryptedBody ?? '',
              style: const TextStyle(fontSize: 40),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(message.createdAt.toLocal()),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
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

// ── Standard text bubble ──────────────────────────────────────────────────

class _TextBubble extends StatelessWidget {
  const _TextBubble({
    required this.message,
    required this.isMine,
    required this.isDark,
    this.url,
  });

  final Message message;
  final bool    isMine;
  final bool    isDark;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left:   isMine ? 64 : 12,
          right:  isMine ? 12 : 64,
          top:    2,
          bottom: 2,
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
              color:      Colors.black.withValues(alpha: 0.06),
              blurRadius: 4,
              offset:     const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize:       MainAxisSize.min,
          children: [
            if (message.isDeletedForEveryone)
              Text(
                '🚫 Message deleted',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize:  14,
                  color: isMine
                      ? Colors.white70
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                ),
              )
            else
              Text(
                message.decryptedBody ?? '🔒 Encrypted',
                style: TextStyle(
                  color:    isMine
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 15,
                ),
              ),

            // Link preview
            if (url != null && !message.isDeletedForEveryone)
              LinkPreviewCard(url: url!),

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

// ── Tick indicator ────────────────────────────────────────────────────────

class _TickIndicator extends StatelessWidget {
  const _TickIndicator({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    if (status == 'pending') {
      return const SizedBox(
        width: 12, height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white54),
      );
    }
    if (status == 'failed') {
      return const Icon(Icons.error_outline, size: 14, color: Colors.redAccent);
    }

    final Color color = switch (status) {
      'read'      => Colors.white,      // white = read (visible on indigo)
      'delivered' => Colors.white54,
      _           => Colors.white38,    // sent
    };

    if (status == 'sent') return Icon(Icons.check, size: 14, color: color);

    return SizedBox(
      width: 18,
      child: Stack(
        children: [
          Icon(Icons.check, size: 14, color: color),
          Positioned(left: 5, child: Icon(Icons.check, size: 14, color: color)),
        ],
      ),
    );
  }
}

// ── System / info bubble ───────────────────────────────────────────────────
//
// WhastApp-style narrative info row rendered for 'system' messages (group
// created, member added/removed, role change, etc). Always centered,
// always grey, no sender colour metadata, no bubbles, no long-press.

class _SystemMessageBubble extends StatelessWidget {
  const _SystemMessageBubble({required this.body});
  final String body;

  @override
  Widget build(BuildContext context) {
    final dimmed = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color:  Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize:    12,
              fontStyle:   FontStyle.italic,
              color:       dimmed,
              fontWeight:  FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
