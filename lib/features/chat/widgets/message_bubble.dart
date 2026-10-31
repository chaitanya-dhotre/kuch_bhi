import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/decrypt/body_cache.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../core/widgets/skeleton.dart';
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
import 'expiry_badge.dart';

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

String _messageTypeLabel(String type) => switch (type) {
  'image' => kMediaRowPhotoLabel,
  'video' => kMediaRowVideoLabel,
  'voice' => kMediaRowVoiceLabel,
  'document' => kMediaRowDocumentLabel,
  'poll' => 'Poll',
  'system' => 'System message',
  _ => 'Message',
};

String _messageBodyLabel(Message message, String resolvedBody) {
  if (message.isDeletedForEveryone) return 'Message deleted';
  if (message.decryptState == 'key_missing' ||
      message.decryptState == 'failed') {
    return "Can't decrypt";
  }

  final body = resolvedBody.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (message.type == 'text' || message.type == 'system') {
    return body.isEmpty ? _messageTypeLabel(message.type) : body;
  }
  return _messageTypeLabel(message.type);
}

String _messageRowSemanticsLabel({
  required Message message,
  required bool isMine,
  required String senderName,
  required String resolvedBody,
}) {
  final sender = isMine
      ? 'You'
      : senderName.trim().isEmpty
      ? 'Unknown sender'
      : senderName.trim();
  final body = _messageBodyLabel(message, resolvedBody);
  final time = DateFormat('HH:mm').format(message.createdAt.toLocal());
  final status = message.status.trim().isEmpty ? 'unknown' : message.status;
  return 'From $sender. $body. Time $time. Status $status.';
}

Widget _messageRowSemantics({
  required String label,
  required Widget child,
  required bool preserveChildNodes,
}) => Semantics(
  // Text-only rows collapse into one semantic leaf. Rows with media,
  // reactions, reply quotes, or retry controls keep explicit child nodes so
  // their labelled actions remain independently reachable.
  container: true,
  explicitChildNodes: preserveChildNodes,
  label: label,
  child: child,
);

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.senderName = 'Unknown',
    this.isGroup = false,
    this.runStart = true,
    this.runEnd = true,
    this.searchQuery,
    this.searchCurrent = false,
    this.selected = false,
    this.onSelect,
    this.onReply,
    this.onReplyTap,
  });

  final Message message;
  final bool isMine;
  final String senderName;
  final bool isGroup;
  final bool runStart;
  final bool runEnd;
  final String? searchQuery;
  final bool searchCurrent;
  final bool selected;
  final VoidCallback? onSelect;
  final VoidCallback? onReply;
  final VoidCallback? onReplyTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // T9 (spec §5.1): THE body read goes through messageBodyProvider —
    // cache-resident text resolves synchronously (no frame of placeholder
    // for own-sent), a miss watches the family and rebuilds when it emits.
    // `resolved` stays null while unresolved → branch to the placeholder-
    // rendering surfaces below (never ciphertext, never a blank).
    final String? resolved =
        bodyCache.get(message.localId) ??
        ref.watch(messageBodyProvider(message.localId)).valueOrNull;
    final body = resolved ?? '';
    final emojiOnly = isEmojiOnly(body) && message.type == 'text';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = extractFirstUrl(body);
    final rowSemanticsLabel = _messageRowSemanticsLabel(
      message: message,
      isMine: isMine,
      senderName: senderName,
      resolvedBody: body,
    );

    // ── System / info bubbles — no reply, no long-press, no sender meta ─
    if (message.type == 'system') {
      return _messageRowSemantics(
        label: rowSemanticsLabel,
        preserveChildNodes: false,
        child: _SystemMessageBubble(
          messageId: message.localId,
          decryptState: message.decryptState,
          ciphertextLength: message.ciphertextLength,
        ),
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
        onSelect: onSelect,
      ),
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // ── Group sender name ────────────────────────────────
          if (isGroup && !isMine && runStart)
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 1, top: 4),
              child: ExcludeSemantics(
                child: Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 12, // plan floor: labels ≥ w600 12px
                    fontWeight: FontWeight.w600,
                    color: _colorForSender(
                      message.senderId,
                      Theme.of(context).brightness,
                    ),
                  ),
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
                padding: ChatBubbleGeometry.margin(
                  isMine: isMine,
                ).copyWith(bottom: 0),
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
            VoiceMessageBubble(
              conversationId: message.conversationId,
              serverId: message.serverId!,
              isMine: isMine,
              runEnd: runEnd,
              durationText: resolved,
              status: message.status,
              createdAt: message.createdAt,
            )
          else if (message.type == 'image' && message.serverId != null)
            ImageMessageBubble(
              conversationId: message.conversationId,
              serverId: message.serverId!,
              isMine: isMine,
              isDark: isDark,
              runEnd: runEnd,
              status: message.status,
              createdAt: message.createdAt,
              senderName: senderName,
            )
          else if (message.type == 'video' && message.serverId != null)
            VideoMessageBubble(
              conversationId: message.conversationId,
              serverId: message.serverId!,
              isMine: isMine,
              isDark: isDark,
              runEnd: runEnd,
              status: message.status,
              createdAt: message.createdAt,
              senderName: senderName,
            )
          else if (message.type == 'document' && message.serverId != null)
            DocumentMessageBubble(
              conversationId: message.conversationId,
              serverId: message.serverId!,
              isMine: isMine,
              isDark: isDark,
              runEnd: runEnd,
              status: message.status,
              createdAt: message.createdAt,
            )
          else if (message.serverId == null &&
              const {
                'image',
                'video',
                'voice',
                'document',
              }.contains(message.type))
            // Optimistic upload in flight (serverId not stamped yet). Keep
            // the shape/type recognizable without changing the data layer.
            ExcludeSemantics(
              child: _OptimisticMediaPlaceholder(
                type: message.type,
                isMine: isMine,
                runEnd: runEnd,
                status: message.status,
                createdAt: message.createdAt,
              ),
            )
          else if (emojiOnly)
            _EmojiOnlyBubble(message: message, isMine: isMine, runEnd: runEnd)
          else
            _TextBubble(
              message: message,
              isMine: isMine,
              runEnd: runEnd,
              skeletonShell: resolved == null && !message.isDeletedForEveryone,
              highlightQuery: searchQuery,
              highlightCurrent: searchCurrent,
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
              onDiscard: () => ref
                  .read(messageRepositoryProvider)
                  .discardOp(terminalOp.opId),
            ),
        ],
      ),
    );

    Widget content = SwipeToReply(
      isMine: isMine,
      onReply: onReply ?? () {},
      child: bubble,
    );

    if (isGroup && !isMine) {
      final initial = initialsOf(senderName);
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // The bubble's own margin gives the disc→bubble gap; this pad
          // keeps the disc off the screen edge and level with the bubble.
          Padding(
            padding: const EdgeInsets.only(
              left: ChatBubbleGeometry.nearMargin,
              bottom: ChatBubbleGeometry.verticalMargin,
            ),
            child: SizedBox(
              width: 28,
              child: runStart
                  ? ExcludeSemantics(
                      child: AppAvatar(radius: 14, initials: initial),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          Flexible(child: content),
        ],
      );
    }

    if (selected) {
      content = Container(
        decoration: BoxDecoration(
          color: context.t.accent.withValues(alpha: 0.08),
          border: Border.all(color: context.t.accent.withValues(alpha: 0.55)),
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
        ),
        child: content,
      );
    }

    final hasInteractiveChildren =
        terminalOp != null ||
        message.replyToId != null ||
        url != null ||
        message.serverId != null;
    return _messageRowSemantics(
      label: rowSemanticsLabel,
      preserveChildNodes: hasInteractiveChildren,
      child: content,
    );
  }
}

