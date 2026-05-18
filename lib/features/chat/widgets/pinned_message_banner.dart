import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/message.dart';
import '../providers/chat_provider.dart';

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

  @override
  Widget build(BuildContext context) {
    final pinned = ref.watch(pinnedMessagesProvider(widget.conversationId));

    return pinned.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, __) => const SizedBox.shrink(),
      data: (messages) {
        if (messages.isEmpty) return const SizedBox.shrink();

        final msg = messages[_index % messages.length];
        final preview = msg.decryptedBody ?? '📎 Attachment';

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
                left: const BorderSide(color: AppColors.primary, width: 3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.push_pin, size: 14, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        messages.length > 1
                            ? 'Pinned Message ${_index + 1}/${messages.length}'
                            : 'Pinned Message',
                        style: const TextStyle(
                          fontSize:   11,
                          fontWeight: FontWeight.w600,
                          color:      AppColors.primary,
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
