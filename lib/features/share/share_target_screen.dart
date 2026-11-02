// C18 (12.1 D1–D12): the "Send to" picker for shares from other apps. One
// chat per share; the copy into app storage starts only after the tap.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/busy_spinner.dart';
import '../../core/widgets/chat_tile.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/page_app_bar.dart';
import '../../core/widgets/search_field.dart';
import '../../core/widgets/section_header.dart';
import '../../domain/entities/conversation.dart';
import '../../infrastructure/repositories/message_repository_impl.dart';
import '../../services/share_in_service.dart';
import '../auth/providers/auth_provider.dart';
import '../chat/message_offline_policy.dart' show kUploadTooBig;
import '../chat/screens/chat_screen.dart' show canSendIn;
import '../home/providers/conversations_provider.dart';
import 'share_payload.dart';

/// G1: reduced motion pushes with no animation. Pops with the chosen chat,
/// or null when the share is dropped.
Route<Conversation> shareTargetRoute(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? PageRouteBuilder<Conversation>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const ShareTargetScreen(),
      )
    : MaterialPageRoute<Conversation>(
        builder: (_) => const ShareTargetScreen(),
      );

class ShareTargetScreen extends ConsumerStatefulWidget {
  const ShareTargetScreen({super.key});

  @override
  ConsumerState<ShareTargetScreen> createState() => _ShareTargetScreenState();
}

class _ShareTargetScreenState extends ConsumerState<ShareTargetScreen> {
  String _query = '';

  /// Items being copied; 0 = no scrim.
  int _copyTotal = 0;
  int _copyIndex = 0;

