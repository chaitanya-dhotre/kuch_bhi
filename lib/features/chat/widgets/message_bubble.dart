import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/decrypt/body_cache.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/emoji_utils.dart';
import '../../../data/local/database/app_database.dart' show OutboxTableData;
import '../../../data/local/database/tables/outbox_table.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart'
    show messageRepositoryProvider;
import '../providers/message_body_provider.dart';
import '../providers/outbox_status_provider.dart';
import 'message_body_text.dart';
import 'link_preview_card.dart';
import 'document_message_bubble.dart';
import 'image_message_bubble.dart';
import 'video_message_bubble.dart';
import 'voice_message_bubble.dart';
import 'reaction_bar.dart';
import 'reply_quote.dart';
import 'swipe_to_reply.dart';
import 'message_context_menu.dart';

// 5 deterministic sender name colors — Warm Pop tokens only (no violet/
// indigo; spec veto). Names render on t.surface. Light surface needs dark
// ink (accent/keyGold are ~2.2:1 on white); dark surface gets the warm
// highlight pair. Same slot count both themes so hash → index is stable.
List<Color> _senderPalette(Brightness brightness) =>
    brightness == Brightness.dark
    ? const [
        WarmPopTokens.accent, // 8.0:1 on dark surface
        WarmPopTokens.keyGold, // 7.6:1
        WarmPopTokens.info,
        WarmPopTokens.success,
        WarmPopTokens.error,
      ]
    : const [
        WarmPopTokens.info, // ~4.7:1 on white
        WarmPopTokens.success, // ~3.4:1
        WarmPopTokens.error, // ~3.9:1
        WarmPopTokens.inkSoft, // ~5.3:1
        WarmPopTokens.mascotSnout, // ~5.7:1 warm brown
      ];

Color _colorForSender(String senderId, Brightness brightness) {
  final palette = _senderPalette(brightness);
  return palette[senderId.hashCode.abs() % palette.length];
}

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.senderName = 'Unknown',
    this.isGroup = false,
    this.onReply,
    this.onReplyTap,
  });

  final Message message;
  final bool isMine;
  final String senderName;
  final bool isGroup;
  final VoidCallback? onReply;
  final VoidCallback? onReplyTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // T9 (spec §5.1): THE body read goes through messageBodyProvider —
    // cache-resident text resolves synchronously (no frame of placeholder
    // for own-sent), a miss watches the family and rebuilds when it emits.
    // `resolved` stays null while unresolved → branch to the placeholder-
    // rendering surfaces below (never ciphertext, never a blank).
    final String? resolved = bodyCache.get(message.localId) ??
        ref.watch(messageBodyProvider(message.localId)).valueOrNull;
    final body = resolved ?? '';
    final emojiOnly = isEmojiOnly(body) && message.type == 'text';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = extractFirstUrl(body);

    // ── System / info bubbles — no reply, no long-press, no sender meta ─
    if (message.type == 'system') {
      return _SystemMessageBubble(
        messageId: message.localId,
        decryptState: message.decryptState,
        ciphertextLength: message.ciphertextLength,
      );
    }

    // ── Terminal-failure lookup (Task 4) ───────────────────────────────
    // One shared outbox stream per conversation; find THIS message's op.
    // A `failedTerminal` row = stuck message → visible banner below.
    OutboxTableData? failedOp;
    final outboxRows =
        ref.watch(outboxStatusProvider(message.conversationId)).value ??
        const <OutboxTableData>[];
    for (final row in outboxRows) {
      if (row.ref == message.localId &&
          row.state == OutboxState.failedTerminal) {
        failedOp = row;
        break;
      }
    }
    final terminalOp = failedOp; // effectively final → promotable in closures

    final bubble = GestureDetector(
      onLongPress: () => showMessageMenu(
        context: context,
        ref: ref,
        message: message,
        isMine: isMine,
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
                  fontSize: 12, // plan floor: labels ≥ w600 12px
                  fontWeight: FontWeight.w600,
                  color:      _colorForSender(message.senderId,
                      Theme.of(context).brightness),
                ),
              ),
            ),

          // ── Reply quote (P7 / spec §3: DERIVED, never stored) ─────────
          // The presence test is the PARENT ID, not a preview string —
          // `messages.reply_preview` is dropped (schema v11). ReplyQuote
          // resolves the parent row and renders its text through
          // messageBodyProvider (placeholder while unresolved — never a
          // blank, never raw ciphertext).
          if (message.replyToId != null)
            GestureDetector(
              onTap: onReplyTap,
              child: Padding(
                padding: EdgeInsets.only(
                  left: isMine ? 64 : 12,
                  right: isMine ? 12 : 64,
                  top: 2,
                ),
                child: ReplyQuote(
                  // The quote shows WHO was replied to, not who sent THIS message.
                  // If I sent this message, I replied to the other user → show their name.
                  // If other user sent this message, they replied to me → show 'You'.
                  senderName: isMine ? senderName : 'You',
                  isMine: isMine,
                  // Local id while the reply is unsent, server id after the
                  // dual-truth stamp — ReplyQuote resolves BOTH.
                  replyToId: message.replyToId,
                  conversationId: message.conversationId,
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
                  left: isMine ? 64 : 12,
                  right: isMine ? 12 : 64,
                  top: 2,
                  bottom: 2,
                ),
                child: VoiceMessageBubble(
                  conversationId: message.conversationId,
                  serverId: message.serverId!,
                  isMine: isMine,
                  durationText: resolved,
                  status: message.status,
                  createdAt: message.createdAt,
                ),
              ),
            )
          else if (message.type == 'image' && message.serverId != null)
            Align(
              alignment:
                  isMine ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(
                  left: isMine ? 64 : 12,
                  right: isMine ? 12 : 64,
                  top: 2,
                  bottom: 2,
                ),
                child: ImageMessageBubble(
                  conversationId: message.conversationId,
                  serverId: message.serverId!,
                  isMine: isMine,
                  isDark: isDark,
                  status: message.status,
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
                  left: isMine ? 64 : 12,
                  right: isMine ? 12 : 64,
                  top: 2,
                  bottom: 2,
                ),
                child: VideoMessageBubble(
                  conversationId: message.conversationId,
                  serverId: message.serverId!,
                  isMine: isMine,
                  isDark: isDark,
                  status: message.status,
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
                serverId: message.serverId!,
                isMine: isMine,
                isDark: isDark,
                status: message.status,
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
                  left: isMine ? 64 : 12,
                  right: isMine ? 12 : 64,
                  top: 2,
                  bottom: 2,
                ),
                child: Container(
                  width: 140,
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
              isMine: isMine,
              isDark: isDark,
              url: url,
            ),

          // ── Reactions ────────────────────────────────────────
          if (message.serverId != null)
            ReactionBar(messageServerId: message.serverId!, isMine: isMine),

          // ── Terminal-failure banner (spec: stuck message VISIBLE) ──
          // Keyed by message localId; Retry/Discard wire straight to the
          // real repo (Task 3 retryOp/discardOp — discard cascades).
          if (terminalOp != null)
            TerminalFailureBanner(
              key: ValueKey('terminal-banner-${message.localId}'),
              isMine: isMine,
              errorClass: terminalOp.errorClass,
              onRetry: () =>
                  ref.read(messageRepositoryProvider).retryOp(terminalOp.opId),
              onDiscard: () =>
                  ref.read(messageRepositoryProvider).discardOp(terminalOp.opId),
            ),
        ],
      ),
    );

    return SwipeToReply(
      isMine: isMine,
      onReply: onReply ?? () {},
      child: bubble,
    );
  }
}

