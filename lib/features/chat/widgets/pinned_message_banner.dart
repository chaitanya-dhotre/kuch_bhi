import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/message.dart';
import '../providers/chat_provider.dart';
import '../../../core/theme/tokens.dart';
import 'message_body_text.dart';

class PinnedMessageBanner extends ConsumerStatefulWidget {
  const PinnedMessageBanner({
    super.key,
    required this.conversationId,
    this.onTap,
  });

  final String conversationId;
  final void Function(Message)? onTap;

  @override
  ConsumerState<PinnedMessageBanner> createState() =>
      _PinnedMessageBannerState();
}

class _PinnedMessageBannerState extends ConsumerState<PinnedMessageBanner> {
  int _index = 0;

  /// Type-aware preview for media/system rows. Text bodies and terminal
  /// decrypt states use [MessageBodyText] so they share the chat/home state
  /// machine: transient = neutral placeholder, terminal = explicit error.
  static String _previewForBanner(Message msg) {
    final body = msg.decryptedBody ?? '';
    switch (msg.type) {
      case 'image':
        return '📷 Photo';
      case 'video':
        return body.isNotEmpty ? '🎬 Video · $body' : '🎬 Video';
      case 'voice':
        return body.isNotEmpty && body != 'Voice message'
            ? '🎤 Voice message · $body'
            : '🎤 Voice message';
      case 'document':
        return body.isNotEmpty ? '📎 $body' : '📎 Document';
      default:
        return 'New message';
    }
  }

  Widget _previewWidget(BuildContext context, Message msg) {
    final previewStyle = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    );
    final terminal =
        msg.decryptState == 'key_missing' || msg.decryptState == 'failed';

    // Text and terminal rows must use the shared body state machine. This
    // removes the misleading old "🔒 Encrypted" fallback from pinned UI.
    if (msg.type == 'text' || terminal) {
      return MessageBodyText(
        messageId: msg.localId,
        styleContext: 'preview',
        decryptState: msg.decryptState,
        ciphertextLength: msg.ciphertextLength,
        style: previewStyle,
      );
    }

    return Text(
      _previewForBanner(msg),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: previewStyle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pinned = ref.watch(pinnedMessagesProvider(widget.conversationId));

    return pinned.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (messages) {
        if (messages.isEmpty) return const SizedBox.shrink();

        final msg = messages[_index % messages.length];
        return GestureDetector(
          onTap: () {
            widget.onTap?.call(msg);
            if (messages.length > 1) {
              setState(() => _index = (_index + 1) % messages.length);
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.15),
                ),
                left: BorderSide(color: context.t.accent, width: 3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.push_pin, size: 14, color: context.t.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        messages.length > 1
                            ? 'Pinned Message ${_index + 1}/${messages.length}'
                            : 'Pinned Message',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.t.accent,
                        ),
                      ),
                      _previewWidget(context, msg),
                    ],
                  ),
                ),
                if (messages.length > 1)
                  Icon(
                    Icons.keyboard_arrow_up,
                    size: 16,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
