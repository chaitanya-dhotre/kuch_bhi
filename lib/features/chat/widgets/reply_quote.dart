import 'package:flutter/material.dart';

import '../../../core/decrypt/body_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/message.dart';
import '../providers/chat_provider.dart';
import '../../../core/theme/tokens.dart';

/// Resolves the original (replied-to) message row from Drift by server id.
final _originalMessageProvider = FutureProvider.autoDispose
    .family<MessagesTableData?, String>((ref, serverId) {
  return ref
      .read(appDatabaseProvider)
      .messagesDao
      .getMessageByServerId(serverId);
});

/// Compact quote shown inside a message bubble (received) or above the
/// input bar (composing). Pass [compact] = true for the input bar.
///
/// If [replyToId] (server id of the original message) is provided the quote
/// resolves the original message from Drift and renders a media-aware
/// preview (photo/video thumbnail, voice duration, document label) like
/// WhatsApp. Falls back to [messageType] / emoji-prefix heuristics when the
/// row isn't found locally.
class ReplyQuote extends ConsumerWidget {
  const ReplyQuote({
    super.key,
    required this.preview,
    required this.senderName,
    this.isMine         = false,
    this.compact        = false,
    this.messageType    = 'text',
    this.replyToId,
    this.conversationId,
    this.onCancel,
  });

  final String         preview;
  final String         senderName;
  final bool           isMine;
  final bool           compact;
  final String         messageType;
  /// SERVER id of the original (replied-to) message, if known.
  final String?        replyToId;
  /// Needed to decrypt media thumbnails (conversation key lookup).
  final String?        conversationId;
  final VoidCallback?  onCancel;

  factory ReplyQuote.fromMessage(Message msg, String senderName, {
    bool isMine = false, bool compact = false, VoidCallback? onCancel,
  }) {
    final body = msg.decryptedBody ?? '🔒 Encrypted';
    // Media previews should show a type label, not the (possibly empty) body
    final preview = switch (msg.type) {
      'image'    => 'Photo',
      'video'    => 'Video',
      'voice'    => body.startsWith('🎤') ? body : '🎤 Voice message',
      'document' => body.isNotEmpty ? body : 'Document',
      _          => body.length > 80 ? '${body.substring(0, 80)}…' : body,
    };
    return ReplyQuote(
      preview:        preview,
      senderName:     senderName,
      isMine:         isMine,
      compact:        compact,
      messageType:    msg.type,
      replyToId:      msg.serverId,
      conversationId: msg.conversationId,
      onCancel:       onCancel,
    );
  }

  static const _mediaTypes = {'image', 'video', 'voice', 'document'};

  /// Type guess when the original row isn't available locally.
  String get _fallbackType {
    if (_mediaTypes.contains(messageType)) return messageType;
    if (preview.startsWith('🎤')) return 'voice';
    if (preview.startsWith('📷')) return 'image';
    if (preview.startsWith('🎥')) return 'video';
    if (preview.startsWith('📄')) return 'document';
    return 'text';
  }

  static IconData? _iconFor(String type) => switch (type) {
    'image'    => Icons.camera_alt_outlined,
    'video'    => Icons.videocam_outlined,
    'voice'    => Icons.mic_none,
    'document' => Icons.description_outlined,
    _          => null,
  };

  /// Strips a leading media emoji ('🎤 ', '📷 ', …) from a preview string.
  static String _stripEmoji(String s) =>
      s.replaceFirst(RegExp(r'^(🎤|📷|🎥|📄)\s*'), '').trim();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ── Resolve the original message from Drift (if we have its id) ─────
    MessagesTableData? original;
    if (replyToId != null) {
      original = ref.watch(_originalMessageProvider(replyToId!)).asData?.value;
    }
    final String resolvedType = original?.type ?? _fallbackType;

    // ── Background ──────────────────────────────────────────────
    // Sent bubble reply    : warm white tint on the marigold sent bubble.
    // Received bubble      : accentSoft (cream/brown, theme-aware) inset.
    // Input bar (compact)  : adaptive surface container
    final Color bg;
    if (compact) {
      bg = Theme.of(context).colorScheme.surfaceContainerHighest;
    } else if (isMine) {
      // Subtle inset on the accent-filled sent bubble — same trick as the
      // bubble's own separator (ink @ 6%), kept visible via white tint.
      bg = Colors.white.withValues(alpha: 0.18);
    } else {
      bg = context.t.accentSoft; // light cream / dark warm brown
    }

