import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../media/album_layout.dart';
import '../../media/screens/media_viewer_screen.dart';
import '../chat_run_grouping.dart' show albumLabel;
import '../message_offline_policy.dart';
import '../providers/album_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/upload_progress_provider.dart';
import '../widgets/album_bubble.dart' show albumTileLabel;
import '../widgets/image_message_bubble.dart';
import '../widgets/media_retry.dart';
import '../widgets/selection_bar.dart';
import '../widgets/video_message_bubble.dart';

/// 12.5 E1–E4c: the collage. It watches the album's rows, so a late item
/// appears and a deleted one leaves; with one row left it pops to the chat.
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({
    super.key,
    required this.conversationId,
    required this.albumId,
    required this.senderName,
    required this.timestamp,
    this.initialIndex = 0,
  });

  final String conversationId;
  final String albumId;
  final String senderName;
  final DateTime timestamp;

  /// The tile to bring into view (D5: the one tapped in the bubble).
  final int initialIndex;

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  final _scroll = ScrollController();
  final Set<String> _selected = <String>{};
  bool _selecting = false;
  bool _leaving = false;
  bool _scrolled = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _popToChat() {
    if (!mounted) return;
    // Remove this route, not the top one: the viewer may be open above it.
    final route = ModalRoute.of(context);
    if (_selecting) {
      setState(() => _selected.clear());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && route != null) _leave(route);
      });
      return;
    }
    if (route != null) _leave(route);
  }

  void _leave(Route<dynamic> route) => route.isCurrent
      ? Navigator.of(context).pop()
      : Navigator.of(context).removeRoute(route);

  void _enterSelection(String localId) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(localId);
    });
  }

  void _toggleSelection(String localId) {
    setState(() {
      if (!_selected.remove(localId)) _selected.add(localId);
    });
  }

  void _exitSelection() {
    setState(() => _selected.clear());
    setState(() => _selecting = false);
  }

  Future<void> _openItemMenu(Message row, bool isMine, bool online) {
    final repo = ref.read(messageRepositoryProvider);
    return showAppSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => AppSheetChrome(
        children: [
          SheetActionRow(
            icon: Icons.reply_rounded,
            label: 'Reply',
            onTap: () {
              Navigator.of(sheetContext).pop();
              ref.read(replyProvider(widget.conversationId).notifier).state =
                  row;
              Navigator.of(context).pop();
            },
          ),
          SheetActionRow(
            icon: Icons.checklist_rounded,
            label: 'Select',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _enterSelection(row.localId);
            },
          ),
          SheetActionRow(
            icon: Icons.delete_outline,
            label: 'Delete for me',
            destructive: true,
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final ok = await showConfirmDialog(
                context: context,
                title: 'Delete message?',
                body: 'This message will be deleted for you only.',
                confirmLabel: 'Delete',
                confirmIcon: Icons.delete_outline,
                destructive: true,
              );
              if (!ok) return;
              await repo.deleteMessage(row.localId);
            },
          ),
          if (isMine)
            SheetActionRow(
              icon: Icons.delete_forever_outlined,
              label: 'Delete for everyone',
              destructive: true,
              enabled: online,
              trailing: online ? null : kOfflineActionHint,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final ok = await showConfirmDialog(
                  context: context,
                  title: 'Delete message?',
                  body:
                      'This message will be deleted for everyone in this chat.',
                  confirmLabel: 'Delete',
                  confirmIcon: Icons.delete_outline,
                  destructive: true,
                );
                if (!ok) return;
                await repo.deleteMessage(row.localId, forEveryone: true);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected(List<Message> rows, bool allOwn) async {
    final picked = [
      for (final row in rows)
        if (_selected.contains(row.localId)) row,
    ];
    final ok = await deleteSelectedMessages(
      context,
      ref,
      picked,
      canDeleteForEveryone: allOwn,
    );
    if (ok && mounted) _exitSelection();
  }

  void _openViewer(List<Message> rows, List<String> mediaIds, int index) {
    final items = <MediaViewerItem>[];
    for (var i = 0; i < rows.length; i++) {
      final id = mediaIds[i];
      final thumb = ref
          .read(
            mediaFileProvider(
              MediaRef(widget.conversationId, id, thumb: true),
            ),
          )
          .valueOrNull;
      items.add(
        MediaViewerItem(
          serverId: id,
          mediaType: rows[i].type == 'video' ? 'video' : 'image',
          heroTag: mediaHeroTag(id),
          thumbPath: thumb?.file.path,
        ),
      );
    }
    pushMediaViewer(
      context,
      MediaViewerArgs(
        conversationId: widget.conversationId,
        serverId: items[index].serverId,
        mediaType: items[index].mediaType,
        // Like the single bubbles: your own album says You.
        senderName:
            rows[index].senderId == ref.read(currentUserIdProvider).valueOrNull
                ? 'You'
                : widget.senderName,
        timestamp: rows[index].createdAt,
        items: items,
        initialIndex: index,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rowsAsync = ref.watch(
      albumRowsProvider(AlbumKey(widget.conversationId, widget.albumId)),
    );
    final loaded = rowsAsync.hasValue;
    final rows = rowsAsync.valueOrNull ?? const <Message>[];

    // E1: a deleted row leaves; with one left the collage is gone.
    if (loaded && rows.length <= 1 && !_leaving) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _popToChat());
    }

    final myId = ref.watch(currentUserIdProvider).valueOrNull;
    final isMine =
        rows.isNotEmpty && myId != null && rows.first.senderId == myId;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final allOwn =
        myId != null && rows.every((row) => row.senderId == myId);

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) _exitSelection();
      },
      child: Scaffold(
        backgroundColor: context.t.bg,
        appBar: _selecting
            ? _selectionBar(context, allOwn)
            : pageAppBar(
                context,
                isMine ? 'You' : widget.senderName,
                bottom: PreferredSize(
                  preferredSize: Size.fromHeight(
                    MediaQuery.textScalerOf(context).scale(22),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: Text(
                        '${albumLabel(rows)} · $_time',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.t.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
        body: rows.isEmpty
            ? const SizedBox.shrink()
            : _collage(context, rows, isMine, online, allOwn),
      ),
    );
  }

  String get _time =>
      DateFormat('HH:mm').format(widget.timestamp.toLocal());

  PreferredSizeWidget _selectionBar(BuildContext context, bool allOwn) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Material(
        color: context.t.bg,
        child: SafeArea(
          bottom: false,
          // E3: delete-only, so no Copy or Star slot.
          child: SelectionBar(
            count: _selected.length,
            onExit: _exitSelection,
            onDelete: () => _deleteSelected(
              ref
                      .read(
                        albumRowsProvider(
                          AlbumKey(widget.conversationId, widget.albumId),
                        ),
                      )
                      .valueOrNull ??
                  const <Message>[],
              allOwn,
            ),
          ),
        ),
      ),
    );
  }

  Widget _collage(
    BuildContext context,
    List<Message> rows,
    bool isMine,
    bool online,
    bool allOwn,
  ) {
    final inputs = [
      for (final row in rows) mediaBubbleInputs(ref, row, isMine: isMine),
    ];
    final mediaIds = [
      for (var i = 0; i < rows.length; i++)
        inputs[i].mediaId ?? rows[i].localId,
    ];
    final metas = [
      for (var i = 0; i < rows.length; i++)
        inputs[i].mediaId == null
            ? null
            : ref
                  .watch(
                    mediaFileProvider(
                      MediaRef(
                        widget.conversationId,
                        inputs[i].mediaId!,
                        thumb: true,
                      ),
                    ),
                  )
                  .valueOrNull,
    ];
    final aspects = [
      for (var i = 0; i < rows.length; i++)
        (metas[i]?.width ?? 0) > 0 && (metas[i]?.height ?? 0) > 0
            ? metas[i]!.width! / metas[i]!.height!
            : 1.0,
    ];

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final rects = albumLayout(aspects, width);
        final height = rects.isEmpty ? 0.0 : rects.last.bottom;

        if (!_scrolled && rects.isNotEmpty && widget.initialIndex > 0) {
          _scrolled = true;
          final target = rects[widget.initialIndex.clamp(
            0,
            rects.length - 1,
          )].top;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scroll.hasClients) return;
            _scroll.jumpTo(
              target.clamp(0.0, _scroll.position.maxScrollExtent),
            );
          });
        }

        return ListView(
          controller: _scroll,
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    Positioned.fromRect(
                      rect: rects[i],
                      child: _tile(
                        context,
                        rows,
                        inputs[i],
                        mediaIds,
                        i,
                        isMine,
                        online,
                        allOwn,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _tile(
    BuildContext context,
    List<Message> rows,
    ({String? mediaId, String? uploadLocalId, String status}) input,
    List<String> mediaIds,
    int index,
    bool isMine,
    bool online,
    bool allOwn,
  ) {
    final row = rows[index];
    final video = row.type == 'video';
    final selected = _selected.contains(row.localId);
    final label = [
      albumTileLabel(
        index: index,
        count: rows.length,
        video: video,
        sending: input.uploadLocalId != null && input.status != 'failed',
        failed: input.status == 'failed',
      ),
      if (_selecting) selected ? 'selected' : 'not selected',
    ].join(', ');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    void tap() => _selecting
        ? _toggleSelection(row.localId)
        : _openViewer(rows, mediaIds, index);

    Widget content;
    if (input.mediaId == null) {
      content = const Skeleton.fill(radius: 0);
    } else if (video) {
      content = VideoMessageBubble(
        conversationId: row.conversationId,
        serverId: input.mediaId!,
        isMine: isMine,
        isDark: isDark,
        status: input.status,
        createdAt: row.createdAt,
        senderName: widget.senderName,
        localId: input.uploadLocalId,
        onTileTap: tap,
        tileLabel: label,
      );
    } else {
      content = ImageMessageBubble(
        conversationId: row.conversationId,
        serverId: input.mediaId!,
        isMine: isMine,
        isDark: isDark,
        status: input.status,
        createdAt: row.createdAt,
        senderName: widget.senderName,
        localId: input.uploadLocalId,
        onTileTap: tap,
        tileLabel: label,
      );
    }

    return GestureDetector(
      key: ValueKey(row.localId),
      behavior: HitTestBehavior.opaque,
      // A loading or skeleton tile has no inner tap; same as AlbumBubble.
      onTap: tap,
      // E4a: in selection mode a long-press toggles like a tap.
      onLongPress: () => _selecting
          ? _toggleSelection(row.localId)
          : _openItemMenu(row, isMine, online),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: content),
          if (_selecting)
            Positioned.fill(
              child: IgnorePointer(
                child: _selectionOverlay(context, selected),
              ),
            ),
        ],
      ),
    );
  }

  Widget _selectionOverlay(BuildContext context, bool selected) {
    final t = context.t;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (selected)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: t.accent, width: 3),
            ),
          ),
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? t.accent
                  : WarmPopTokens.shadowDark.withValues(alpha: 0.5),
              border: Border.all(
                color: selected ? t.accent : WarmPopTokens.inkDark,
                width: 2,
              ),
            ),
            child: selected
                ? Icon(Icons.check, size: 16, color: t.onAccent)
                : null,
          ),
        ),
      ],
    );
  }
}