  /// One tap at a time, from the send check to the hand-off.
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _arrived(ref.read(pendingShareProvider));
    });
  }

  // C2 toast for the share on screen; a newer share with nothing usable
  // closes the picker (B6, B7).
  void _arrived(ShareInPayload? share) {
    if (share == null) return;
    final plan = planShare(share);
    if (plan.isEmpty) {
      showToast(
        context,
        plan.tooBig > 0 ? kUploadTooBig : kShareUnreadable,
        error: true,
      );
      Navigator.of(context).pop();
    } else if (plan.overCap) {
      showToast(context, 'Only the first 20 were added.');
    }
  }

  Future<bool> _canSend(Conversation conv) async {
    if (!conv.isGroup) return true;
    final repo = ref.read(messageRepositoryProvider);
    final auth = ref.read(authProvider).valueOrNull;
    final myId = auth is AuthAuthenticated ? auth.user.id : '';
    try {
      const wait = Duration(seconds: 3);
      final members = await repo.watchGroupMembers(conv.id).first.timeout(wait);
      final keyReady = await repo.hasUsableKey(conv.id).timeout(wait);
      final me = members.where((m) => m.id == myId).firstOrNull;
      return canSendIn(conv, myRole: me?.groupRole, keyReady: keyReady);
    } catch (e) {
      debugPrint('[Share] send check failed: $e');
      return true; // the chat's composer checks again (E1)
    }
  }

  Future<void> _pick(Conversation conv) async {
    if (_picking) return;
    _picking = true;
    try {
      await _pickOnce(conv);
    } finally {
      _picking = false;
    }
  }

  Future<void> _pickOnce(Conversation conv) async {
    final share = ref.read(pendingShareProvider);
    if (share == null) return;
    if (!await _canSend(conv)) {
      if (mounted) {
        showToast(context, "You can't send messages in this chat.", error: true);
      }
      return;
    }
    if (!mounted) return;

    final plan = planShare(share);
    final files = <({String path, SharedKind kind, String mime})>[];
    var tooBig = plan.tooBig;
    var unreadable = 0;
    if (plan.items.isNotEmpty) {
      setState(() {
        _copyTotal = plan.items.length;
        _copyIndex = 0;
      });
    }
    for (var i = 0; i < plan.items.length; i++) {
      // Closed (back / ✕): the service deletes the copies. Replaced (B6): we do.
      if (!mounted) return;
      if (!identical(ref.read(pendingShareProvider), share)) {
        setState(() => _copyTotal = 0);
        await clearSharedFiles();
        return;
      }
      setState(() => _copyIndex = i);
      final item = plan.items[i];
      try {
        final copied = await shareChannel.invokeMethod<String>('copyShared', {
          'uri': item.uri,
          'name': item.name,
          'maxBytes': shareMaxBytes,
        });
        if (copied == null) {
          unreadable++;
        } else {
          files.add((path: copied, kind: item.kind, mime: item.mime));
        }
      } on PlatformException catch (e) {
        e.code == 'too_big' ? tooBig++ : unreadable++;
      } catch (e) {
        debugPrint('[Share] copy failed: $e');
        unreadable++;
      }
    }
    if (!mounted) return;
    if (!identical(ref.read(pendingShareProvider), share)) {
      setState(() => _copyTotal = 0);
      await clearSharedFiles();
      return;
    }

    if (files.isEmpty && !share.hasText) {
      setState(() => _copyTotal = 0);
      await clearSharedFiles();
      if (!mounted) return;
      showToast(
        context,
        unreadable == 0 ? kUploadTooBig : kShareUnreadable,
        error: true,
      );
      return; // the picker stays (D8)
    }
    if (tooBig > 0) {
      showToast(context, tooBigLeftOut(tooBig), error: true);
    } else if (unreadable > 0) {
      showToast(context, unreadableLeftOut(unreadable), error: true);
    }
    ref.read(chatShareProvider(conv.id).notifier).state = ReadyShare(
      chatName: conv.displayName,
      files: files,
      text: share.hasText ? share.text : null,
    );
    ref.read(pendingShareProvider.notifier).state = null;
    Navigator.of(context).pop(conv);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pendingShareProvider, (_, next) => _arrived(next));
    final t = context.t;
    final share = ref.watch(pendingShareProvider);
    final plan = share == null ? null : planShare(share);
    final summary = plan == null ? '' : shareSummary(plan.items, plan.text);
    final convsAsync = ref.watch(conversationsProvider);
    // Same rows as home's Chats section: unsynced direct chats are left out.
    final convs = (convsAsync.valueOrNull ?? const <Conversation>[])
        .where((c) => !(c.type == 'direct' && c.otherUser == null))
        .toList();
    final query = _query.trim().toLowerCase();
    final shown = query.isEmpty
        ? convs
        : convs
              .where((c) => c.displayName.toLowerCase().contains(query))
              .toList();
    final summaryHeight = MediaQuery.textScalerOf(context).scale(18) + 6;

    final Widget list;
    if (!convsAsync.hasValue) {
      list = const SizedBox.shrink();
    } else if (convs.isEmpty) {
      list = const EmptyState(
        title: 'No chats yet',
        subtitle: 'Add a friend first, then share again.',
        withMascot: false,
      );
    } else if (shown.isEmpty) {
      list = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          'No chats match ‘${_query.trim()}’.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: t.inkFaint),
        ),
      );
    } else {
      list = ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const SectionHeader('Chats'),
          for (final c in shown)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: ChatTile(
                key: ValueKey('share-target-${c.id}'),
                title: c.displayName,
                subtitle: c.isGroup
                    ? (c.memberCount == 1
                          ? '1 member'
                          : '${c.memberCount} members')
                    : '',
                avatarUrl: c.avatarUrl,
                isGroup: c.isGroup,
                isPinned: c.isPinned,
                onTap: () => _pick(c),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: t.bg,
      appBar: pageAppBar(
        context,
        'Send to',
        leading: IconButton(
          icon: Icon(Icons.close, color: t.ink),
          tooltip: 'Cancel sharing',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(summaryHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(72, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 18 / 13, color: t.inkSoft),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SearchField(
                  hint: 'Search chats',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(child: list),
            ],
          ),
          if (_copyTotal > 0)
            Positioned.fill(
              child: ColoredBox(
                color: t.bg.withValues(alpha: 0.92),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BusySpinner(),
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _copyTotal == 1
                                ? 'Opening…'
                                : 'Opening ${_copyIndex + 1} of $_copyTotal',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: t.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
