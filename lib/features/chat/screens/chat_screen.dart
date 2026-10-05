import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../../services/presence_service.dart';
import '../../../services/fcm_service.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/pinned_message_banner.dart';
import '../../media/screens/media_docs_screen.dart';
import '../../groups/screens/group_settings_screen.dart';
import '../../starred_messages/screens/starred_messages_screen.dart';

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

  final Map<String, String> _senderNameCache = {};

  ProviderSubscription<AsyncValue<List<Message>>>? _markReadSub;

  // Collapses the rapid messages-stream burst (rowCount 1→N during a backfill,
  // plus the per-message re-emits) into a SINGLE server round-trip. Without
  // this, every emit called `markConversationRead` — which writes a `read_at`
  // receipt for each message → fired the receipts subscription → which
  // re-ran reconcile → receipts flood. The open chat kept "running" forever.
  Timer? _markReadDebounce;

  PresenceService get _pres => ref.read(presenceServiceProvider);
  String          get _cid  => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    FcmService.activeConversationId = _cid;
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enter();
      if (!mounted) return;
      _markReadSub = ref.listenManual(
        messagesProvider(_cid),
        (_, next) {
          if (!mounted) return;
          if (!next.hasValue || next.value!.isEmpty) return;
          // Debounce: reset the clock on every emit; only the LAST emit (after
          // ~1.5s of quiet) actually marks read. This collapses an initial
          // 30-message backfill from ~30 server round-trips into 1.
          _markReadDebounce?.cancel();
          _markReadDebounce = Timer(const Duration(milliseconds: 1500), () {
            if (mounted) {
              ref.read(messageRepositoryProvider).markConversationRead(_cid);
            }
          });
        },
      );
    });
  }

  @override
  void dispose() {
    if (FcmService.activeConversationId == _cid) {
      FcmService.activeConversationId = null;
    }
    _markReadSub?.close();
    _markReadDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _pres.leaveChat(_cid);
    ref.read(replyProvider.notifier).state = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      FcmService.activeConversationId = _cid;
      _enter();
    }
    if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
      FcmService.activeConversationId = null;
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
  int _findFlatIndex(Message msg) {
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      // Match on localId OR serverId — starred-screen messages are
      // reconstructed from the server and their localId may actually be
      // the server id.
      if (item is _MsgItem &&
          (item.msg.localId == msg.localId ||
              (msg.serverId != null && item.msg.serverId == msg.serverId) ||
              item.msg.serverId == msg.localId)) {
        return i;
      }
    }
    return -1;
  }

  void _scrollToFlatIndex(int flatIndex) {
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
    _scrollToItemIndex(flatIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The list can shrink between frames (disappearing-message expiry)
      // — never index past the end (review minor).
      if (flatIndex >= _items.length) return;
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

  /// Unified jump for search/star/reply/pin. If the target is not in the
  /// loaded window, fetch it from the server, wait for the stream to emit
  /// it, then scroll precisely. Never bails silently (B3).
  Future<void> _jumpToMessage(Message msg) async {
    var flatIndex = _findFlatIndex(msg);
    if (flatIndex < 0 && msg.serverId != null) {
      try {
        await ref
            .read(messageRepositoryProvider)
            .fetchAndCacheSingleMessage(msg.serverId!, _cid);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Message unavailable: $e')));
        }
        return;
      }
      for (var i = 0; i < 20 && flatIndex < 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
        flatIndex = _findFlatIndex(msg);
      }
    }
    if (flatIndex < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Message not found in this chat')));
      }
      return;
    }
    _scrollToFlatIndex(flatIndex);
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final convAsync      = ref.watch(conversationStreamProvider(_cid));
    final conv           = convAsync.asData?.value ?? widget.conversation;
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

    // ── Group-specific reactive state ─────────────────────────
    final membersAsync = ref.watch(groupMembersProvider(_cid));
    final members = membersAsync.asData?.value ?? [];
    final myMember = members.where((m) => m.id == myId).firstOrNull;
    final isMeAdmin = myMember?.groupRole == 'admin';
    final isLeft = myMember?.groupRole == 'left';
    final memberCount = conv.isGroup ? members.where((m) => m.groupRole != 'left').length : 0;

    // Group-key readiness: a just-joined member holds no key until an admin
    // device rotates. Keyless -> composer off + explanatory banner (spec D3).
    final keyReady = !conv.isGroup
        ? true
        : (ref.watch(groupKeyReadyProvider(_cid)).asData?.value ?? false);

    final canSend = !conv.isGroup
        ? true
        : (isLeft || !keyReady
            ? false
            : (!conv.onlyAdminsCanMessage || isMeAdmin));

    final restrictionMessage = isLeft
        ? "You can't send messages to this group because you're no longer a member."
        : (!keyReady
            ? 'Waiting for a group admin to come online and share the group key…'
            : null);

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
            : _mainBar(context, conv, presence, memberCount),
        body: Column(
          children: [
            if (_loadingMore)
              const LinearProgressIndicator(minHeight: 2),

            if (!_searchActive)
              PinnedMessageBanner(
                conversationId: _cid,
                onTap: (m) => unawaited(_jumpToMessage(m)),
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

                          if (conv.isGroup && !isMine && !_senderNameCache.containsKey(msg.senderId)) {
                            ref.read(appDatabaseProvider).usersDao.getUserById(msg.senderId).then((u) {
                              if (u != null && mounted) {
                                setState(() => _senderNameCache[msg.senderId] = u.displayName);
                              }
                            });
                          }

                          final isMatch   = _searchQuery.isNotEmpty &&
                              (msg.decryptedBody ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
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
                                senderName: conv.isGroup
                                    ? (_senderNameCache[msg.senderId] ?? 'Unknown')
                                    : (conv.otherUser?.displayName ?? 'Unknown'),
                                onReply: () => ref
                                    .read(replyProvider.notifier)
                                    .state = msg,
                                onReplyTap: msg.replyToId != null
                                    ? () {
                                        final orig = messages.where(
                                          (m) => m.serverId == msg.replyToId,
                                        ).firstOrNull;
                                        if (orig != null) {
                                          unawaited(_jumpToMessage(orig));
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
                conversationId:     _cid,
                isLoading:          false,
                canSendMessages:    canSend,
                restrictionMessage: restrictionMessage,
                onTyping:           () => _pres.onTyping(_cid),
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
    int memberCount,
  ) {
    return AppBar(
        titleSpacing: 0,
        leading: BackButton(onPressed: () =>
            _pres.leaveChat(_cid).then((_) {
              if (context.mounted) Navigator.of(context).pop();
            })),
        title: Row(children: [
          if (!conv.isGroup)
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
            )
          else
            Stack(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primaryLight,
                  backgroundImage: conv.iconUrl != null
                      ? CachedNetworkImageProvider(conv.iconUrl!)
                      : null,
                  child: conv.iconUrl == null
                      ? Text(
                          conv.displayName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primary, fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.group, size: 10, color: AppColors.primary),
                  ),
                ),
              ],
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
                    onJump:         (m) => unawaited(_jumpToMessage(m)),
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
              const PopupMenuItem(value: 'media_docs',   child: Text('Media & Docs')),
              const PopupMenuItem(value: 'starred',      child: Text('Starred Messages')),
              if (conv.isGroup)
                const PopupMenuItem(value: 'group_info',  child: Text('Group Info')),
              const PopupMenuItem(value: 'disappearing', child: Text('Disappearing Messages')),
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

// ── Presence stream provider ──────────────────────────────────────────────

final _presenceProvider = StreamProvider.autoDispose
    .family<OtherUserPresence, ({String userId, String convId})>(
        (ref, args) {
  return ref.read(presenceServiceProvider).watchPresence(args.userId, args.convId);
});

