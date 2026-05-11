import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../../services/presence_service.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversation});
  final Conversation conversation;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {           // ← handles app resume/pause
  final _scrollController = ScrollController();
  bool _loadingMore = false;
  int  _currentOffset = 40;

  PresenceService get _presence => ref.read(presenceServiceProvider);
  String get _convId => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enterChat();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    // Fire-and-forget cleanup — still runs after dispose returns.
    _presence.leaveChat(_convId);
    super.dispose();
  }

  /// Called when app comes back from background while this screen is shown.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Restore in-chat status when user returns to app mid-chat.
        _enterChat();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Clear in-chat presence when app goes to background.
        _presence.leaveChat(_convId);
      default:
        break;
    }
  }

  Future<void> _enterChat() async {
    await ref.read(messageRepositoryProvider).markConversationRead(_convId);
    await _presence.enterChat(_convId);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    await ref.read(messageRepositoryProvider)
        .loadMoreMessages(_convId, _currentOffset);
    _currentOffset += 40;
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _retrySingle(Message msg) async {
    if (msg.decryptedBody == null) return;
    // Retry with same localId — no duplicate
    await ref.read(messageRepositoryProvider).retryMessage(msg.localId);
  }

  @override
  Widget build(BuildContext context) {
    final conv          = widget.conversation;
    final messagesAsync = ref.watch(messagesProvider(_convId));
    final otherUserId   = conv.otherUser?.id;

    // ── Issue 1 fix: mark as read whenever messages update ─────
    ref.listen(messagesProvider(_convId), (_, next) {
      if (next.hasValue && next.value!.isNotEmpty) {
        ref.read(messageRepositoryProvider).markConversationRead(_convId);
      }
    });

    // ── Presence stream ────────────────────────────────────────
    final presence = otherUserId != null
        ? ref.watch(_presenceStreamProvider(
              (userId: otherUserId, convId: _convId)))
              .asData?.value
        : null;

    return PopScope(
      // Intercept back button so we can clear presence BEFORE the pop.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _presence.leaveChat(_convId).then((_) {
          if (context.mounted) Navigator.of(context).pop();
        });
      },
      child: Scaffold(
        appBar: _buildAppBar(context, conv, presence),
        body: Column(
          children: [
            if (_loadingMore)
              const LinearProgressIndicator(minHeight: 2),

            Expanded(
              child: messagesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (messages) => messages.isEmpty
                    ? Center(
                        child: Text(
                          'Say hello to ${conv.displayName}! 👋',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.4),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller:  _scrollController,
                        reverse:     true,
                        padding:     const EdgeInsets.symmetric(vertical: 8),
                        itemCount:   messages.length,
                        itemBuilder: (context, i) {
                          final msg = messages[i];
                          return _MessageItem(
                            message: msg,
                            onRetry: msg.isFailed
                                ? () => _retrySingle(msg)
                                : null,
                          );
                        },
                      ),
              ),
            ),

            MessageInput(
              isLoading: false,
              onTyping: () => _presence.onTyping(_convId),
              onSend:   (text) => ref
                  .read(sendMessageProvider.notifier)
                  .send(conversationId: _convId, text: text),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(
    BuildContext context,
    Conversation conv,
    OtherUserPresence? presence,
  ) {
    return AppBar(
      titleSpacing: 0,
      // Let PopScope handle back; keep the back button visible.
      leading: BackButton(
        onPressed: () {
          _presence.leaveChat(_convId).then((_) {
            if (context.mounted) Navigator.of(context).pop();
          });
        },
      ),
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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  conv.displayName,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (presence != null)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Row(
                      key: ValueKey(presence.statusLabel),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (presence.isTyping)
                          _TypingDots()
                        else if (presence.showDot)
                          Container(
                            width: 6, height: 6,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: const BoxDecoration(
                              color:  AppColors.success,
                              shape:  BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: 4),
                        Text(
                          presence.statusLabel,
                          style: TextStyle(
                            fontSize: 12,
                            color: presence.showDot
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
          ),
        ],
      ),
    );
  }
}

// ── Providers ──────────────────────────────────────────────────────────────

final _presenceStreamProvider = StreamProvider.autoDispose
    .family<OtherUserPresence, ({String userId, String convId})>(
        (ref, args) {
  return ref
      .read(presenceServiceProvider)
      .watchPresence(args.userId, args.convId);
});

// ── Message item ───────────────────────────────────────────────────────────

class _MessageItem extends ConsumerWidget {
  const _MessageItem({required this.message, this.onRetry});
  final Message       message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId   = ref.watch(currentUserIdProvider).asData?.value ?? '';
    final isMine = message.senderId == myId;
    return Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        MessageBubble(message: message, isMine: isMine),
        if (isMine && message.isFailed && onRetry != null)
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 4),
            child: GestureDetector(
              onTap: onRetry,
              child: const Text(
                '⚠ Tap to retry',
                style: TextStyle(fontSize: 11, color: AppColors.error),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Typing animation ───────────────────────────────────────────────────────

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t       = (_ctrl.value - i / 3).clamp(0.0, 1.0);
          final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.3, 1.0);
          return Container(
            width: 5, height: 5,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: opacity),
              shape: BoxShape.circle,
            ),
          );
        }),
      ),
    );
  }
}
