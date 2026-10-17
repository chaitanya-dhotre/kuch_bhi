import 'package:flutter/material.dart';

import '../../../core/decrypt/body_cache.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/message.dart';
import '../providers/chat_provider.dart';
import '../../../core/theme/tokens.dart';
import 'message_body_text.dart';

/// Resolves the original (replied-to) message row from Drift.
///
/// P7: the id a quote carries is a LOCAL id while the reply is still
/// unsent (the enqueue writes `replyToLocalId`) and becomes a SERVER id
/// once the dual-truth stamp lands — resolve BOTH, local first.
final _originalMessageProvider = FutureProvider.autoDispose
    .family<MessagesTableData?, String>((ref, id) async {
      final dao = ref.read(appDatabaseProvider).messagesDao;
      return await dao.getMessageByLocalId(id) ?? dao.getMessageByServerId(id);
    });

/// Compact quote shown inside a message bubble (received) or above the
/// input bar (composing). Pass [compact] = true for the input bar.
///
/// **P7 / spec §3 — previews are DERIVED, never stored.** With
/// [replyToId] provided the quote resolves the original row from Drift and
/// renders a media-aware preview (photo/video thumbnail, voice duration,
/// document label); a TEXT parent's line comes from
/// `messageBodyProvider(messageId)` — the same read path as a bubble, so
/// an unresolved/gone parent renders the keyed geometry-preserving placeholder
/// (with lock/error only for terminal decrypt states), never a blank and never
/// raw ciphertext. Falls back to [messageType]
/// only to pick the label when the row isn't found locally.
///
/// [preview] is an OPTIONAL explicit label used solely by the input bar
/// (built in memory from the reply provider — never from storage).
class ReplyQuote extends ConsumerWidget {
  const ReplyQuote({
    super.key,
    this.preview,
    required this.senderName,
    this.isMine = false,
    this.compact = false,
    this.messageType = 'text',
    this.decryptState = 'ready',
    this.ciphertextLength = 0,
    this.replyToId,
    this.conversationId,
    this.onCancel,
  });

  /// Optional EXPLICIT label (input bar only — in-memory source).
  final String? preview;
  final String senderName;
  final bool isMine;
  final bool compact;
  final String messageType;
  final String decryptState;
  final int ciphertextLength;
  /// SERVER id of the original (replied-to) message, if known.
  final String? replyToId;
  /// Needed to decrypt media thumbnails (conversation key lookup).
  final String? conversationId;
  final VoidCallback? onCancel;

  factory ReplyQuote.fromMessage(Message msg, String senderName, {
    bool isMine = false, bool compact = false, VoidCallback? onCancel,
  }) {
    final body = msg.decryptedBody;
    // Media previews should show a type label, not the (possibly empty) body
    final String? preview = switch (msg.type) {
      'image' => 'Photo',
      'video' => 'Video',
      'voice' => body?.startsWith('🎤') == true ? body : '🎤 Voice message',
      'document' => body?.isNotEmpty == true ? body : 'Document',
      _ =>
        body == null
            ? null
            : body.length > 80
            ? '${body.substring(0, 80)}…'
            : body,
    };
    return ReplyQuote(
      preview: preview,
      senderName: senderName,
      isMine: isMine,
      compact: compact,
      messageType: msg.type,
      decryptState: msg.decryptState,
      ciphertextLength: msg.ciphertextLength,
      replyToId: msg.serverId ?? msg.localId,
      conversationId: msg.conversationId,
      onCancel: onCancel,
    );
  }

  static const _mediaTypes = {'image', 'video', 'voice', 'document'};

  /// Type guess when the original row isn't available locally.
  String get _fallbackType {
    if (_mediaTypes.contains(messageType)) return messageType;
    final p = preview;
    if (p != null) {
      if (p.startsWith('🎤')) return 'voice';
      if (p.startsWith('📷')) return 'image';
      if (p.startsWith('🎥')) return 'video';
      if (p.startsWith('📄')) return 'document';
    }
    return 'text';
  }

  static IconData? _iconFor(String type) => switch (type) {
    'image' => Icons.camera_alt_outlined,
    'video' => Icons.videocam_outlined,
    'voice' => Icons.mic_none,
    'document' => Icons.description_outlined,
    _ => null,
  };

  /// Strips a leading media emoji ('🎤 ', '📷 ', …) from a preview string.
  static String _stripEmoji(String s) =>
      s.replaceFirst(RegExp(r'^(🎤|📷|🎥|📄)\s*'), '').trim();

  /// The preview line for a CONSTANT label (type labels + explicit input-bar
  /// label) — single line, ellipsised, 12px (the quote's typography).
  static Widget _line(String text, Color color) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: 12, color: color),
  );

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
      nameColor = onTint;
      previewColor = onTint.withValues(alpha: 0.80);
      iconColor = onTint.withValues(alpha: 0.65);
    } else {
      nameColor = context.t.accent;
      previewColor = context.t.ink.withValues(alpha: 0.80);
      iconColor = context.t.ink.withValues(alpha: 0.60);
    }

    // ── Preview line (P7 / spec §3: DERIVED, never a stored string) ────
    // An explicit [preview] (input bar, built in memory from the reply
    // provider) wins. Otherwise everything derives from the parent row:
    // media → CONSTANT type labels; voice/document → the session body
    // cache with a constant fallback (never blank); text → THE PROVIDER.
    final String? explicit =
        (preview == null || preview!.isEmpty) ? null : preview;
    final Widget previewLine;
    if (explicit != null) {
      previewLine = _line(explicit, previewColor);
    } else {
      switch (resolvedType) {
        case 'image':
          previewLine = _line('Photo', previewColor);
        case 'video':
          previewLine = _line('Video', previewColor);
        case 'voice':
          // T9/P7: row bodies live in the session cache only.
          final origBody =
              original == null ? null : bodyCache.get(original.localId);
          final dur = _stripEmoji(origBody ?? '');
          previewLine = _line(
            dur.isNotEmpty && dur != 'Voice message'
                ? 'Voice message · $dur'
                : 'Voice message',
              previewColor);
        case 'document':
          final doc = original == null
              ? ''
              : _stripEmoji(bodyCache.get(original.localId) ?? '');
          previewLine = _line(doc.isNotEmpty ? doc : 'Document', previewColor);
        default:
          // text (or the parent row is gone): messageBodyProvider is the
          // single read path. A gone/unresolvable parent resolves null ⇒
          // the keyed geometry-preserving placeholder — never blank, never
          // raw ciphertext (spec §8 placeholder law; user ruling: never
          // re-introduce ciphertext printing in a quote).
          final parentId = original?.localId ?? replyToId;
          previewLine = parentId == null
              ? _line('Message', previewColor)
              : MessageBodyText(
                  messageId: parentId,
                  styleContext: 'preview',
                  decryptState: original?.decryptState ?? decryptState,
                  ciphertextLength:
                      original?.encryptedBody.length ?? ciphertextLength,
                  style: TextStyle(fontSize: 12, color: previewColor),
                );
      }
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          senderName,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: nameColor,
          ),
        ),
        const SizedBox(height: 2),
        previewLine,
      ],
    );

    Widget quote = Container(
      margin: EdgeInsets.only(bottom: compact ? 0 : 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
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
              serverId: original!.serverId!,
              isVideo: resolvedType == 'video',
              iconColor: iconColor,
            ),
          ],
          if (onCancel != null)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: previewColor),
              onPressed: onCancel,
              padding: EdgeInsets.zero,
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
  final bool isVideo;
  final Color iconColor;

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
          error: (_, __) => placeholder,
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