// ── Terminal-failure banner (Task 4) ──────────────────────────────────────
//
// Spec §5.2: a `failedTerminal` op must be VISIBLE under its message —
// error-class text + Retry (re-queue) + Discard (cascade delete). Warm Pop
// token law: `t.error` text on `t.error` @8% bg, radius `radiusSm`,
// system fonts, no new colors (grep gate 11).

class TerminalFailureBanner extends StatelessWidget {
  const TerminalFailureBanner({
    super.key,
    required this.isMine,
    required this.errorClass,
    required this.onRetry,
    required this.onDiscard,
  });

  final bool isMine;
  final String? errorClass;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final err = context.t.error;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isMine ? 64 : 12,
          right: isMine ? 12 : 64,
          top: 2,
          bottom: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: err.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 15, color: err),
                const SizedBox(width: 6),
                Text(
                  'Failed to send',
                  style: TextStyle(
                    color: err,
                    fontSize: 13,
                    fontWeight: FontWeight.w600, // plan floor: ≥w600 12px
                  ),
                ),
              ],
            ),
            if (errorClass != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 21),
                child: Text(
                  errorClass!,
                  style: TextStyle(color: err, fontSize: 11),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: err,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: onDiscard,
                  style: TextButton.styleFrom(
                    foregroundColor: err,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Discard'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Emoji-only (no bubble, large font) ────────────────────────────────────

class _EmojiOnlyBubble extends StatelessWidget {
  const _EmojiOnlyBubble({required this.message, required this.isMine});
  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          left: isMine ? 64 : 12,
          right: isMine ? 12 : 64,
          top: 2,
          bottom: 2,
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            MessageBodyText(
              messageId: message.localId,
              styleContext: 'emoji',
              decryptState: message.decryptState,
              ciphertextLength: message.ciphertextLength,
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
  final bool isMine;
  final bool isDark;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          left: isMine ? 64 : 12,
          right: isMine ? 12 : 64,
          top: 2,
          bottom: 2,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMine ? context.t.accent : context.t.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: context.t.ink.withValues(alpha: 0.06),
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
                  fontSize: 14,
                  color: isMine
                      ? context.t.onAccent.withValues(alpha: 0.7)
                      : context.t.inkSoft,
                ),
              )
            else
              MessageBodyText(
                messageId: message.localId,
                styleContext: isMine ? 'bubble.mine' : 'bubble',
                decryptState: message.decryptState,
                ciphertextLength: message.ciphertextLength,
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
                        ? context.t.onAccent.withValues(alpha: 0.6)
                        : context.t.inkFaint,
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
      return SizedBox(
        width: 12, height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
            color: context.t.onAccent.withValues(alpha: 0.54)),
      );
    }
    if (status == 'failed') {
      return Icon(Icons.error_outline, size: 14, color: context.t.error);
    }

    final Color color = switch (status) {
      'read' => context.t.onAccent, // on-accent = read (visible on Marigold)
      'delivered' => context.t.onAccent.withValues(alpha: 0.54),
      _ => context.t.onAccent.withValues(alpha: 0.38), // sent
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
  const _SystemMessageBubble({
    required this.messageId,
    required this.decryptState,
    required this.ciphertextLength,
  });
  final String messageId;
  final String decryptState;
  final int ciphertextLength;

  @override
  Widget build(BuildContext context) {
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
          // T9: system bodies ride the same placeholder law — cache-resident
          // local emits paint instantly; an unresolved id shows the keyed
          // placeholder inside the pill (never a blank narrative row).
          child: MessageBodyText(
            messageId: messageId,
            styleContext: 'system',
            decryptState: decryptState,
            ciphertextLength: ciphertextLength,
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color:       Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.55),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
