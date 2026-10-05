import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/message.dart';
import '../providers/chat_provider.dart';
import '../../../core/theme/tokens.dart';

class PinnedMessageBanner extends ConsumerStatefulWidget {
  const PinnedMessageBanner({
    super.key,
    required this.conversationId,
    this.onTap,
  });

  final String    conversationId;
  final void Function(Message)? onTap;

  @override
  ConsumerState<PinnedMessageBanner> createState() =>
      _PinnedMessageBannerState();
}

class _PinnedMessageBannerState extends ConsumerState<PinnedMessageBanner> {
  int _index = 0;

  /// Type-aware preview for the pinned banner.
  /// Plaintext-only fallback `decryptedBody ?? '📎 Attachment'` left media
  /// messages looking blank (the body's just a duration string for voice/
  /// video or empty for documents). Emojis here match the conversation-list
  /// previews, so it feels consistent.
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
        final text = body.isNotEmpty ? body : '🔒 Encrypted';
        return text.length > 60 ? '${text.substring(0, 60)}…' : text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinned = ref.watch(pinnedMessagesProvider(widget.conversationId));

    return pinned.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, __) => const SizedBox.shrink(),
      data: (messages) {
        if (messages.isEmpty) return const SizedBox.shrink();

        final msg = messages[_index % messages.length];
        final preview = _previewForBanner(msg);

        return GestureDetector(
          onTap: () {
            widget.onTap?.call(msg);
            if (messages.length > 1) {
              setState(() => _index = (_index + 1) % messages.length);
            }
          },
          child: Container(
            width:   double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.15),
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
                          fontSize:   11,
                          fontWeight: FontWeight.w600,
                          color:      context.t.accent,
                        ),
                      ),
                      Text(
                        preview.length > 60
                            ? '${preview.substring(0, 60)}…'
                            : preview,
                        style: TextStyle(
                          fontSize: 12,
                          color:    Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                        maxLines:  1,
                        overflow:  TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (messages.length > 1)
                  Icon(Icons.keyboard_arrow_up,
                      size: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.4)),
              ],
            ),
          ),
        );
      },
    );
  }
}
