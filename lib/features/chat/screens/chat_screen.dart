import 'package:cached_network_image/cached_network_image.dart';
import '../../../services/media_upload_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../../services/presence_service.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/pinned_message_banner.dart';
import '../../media/screens/media_docs_screen.dart';
import '../../groups/screens/group_settings_screen.dart';

// ── Sealed list item ──────────────────────────────────────────────────────

sealed class _ChatItem {}

class _MsgItem extends _ChatItem {
  _MsgItem(this.msg, this.key);
  final Message   msg;
  final GlobalKey key;
}

class _DateItem extends _ChatItem {
  _DateItem(this.date);
  final DateTime date;
}

// ── Chat screen ───────────────────────────────────────────────────────────

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversation});
  final Conversation conversation;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final _scrollCtrl   = ScrollController();
  final _searchCtrl   = TextEditingController();
  bool  _loadingMore  = false;
  int   _offset       = 40;
  bool  _searchActive = false;
  String _searchQuery = '';

  // Match navigation
  List<int>   _matchItemIndices = []; // indices into _items (the flat list)
  int         _matchIndex       = 0;

  // Keys per message for scroll-to
  final Map<String, GlobalKey> _msgKeys = {};

  // Cached items list so scroll helpers can access it
  List<_ChatItem> _items = [];

  ProviderSubscription<AsyncValue<List<Message>>>? _markReadSub;

  PresenceService get _pres => ref.read(presenceServiceProvider);
  String          get _cid  => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enter();
      if (!mounted) return;
      _markReadSub = ref.listenManual(
        messagesProvider(_cid),
        (_, next) {
          if (!mounted) return;
          if (next.hasValue && next.value!.isNotEmpty) {
            ref.read(messageRepositoryProvider).markConversationRead(_cid);
          }
        },
      );
    });
  }

  @override
  void dispose() {
    _markReadSub?.close();
    WidgetsBinding.instance.removeObserver(this);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _pres.leaveChat(_cid);
    ref.read(replyProvider.notifier).state = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _enter();
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      _pres.leaveChat(_cid);
    }
  }

  Future<void> _enter() async {
    await ref.read(messageRepositoryProvider).markConversationRead(_cid);
    await _pres.enterChat(_cid);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    await ref.read(messageRepositoryProvider).loadMoreMessages(_cid, _offset);
    _offset += 40;
    if (mounted) setState(() => _loadingMore = false);
  }

  // ── Build flat item list with date separators ─────────────────────────

  List<_ChatItem> _buildItems(List<Message> messages) {
    final items = <_ChatItem>[];
    for (int i = 0; i < messages.length; i++) {
      final msg  = messages[i];
      final key  = _msgKeys.putIfAbsent(msg.localId, () => GlobalKey());
      items.add(_MsgItem(msg, key));

      final next = i + 1 < messages.length ? messages[i + 1] : null;
      if (next == null || !_sameDay(msg.createdAt, next.createdAt)) {
        items.add(_DateItem(msg.createdAt));
      }
    }
    _items = items;
    return items;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ── Search helpers ────────────────────────────────────────────────────

  void _onSearchChanged(String q, List<Message> messages) {
    setState(() {
      _searchQuery = q;
      _matchIndex  = 0;
    });
    if (q.isNotEmpty) {
      // Build a list of flat-item indices for matching messages
      _matchItemIndices = [];
      for (int i = 0; i < _items.length; i++) {
        final item = _items[i];
        if (item is _MsgItem &&
            (item.msg.decryptedBody ?? '')
                .toLowerCase()
                .contains(q.toLowerCase())) {
          _matchItemIndices.add(i);
        }
      }
      _scrollToMatch(0);
    } else {
      _matchItemIndices = [];
    }
  }

  /// Scrolls the reversed ListView to bring item at [flatIndex] into view.
  /// Because the list is reversed, index 0 = bottom. The scroll offset for
  /// item at [flatIndex] from the bottom is:
  ///   offset = flatIndex * estimatedHeight
  void _scrollToItemIndex(int flatIndex) {
    if (!_scrollCtrl.hasClients) return;
    final maxExt  = _scrollCtrl.position.maxScrollExtent;
    final total   = _items.length;
    // In a reversed list, item 0 is at the bottom (offset 0).
    // Item at flatIndex is approximately:
    final target = (flatIndex / total.clamp(1, total)) * maxExt;
    _scrollCtrl.animateTo(
      target.clamp(0.0, maxExt),
      duration: const Duration(milliseconds: 400),
      curve:    Curves.easeInOut,
    );
  }

  void _scrollToMatch(int index) {
    if (_matchItemIndices.isEmpty || index < 0 || index >= _matchItemIndices.length) return;
    setState(() => _matchIndex = index);
    final flatIndex = _matchItemIndices[index];
    // Try the fast path first (widget already rendered)
    final item = _items[flatIndex];
    if (item is _MsgItem) {
      final ctx = item.key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration:  const Duration(milliseconds: 350),
          curve:     Curves.easeInOut,
        );
        return;
      }
    }
    // Widget not yet rendered — scroll by estimated offset
    _scrollToItemIndex(flatIndex);
    // After scroll settles, try ensureVisible again
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final item2 = _items[flatIndex];
      if (item2 is _MsgItem) {
        final ctx2 = item2.key.currentContext;
        if (ctx2 != null) {
          Scrollable.ensureVisible(
            ctx2,
            alignment: 0.5,
            duration:  const Duration(milliseconds: 200),
            curve:     Curves.easeInOut,
          );
        }
      }
    });
  }

  void _nextMatch() => _scrollToMatch(
      (_matchIndex + 1) % (_matchItemIndices.isEmpty ? 1 : _matchItemIndices.length));

  void _prevMatch() => _scrollToMatch(
      (_matchIndex - 1 + (_matchItemIndices.isEmpty ? 1 : _matchItemIndices.length)) %
          (_matchItemIndices.isEmpty ? 1 : _matchItemIndices.length));

  /// Scrolls to [msg] whether it is currently rendered or not.
  /// Fast path: widget in tree → ensureVisible.
  /// Slow path: estimate offset by item index, then retry ensureVisible
  /// once the ListView has rebuilt with the target item rendered.
  void _scrollToMessage(Message msg) {
    // Find the flat-item index for this message
    int flatIndex = -1;
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item is _MsgItem && item.msg.localId == msg.localId) {
        flatIndex = i;
        break;
      }
    }
    if (flatIndex < 0) return;

    // Fast path — widget already rendered
    final item = _items[flatIndex];
    if (item is _MsgItem) {
      final ctx = item.key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration:  const Duration(milliseconds: 350),
          curve:     Curves.easeInOut,
        );
        return;
      }
    }

    // Slow path — scroll by proportional offset then retry
    _scrollToItemIndex(flatIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final item2 = _items[flatIndex];
      if (item2 is _MsgItem) {
        final ctx2 = item2.key.currentContext;
        if (ctx2 != null) {
          Scrollable.ensureVisible(
            ctx2,
            alignment: 0.5,
            duration:  const Duration(milliseconds: 200),
            curve:     Curves.easeInOut,
          );
        }
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final conv           = widget.conversation;
    final messagesAsync  = ref.watch(messagesProvider(_cid));
    final otherUserId    = conv.otherUser?.id;
    final presence       = otherUserId != null
        ? ref.watch(_presenceProvider(
              (userId: otherUserId, convId: _cid)))
              .asData?.value
        : null;

    final myId    = ref.watch(currentUserIdProvider).asData?.value ?? '';
    final messages = messagesAsync.asData?.value ?? [];
    final items    = _buildItems(messages);

    // ── Group-specific: canSendMessages ───────────────────────
    bool canSend = true;
    if (conv.isGroup && conv.onlyAdminsCanMessage) {
      final myRole = ref.watch(_myRoleProvider((
        convId: _cid,
        userId: myId,
      ))).asData?.value;
      canSend = myRole == 'admin';
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _pres.leaveChat(_cid).then((_) {
          if (context.mounted) Navigator.of(context).pop();
        });
      },
      child: Scaffold(
        appBar: _searchActive
            ? _searchBar(context, messages)
            : _mainBar(context, conv, presence),
        body: Column(
          children: [
            if (_loadingMore)
              const LinearProgressIndicator(minHeight: 2),

            if (!_searchActive)
              PinnedMessageBanner(
                conversationId: _cid,
                onTap: _scrollToMessage,
              ),

            Expanded(
              child: messagesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error:   (e, _) => Center(child: Text('Error: $e')),
                data: (_) => items.isEmpty
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
                        controller:  _scrollCtrl,
                        reverse:     true,
                        padding:     const EdgeInsets.symmetric(vertical: 8),
                        itemCount:   items.length,
                        itemBuilder: (_, i) {
                          final item = items[i];

                          if (item is _DateItem) {
                            return _DateSeparator(date: item.date);
                          }

                          final msgItem   = item as _MsgItem;
                          final msg       = msgItem.msg;
                          final isMine    = msg.senderId == myId;
                          final isMatch   = _searchQuery.isNotEmpty &&
                              (msg.decryptedBody ?? '')
                                  .toLowerCase()
                                  .contains(_searchQuery.toLowerCase());
                          final isCurrent = _matchItemIndices.isNotEmpty &&
                              _matchIndex < _matchItemIndices.length &&
                              _items[_matchItemIndices[_matchIndex]] == item;

                          return KeyedSubtree(
                            key: msgItem.key,
                            child: _HighlightWrapper(
                              active:  isMatch,
                              current: isCurrent,
                              child:   MessageBubble(
                                message:    msg,
                                isMine:     isMine,
                                isGroup:    conv.isGroup,
                                senderName: conv.otherUser?.displayName
                                    ?? 'Unknown',
                                onReply: () => ref
                                    .read(replyProvider.notifier)
                                    .state = msg,
                                onReplyTap: msg.replyToId != null
                                    ? () {
                                        final orig = messages.where(
                                          (m) => m.serverId == msg.replyToId,
                                        ).firstOrNull;
                                        if (orig != null) {
                                          _scrollToMessage(orig);
                                        }
                                      }
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),

            if (!_searchActive)
              MessageInput(
                conversationId:   _cid,
                isLoading:        false,
                canSendMessages:  canSend,
                onTyping:         () => _pres.onTyping(_cid),
                onSend:           (text) {
                  final reply = ref.read(replyProvider);
                  String? replyPreview;
                  if (reply != null) {
                    replyPreview = switch (reply.type) {
                      'image' => '📷 Photo',
                      'voice' => '🎤 Voice message',
                      _       => reply.decryptedBody != null && reply.decryptedBody!.isNotEmpty
                          ? reply.decryptedBody!.length > 60
                              ? '${reply.decryptedBody!.substring(0, 60)}…'
                              : reply.decryptedBody!
                          : null,
                    };
                  }
                  ref.read(sendMessageProvider.notifier).send(
                    conversationId: _cid,
                    text:           text,
                    replyToLocalId: reply?.localId,
                    replyPreview:   replyPreview,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── App bars ──────────────────────────────────────────────────────────

  AppBar _mainBar(
    BuildContext context,
    Conversation conv,
    OtherUserPresence? presence,
  ) {
    // Group member count subtitle
    final memberCount = conv.memberCount
        ?? ref.watch(_memberCountProvider(_cid)).asData?.value
        ?? 0;

    return AppBar(
        titleSpacing: 0,
        leading: BackButton(onPressed: () =>
            _pres.leaveChat(_cid).then((_) {
              if (context.mounted) Navigator.of(context).pop();
            })),
        title: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primaryLight,
            backgroundImage: conv.avatarUrl != null
                ? CachedNetworkImageProvider(conv.avatarUrl!)
                : null,
            child: conv.avatarUrl == null
                ? Text(conv.displayName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700,
                      fontSize: 14))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize:       MainAxisSize.min,
              children: [
                Text(conv.displayName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                if (conv.isGroup)
                  Text(
                    '$memberCount member${memberCount == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                  )
                else if (presence != null)
                  Text(
                    presence.statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: presence.showDot
                          ? AppColors.success
                          : Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ]),
        actions: [
          IconButton(
            icon:      const Icon(Icons.search),
            onPressed: () => setState(() => _searchActive = true),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'starred') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StarredMessagesScreen(
                    conversationId: _cid,
                    onJump:         _scrollToMessage,
                  ),
                ));
              } else if (v == 'group_info') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GroupSettingsScreen(conversation: conv),
                ));
              } else if (v == 'disappearing') {
                _disappearingDialog(context);
              } else if (v == 'media_docs') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => MediaDocsScreen(conversationId: _cid),
                ));
              }
            },
            itemBuilder: (_) => [
              if (!conv.isGroup)
                const PopupMenuItem(value: 'starred',      child: Text('Starred Messages'))
              else
                const PopupMenuItem(value: 'group_info',   child: Text('Group Info')),
              const PopupMenuItem(value: 'disappearing', child: Text('Disappearing Messages')),
              const PopupMenuItem(value: 'media_docs',   child: Text('Media & Docs')),
            ],
          ),
        ],
      );
  }

  AppBar _searchBar(BuildContext context, List<Message> messages) =>
      AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() {
            _searchActive       = false;
            _searchQuery        = '';
            _matchItemIndices   = [];
            _searchCtrl.clear();
          }),
        ),
        title: TextField(
          controller: _searchCtrl,
          autofocus:  true,
          decoration: const InputDecoration(
            hintText: 'Search in conversation…',
            border:   InputBorder.none,
          ),
          onChanged: (q) => _onSearchChanged(q, messages),
        ),
        actions: [
          if (_matchItemIndices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child:   Text(
                '${_matchIndex + 1}/${_matchItemIndices.length}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          IconButton(
            icon:      const Icon(Icons.keyboard_arrow_up),
            onPressed: _matchItemIndices.isNotEmpty ? _prevMatch : null,
          ),
          IconButton(
            icon:      const Icon(Icons.keyboard_arrow_down),
            onPressed: _matchItemIndices.isNotEmpty ? _nextMatch : null,
          ),
        ],
      );

  void _disappearingDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title:   const Text('Disappearing Messages'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final opt in [
              ('Off',      0),
              ('24 hours', 86400),
              ('7 days',   604800),
              ('30 days',  2592000),
            ])
              ListTile(
                title:  Text(opt.$1),
                onTap: () {
                  ref.read(messageRepositoryProvider)
                      .setDisappearingDuration(_cid, opt.$2);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Disappearing: ${opt.$1}')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ── Date separator ────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});
  final DateTime date;

  String _label() {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d     = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMMM d, y').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin:  const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _label(),
          style: TextStyle(
            fontSize: 11,
            color:    Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

// ── Search highlight wrapper ───────────────────────────────────────────────

class _HighlightWrapper extends StatelessWidget {
  const _HighlightWrapper({
    required this.child,
    required this.active,
    required this.current,
  });
  final Widget child;
  final bool   active;
  final bool   current;

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: current
          ? AppColors.primary.withValues(alpha: 0.12)
          : AppColors.primary.withValues(alpha: 0.04),
      child: child,
    );
  }
}

// ── Starred messages screen ───────────────────────────────────────────────

class StarredMessagesScreen extends ConsumerWidget {
  const StarredMessagesScreen({
    super.key,
    required this.conversationId,
    this.onJump,
  });
  final String                 conversationId;
  final void Function(Message)? onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Starred Messages')),
      body: FutureBuilder<List<Message>>(
        future: ref.read(messageRepositoryProvider)
            .getStarredMessages(conversationId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final msgs = snap.data!;
          if (msgs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_outline, size: 64,
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.2)),
                  const SizedBox(height: 12),
                  Text('No starred messages',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.4))),
                ],
              ),
            );
          }
          return ListView.separated(
            padding:         const EdgeInsets.all(16),
            itemCount:       msgs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final msg = msgs[i];
              return _StarredCard(
                message: msg,
                onTap: onJump != null
                    ? () {
                        Navigator.pop(context);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          onJump!(msg);
                        });
                      }
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}

