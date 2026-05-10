import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversation});
  final Conversation conversation;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();
  late String _conversationId;

  @override
  void initState() {
    super.initState();
    _conversationId = widget.conversation.id;
    // Mark as read when chat opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(messageRepositoryProvider)
          .markConversationRead(_conversationId);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conv = widget.conversation;
    final messagesAsync =
        ref.watch(messagesProvider(_conversationId));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primaryLight,
              backgroundImage: conv.avatarUrl != null
                  ? CachedNetworkImageProvider(conv.avatarUrl!)
                  : null,
              child: conv.avatarUrl == null
                  ? Text(
                      conv.displayName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conv.displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (conv.otherUser != null)
                    Text(
                      conv.isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        color: conv.isOnline
                            ? AppColors.success
                            : Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {}, // Phase 5: menu
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages list.
          Expanded(
            child: messagesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Say hello to ${conv.displayName}! 👋',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    // Get current user from Drift settings.
                    // We determine "mine" by comparing sender ID.
                    // We'll use a simple FutureProvider for this.
                    return _MessageItem(
                      message: msg,
                      conversationId: _conversationId,
                    );
                  },
                );
              },
            ),
          ),

          // Input bar.
          MessageInput(
            isLoading: false,
            onSend: (text) {
              ref.read(sendMessageProvider.notifier).send(
                conversationId: _conversationId,
                text: text,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MessageItem extends ConsumerWidget {
  const _MessageItem({
    required this.message,
    required this.conversationId,
  });

  final Message message;
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserIdProvider).asData?.value ?? '';
    return MessageBubble(message: message, isMine: message.senderId == myId);
  }
}