/// Per-type optimistic media shell. It deliberately stays presentation-only:
/// the real media widgets take over as soon as the server id is stamped.
class _OptimisticMediaPlaceholder extends StatelessWidget {
  const _OptimisticMediaPlaceholder({
    required this.type,
    required this.isMine,
    required this.runEnd,
    required this.status,
    required this.createdAt,
  });

  final String type;
  final bool isMine;
  final bool runEnd;
  final String status;
  final DateTime createdAt;

  @override
  Widget build(BuildContext context) {
    final shellColor = isMine
        ? context.t.accent.withValues(alpha: 0.18)
        : context.t.surface2;
    final mediaType = type == 'video' ? 'video' : 'image';
    final mediaSkeleton = ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: ChatBubbleGeometry.mediaMaxWidth,
      ),
      child: AspectRatio(
        aspectRatio: mediaType == 'video' ? 16 / 9 : 4 / 3,
        child: Skeleton.fill(),
      ),
    );

    if (type == 'image' || type == 'video') {
      return ChatBubbleFrame(
        isMine: isMine,
        runEnd: runEnd,
        background: shellColor,
        showShadow: false,
        showTimestamp: true,
        createdAt: createdAt,
        status: status,
        padding: EdgeInsets.zero,
        child: mediaSkeleton,
      );
    }

    // A failed upload never gets a server id, so it stays here: say so
    // instead of spinning forever.
    final failed = status == 'failed';
    final content = switch (type) {
      'voice' => _OptimisticVoiceContent(isMine: isMine, failed: failed),
      _ => _OptimisticDocumentContent(isMine: isMine, failed: failed),
    };
    // Default shell (full accent when mine): onAccent ink on the 18% shell
    // was unreadable in dark mode.
    return ChatBubbleFrame(
      isMine: isMine,
      runEnd: runEnd,
      showShadow: false,
      fillWidth: true,
      showTimestamp: true,
      timestampOverlay: false,
      createdAt: createdAt,
      status: status,
      child: Column(mainAxisSize: MainAxisSize.min, children: [content]),
    );
  }
}