    // ── Text colours ────────────────────────────────────────────
    // Sent bubble  → on the white tint: dark onAccent in light mode, light
    //                ink in dark mode (tint over dark scaffold = mid grey).
    // Received + compact → theme ink (already correct in both brightnesses).
    final Color nameColor;
    final Color previewColor;
    final Color iconColor;
    if (isMine && !compact) {
      final onTint = isDark ? context.t.ink : context.t.onAccent;
      nameColor    = onTint;
      previewColor = onTint.withValues(alpha: 0.80);
      iconColor    = onTint.withValues(alpha: 0.65);
    } else {
      nameColor    = context.t.accent;
      previewColor = context.t.ink.withValues(alpha: 0.80);
      iconColor    = context.t.ink.withValues(alpha: 0.60);
    }

    // ── Preview label per resolved type ─────────────────────────
    final String label;
    switch (resolvedType) {
      case 'image':
        label = 'Photo';
      case 'video':
        label = 'Video';
      case 'voice':
        // T9: row bodies live in the session cache (column dropped).
        final origBody =
            original == null ? null : bodyCache.get(original.localId);
        final dur = _stripEmoji(
            origBody ?? (_fallbackType == 'voice' ? preview : ''));
        label = dur.isNotEmpty && dur != 'Voice message'
            ? 'Voice message · $dur'
            : 'Voice message';
      case 'document':
        final doc = _stripEmoji(
            (original == null ? null : bodyCache.get(original.localId)) ??
                preview);
        label = doc.isNotEmpty ? doc : 'Document';
      default:
        label = preview;
    }

    final icon = _iconFor(resolvedType);

    // Thumbnail on the right for photo/video replies (needs the original row
    // — its server id — and the conversation id for the decryption key).
    final bool showThumb =
        (resolvedType == 'image' || resolvedType == 'video') &&
        original?.serverId != null &&
        conversationId != null;

    final textColumn = Column(
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
          label,
          maxLines:  1,
          overflow:  TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: previewColor),
        ),
      ],
    );

    Widget quote = Container(
      margin:  EdgeInsets.only(bottom: compact ? 0 : 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: context.t.accent, width: 3),
        ),
      ),
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
          ],
          // Compact (input bar): stretch full width so the cancel button
          // sits at the right edge. Bubble quote: size to content.
          if (compact)
            Expanded(child: textColumn)
          else
            Flexible(child: textColumn),
          if (showThumb) ...[
            const SizedBox(width: 8),
            _QuoteThumb(
              conversationId: conversationId!,
              serverId:       original!.serverId!,
              isVideo:        resolvedType == 'video',
              iconColor:      iconColor,
            ),
          ],
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

    if (!compact) {
      // Size to content, capped at 78% of the screen width.
      quote = ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: IntrinsicWidth(child: quote),
      );
    }

    return quote;
  }
}

/// 36x36 rounded decrypted thumbnail for photo/video reply quotes.
class _QuoteThumb extends ConsumerWidget {
  const _QuoteThumb({
    required this.conversationId,
    required this.serverId,
    required this.isVideo,
    required this.iconColor,
  });

  final String conversationId;
  final String serverId;
  final bool   isVideo;
  final Color  iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbAsync = ref.watch(
        mediaFileProvider(MediaRef(conversationId, serverId, thumb: true)));

    final placeholder = Container(
      width: 36, height: 36,
      color: Colors.black.withValues(alpha: 0.15),
      child: Icon(
        isVideo ? Icons.videocam_outlined : Icons.image_outlined,
        size: 18, color: iconColor,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 36, height: 36,
        child: thumbAsync.when(
          loading: () => placeholder,
          error:   (_, __) => placeholder,
          data: (media) => media == null
              ? placeholder
              : Image.file(
                  media.file,
                  width: 36, height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => placeholder,
                ),
        ),
      ),
    );
  }
}
