import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/message.dart';
import '../providers/chat_provider.dart';
import '../providers/album_provider.dart';
import '../chat_run_grouping.dart' show albumLabel;
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/tokens.dart';
import 'message_body_text.dart';
import '../providers/message_body_provider.dart';
import '../../stickers/sticker_widgets.dart';

class PinnedMessageBanner extends ConsumerStatefulWidget {
  const PinnedMessageBanner({
    super.key,
    required this.conversationId,
    this.onTap,
    this.onCycle,
  });

  final String conversationId;
  final void Function(Message)? onTap;
  final VoidCallback? onCycle;

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
        return kPreviewPhotoLabel;
      case 'video':
        return body.isNotEmpty ? '🎬 Video · $body' : kPreviewVideoLabel;
      case 'voice':
        return body.isNotEmpty && body != kMediaRowVoiceLabel
            ? '🎤 Voice message · $body'
            : kPreviewVoiceLabel;
      case 'document':
        return body.isNotEmpty ? '📎 $body' : kPreviewDocumentLabel;
      default:
        return 'New message';
    }
  }

  Widget _previewWidget(BuildContext context, Message msg) {
    final previewStyle = TextStyle(fontSize: 12, color: context.t.inkSoft);
    final terminal =
        msg.decryptState == 'key_missing' || msg.decryptState == 'failed';

    // 12.5 F5: a pinned album row previews what is inside the album.
    final albumId = msg.albumId;
    final albumRows = albumId == null
        ? null
        : ref
              .watch(
                albumRowsProvider(
                  AlbumKey(msg.conversationId, albumId),
                ),
              )
              .valueOrNull;
    final album = albumRows != null && albumRows.length >= 2
        ? albumRows
        : null;
    if (album != null && (msg.type == 'image' || msg.type == 'video')) {
      return Text(
        albumLabel(album),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: previewStyle,
      );
    }

    // Text and terminal rows must use the shared body state machine. This
    // removes the misleading old "🔒 Encrypted" fallback from pinned UI.
    if (msg.type == 'sticker' && !terminal) {
      return Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: stickerThumb(
              ref.watch(messageBodyProvider(msg.localId)).valueOrNull ??
                  msg.decryptedBody,
              24,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Sticker',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: previewStyle,
            ),
          ),
        ],
      );
    }
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

        final currentIndex = _index % messages.length;
        final msg = messages[currentIndex];
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: context.t.surface,
              border: Border.all(color: context.t.line),
              borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
              boxShadow: WarmPopTokens.cardShadow(context.t.shadow),
            ),
            child: Row(
              children: [
                Icon(Icons.push_pin, size: 14, color: context.t.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => widget.onTap?.call(msg),
                    borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            messages.length > 1
                                ? 'Pinned · ${currentIndex + 1}/${messages.length}'
                                : 'Pinned · 1/1',
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
                  ),
                ),
                if (messages.length > 1)
                  IconButton(
                    tooltip: 'Next pinned message',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    color: context.t.inkSoft,
                    onPressed: () {
                      widget.onCycle?.call();
                      if (widget.onCycle == null) {
                        setState(() => _index = (_index + 1) % messages.length);
                      }
                    },
                    icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
