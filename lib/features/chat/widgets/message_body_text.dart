import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/decrypt/body_cache.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/entities/conversation.dart';
import '../providers/message_body_provider.dart';

/// THE body renderer (spec §8 placeholder law — Task 9).
///
/// Every consumer that displays a message body goes through this widget:
/// it watches `messageBodyProvider(messageId)` and renders
/// - text when a body is available — the synchronous [bodyCache] fast-path
///   resolves the very FIRST frame (own-sent messages never flash a
///   placeholder, spec §5.1), else when the provider emits;
/// - a keyed skeleton + 🔒 placeholder while the provider is loading OR
///   resolves null (`key_missing`/`failed`/not-yet-resident) — never
///   blank, never throws, never spinner-blocks.
///
/// [styleContext] picks the typography/color slot:
/// `'bubble.mine' | 'bubble' | 'emoji' | 'system' | 'preview'`.
/// [style] overrides the slot wholesale (parent-controlled coloring).
class MessageBodyText extends ConsumerWidget {
  const MessageBodyText({
    super.key,
    required this.messageId,
    required this.styleContext,
    this.style,
  });

  final String messageId;
  final String styleContext;
  final TextStyle? style;

  /// The placeholder's finder key — brief tests pin
  /// `ValueKey('body-placeholder-<messageId>')`.
  static ValueKey<String> placeholderKey(String messageId) =>
      ValueKey('body-placeholder-$messageId');

  TextStyle _slotStyle(BuildContext context) {
    final t = context.t;
    return switch (styleContext) {
      'bubble.mine' => TextStyle(color: t.onAccent, fontSize: 15),
      'bubble' => TextStyle(color: t.ink, fontSize: 15),
      'emoji' => const TextStyle(fontSize: 40),
      'system' => TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.55),
        ),
      'preview' => TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: t.inkSoft,
        ),
      _ => const TextStyle(fontSize: 15),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Cache fast-path: resolves instantly (and synchronously) so a resident
    // body never flashes the placeholder for a frame. The provider watch
    // below stays UNCONDITIONAL (Riverpod rule) and covers the miss path.
    final cached = bodyCache.get(messageId);
    final resolved =
        cached ?? ref.watch(messageBodyProvider(messageId)).valueOrNull;
    final slot = style ?? _slotStyle(context);
    if (resolved != null) {
      return Text(
        resolved,
        style: slot,
        maxLines: styleContext == 'preview' ? 1 : null,
        overflow: styleContext == 'preview' ? TextOverflow.ellipsis : null,
      );
    }
    // Loading OR resolved-null — same visible contract (spec §8): skeleton
    // line + lock hint, keyed, never empty.
    return _BodyPlaceholder(key: placeholderKey(messageId), style: slot);
  }
}

/// Skeleton line + 🔒 hint — the ONLY thing an unresolved body renders.
/// Public so tests and future surfaces can locate/type-check it directly.
class _BodyPlaceholder extends StatelessWidget {
  const _BodyPlaceholder({super.key, required this.style});

  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final dim = style.color ?? t.inkSoft;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('🔒', style: style.copyWith(fontSize: 12)),
        const SizedBox(width: 6),
        // Skeleton line: a soft rounded bar standing in for the text that
        // has not decrypted yet (spec §8 "skeleton line + 🔒 hint").
        Container(
          width: 72,
          height: 10,
          decoration: BoxDecoration(
            color: dim.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
          ),
        ),
      ],
    );
  }
}

/// Constant label for a NON-text last message (spec §3 / P7: derived at
/// render time from the row's `type` — the same glyphs the old stored
/// `last_message_preview` column held, but never written anywhere).
String conversationPreviewLabel(String type) => switch (type) {
      'image'    => '📷 Photo',
      'video'    => '🎬 Video',
      'voice'    => '🎤 Voice message',
      'document' => '📎 Document',
      'poll'     => '📊 Poll',
      'system'   => 'New message',
      _          => 'New message',
    };

/// Conversation-list preview body (spec §8 placeholder law + P7 sealed
/// previews, spec §3: NOTHING preview-shaped is durable).
///
/// Every branch DERIVES from the newest message row of [conversation]:
/// * `text`      → [MessageBodyText] ⇒ `messageBodyProvider` (placeholder
///   until the body emits, never blank, never ciphertext);
/// * media/system → [conversationPreviewLabel] (a CONSTANT, not a body);
/// * no row at all (fresh chat / evicted last row) → [fallback], the
///   constant the caller passes.
/// There is deliberately no stored-preview fallback anywhere.
class ConversationPreviewText extends ConsumerWidget {
  const ConversationPreviewText({
    super.key,
    required this.conversation,
    required this.fallback,
    this.style,
  });

  final Conversation conversation;
  final String fallback;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastMsg = ref
        .watch(conversationLastMessageProvider(conversation.id))
        .valueOrNull;
    if (lastMsg == null) {
      return _label(fallback, context);
    }
    if (lastMsg.type == 'text') {
      return MessageBodyText(
        messageId: lastMsg.localId,
        styleContext: 'preview',
        style: style,
      );
    }
    return _label(conversationPreviewLabel(lastMsg.type), context);
  }

  Widget _label(String text, BuildContext context) => Text(
        text,
        style: style ??
            TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: context.t.inkSoft,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
}