class _OptimisticVoiceContent extends StatelessWidget {
  const _OptimisticVoiceContent({required this.isMine, required this.failed});

  final bool isMine;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final foreground = isMine ? context.t.onAccent : context.t.accent;
    if (failed) {
      return _FailedUploadRow(
        icon: Icons.mic_none_outlined,
        label: 'Voice note not sent',
        foreground: foreground,
      );
    }
    return Row(
      children: [
        BusySpinner(size: 30, strokeWidth: 2, color: foreground),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 10,
            child: Skeleton.fill(),
          ),
        ),
      ],
    );
  }
}

class _OptimisticDocumentContent extends StatelessWidget {
  const _OptimisticDocumentContent({
    required this.isMine,
    required this.failed,
  });

  final bool isMine;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final foreground = isMine ? context.t.onAccent : context.t.accent;
    if (failed) {
      return _FailedUploadRow(
        icon: Icons.insert_drive_file_outlined,
        label: 'Document not sent',
        foreground: foreground,
      );
    }
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: foreground.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.insert_drive_file_outlined, color: foreground),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Uploading document…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: foreground.withValues(alpha: 0.76),
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 8),
        BusySpinner(size: 18, strokeWidth: 2, color: foreground),
      ],
    );
  }
}

/// Static row for an upload that failed; the timestamp's ⚠ carries the state.
class _FailedUploadRow extends StatelessWidget {
  const _FailedUploadRow({
    required this.icon,
    required this.label,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: foreground.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: foreground),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: foreground, fontSize: 13),
          ),
        ),
      ],
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
        margin: ChatBubbleGeometry.margin(isMine: isMine),
        constraints: BoxConstraints(
          maxWidth: ChatBubbleGeometry.maxWidth(context),
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
  const _EmojiOnlyBubble({
    required this.message,
    required this.isMine,
    required this.runEnd,
  });
  final Message message;
  final bool isMine;
  final bool runEnd;

  @override
  Widget build(BuildContext context) {
    return ChatBubbleFrame(
      isMine: isMine,
      runEnd: runEnd,
      chrome: false,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: MessageBodyText(
              messageId: message.localId,
              styleContext: 'emoji',
              decryptState: message.decryptState,
              ciphertextLength: message.ciphertextLength,
            ),
          ),
          if (runEnd) ...[
            const SizedBox(height: ChatBubbleGeometry.metadataGap),
            ChatBubbleTimestamp(
              isMine: isMine,
              createdAt: message.createdAt,
              status: message.status,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Standard text bubble ──────────────────────────────────────────────────

class _TextBubble extends StatelessWidget {
  const _TextBubble({
    required this.message,
    required this.isMine,
    required this.runEnd,
    required this.skeletonShell,
    this.highlightQuery,
    this.highlightCurrent = false,
    this.url,
  });

  final Message message;
  final bool isMine;
  final bool runEnd;
  final bool skeletonShell;
  final String? highlightQuery;
  final bool highlightCurrent;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return ChatBubbleFrame(
      isMine: isMine,
      runEnd: runEnd,
      background: skeletonShell
          ? (isMine
                ? context.t.accent.withValues(alpha: 0.18)
                : context.t.surface2)
          : null,
      showShadow: !skeletonShell,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.isDeletedForEveryone)
            ExcludeSemantics(
              child: Text(
                '🚫 Message deleted',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                  color: isMine
                      ? context.t.onAccent.withValues(alpha: 0.7)
                      : context.t.inkSoft,
                ),
              ),
            )
          else
            ExcludeSemantics(
              child: MessageBodyText(
                messageId: message.localId,
                styleContext: isMine ? 'bubble.mine' : 'bubble',
                decryptState: message.decryptState,
                ciphertextLength: message.ciphertextLength,
                skeletonShell: skeletonShell,
                highlightQuery: highlightQuery,
                highlightCurrent: highlightCurrent,
              ),
            ),

          // Link preview
          if (url != null && !message.isDeletedForEveryone)
            LinkPreviewCard(url: url!),

          if (runEnd) ...[
            const SizedBox(height: ChatBubbleGeometry.metadataGap),
            ChatBubbleTimestamp(
              isMine: isMine,
              createdAt: message.createdAt,
              status: message.status,
            ),
          ],
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
            color: context.t.surface2.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          // T9: system bodies ride the same placeholder law — cache-resident
          // local emits paint instantly; an unresolved id shows the keyed
          // placeholder inside the pill (never a blank narrative row).
          child: ExcludeSemantics(
            child: MessageBodyText(
              messageId: messageId,
              styleContext: 'system',
              decryptState: decryptState,
              ciphertextLength: ciphertextLength,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: context.t.ink.withValues(alpha: 0.55),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