class _StarredCard extends ConsumerStatefulWidget {
  const _StarredCard({required this.message, this.onTap});
  final Message       message;
  final VoidCallback? onTap;

  @override
  ConsumerState<_StarredCard> createState() => _StarredCardState();
}

class _StarredCardState extends ConsumerState<_StarredCard> {
  String? _thumbUrl;
  bool _loadingImage = true;

  @override
  void initState() {
    super.initState();
    if (widget.message.type == 'image' && widget.message.serverId != null) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final urls = await ref
        .read(mediaUploadServiceProvider)
        .getImageUrls(widget.message.serverId!);
    if (mounted) {
      setState(() {
        _thumbUrl = urls?['thumb'];
        _loadingImage = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId   = ref.watch(currentUserIdProvider).asData?.value ?? '';
    final isMine = widget.message.senderId == myId;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset:     const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.star, color: AppColors.warning, size: 14),
              const SizedBox(width: 6),
              Text(
                isMine ? 'You' : 'Contact',
                style: const TextStyle(
                  fontSize:   12,
                  fontWeight: FontWeight.w600,
                  color:      AppColors.primary,
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM d, HH:mm')
                    .format(widget.message.createdAt.toLocal()),
                style: TextStyle(
                  fontSize: 11,
                  color:    Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.5),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            if (widget.message.type == 'image' && widget.message.serverId != null)
              _buildImageContent()
            else
              Text(
                widget.message.decryptedBody ?? '🔒 Encrypted',
                style: const TextStyle(fontSize: 15),
              ),
            if (widget.onTap != null) ...[
              const SizedBox(height: 8),
              Text(
                'Tap to jump to message',
                style: TextStyle(
                  fontSize: 11,
                  color:    Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.35),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    if (_loadingImage) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_thumbUrl == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: _thumbUrl!,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          height: 200,
          color: Colors.grey.shade300,
        ),
        errorWidget: (_, __, ___) => const SizedBox(
          height: 120,
          child: Center(child: Icon(Icons.broken_image, color: Colors.grey)),
        ),
      ),
    );
  }
}

// ── Presence stream provider ──────────────────────────────────────────────

final _presenceProvider = StreamProvider.autoDispose
    .family<OtherUserPresence, ({String userId, String convId})>(
        (ref, args) {
  return ref.read(presenceServiceProvider).watchPresence(args.userId, args.convId);
});

// ── Group member count provider ───────────────────────────────────────────

final _memberCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, convId) async {
  final db      = ref.read(appDatabaseProvider);
  final members = await db.conversationsDao.getMembersForConversation(convId);
  return members.length;
});

// ── My role in a conversation ─────────────────────────────────────────────

final _myRoleProvider = FutureProvider.autoDispose
    .family<String?, ({String convId, String userId})>((ref, args) async {
  final db      = ref.read(appDatabaseProvider);
  final members = await db.conversationsDao.getMembersForConversation(args.convId);
  final mine    = members.where((m) => m.userId == args.userId).firstOrNull;
  return mine?.role;
});
