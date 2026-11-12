import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../data/local/database/app_database.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../chat/chat_run_grouping.dart' show albumLabel;
import '../../chat/providers/chat_provider.dart';
import '../../chat/providers/message_body_provider.dart';
import '../../chat/widgets/message_body_text.dart';
import '../../stickers/sticker_widgets.dart';

final _starredProvider = FutureProvider.autoDispose
    .family<List<Message>, String>((ref, conversationId) {
  return ref.read(messageRepositoryProvider).getStarredMessages(conversationId);
});

/// 12.5 F7: an album's starred rows are one card.
class _StarredEntry {
  const _StarredEntry.album(this.rows) : single = null;
  const _StarredEntry.single(this.single) : rows = const [];

  /// In album order; empty for a single.
  final List<Message> rows;
  final Message? single;

  bool get isAlbum => rows.length > 1;
  Message get cover => rows.isNotEmpty ? rows.first : single!;
}

/// Groups starred rows by album. The server's starred record carries ids
/// only, so a row without an album id is resolved against its local copy
/// (the same row the repository already looked up for type and body).
final _starredEntriesProvider =
    FutureProvider.autoDispose.family<List<_StarredEntry>, String>(
  (ref, conversationId) async {
    final starred = await ref.watch(_starredProvider(conversationId).future);
    final dao = ref.read(appDatabaseProvider).messagesDao;

    final albumIdByLocal = <String, String>{};
    final groups = <String, List<Message>>{};
    for (final m in starred) {
      var albumId = m.albumId;
      if ((albumId == null || albumId.isEmpty) && m.serverId != null) {
        try {
          albumId = (await dao.getMessageByServerId(m.serverId!))?.albumId;
        } catch (_) {}
      }
      if (albumId == null || albumId.isEmpty) continue;
      albumIdByLocal[m.localId] = albumId;
      groups.putIfAbsent(albumId, () => []).add(m);
    }

    final out = <_StarredEntry>[];
    final emitted = <String>{};
    for (final m in starred) {
      final albumId = albumIdByLocal[m.localId];
      if (albumId == null) {
        out.add(_StarredEntry.single(m));
        continue;
      }
      if (!emitted.add(albumId)) continue;
      final rows = groups[albumId]!
        ..sort((a, b) {
          final i = (a.albumIndex ?? 0).compareTo(b.albumIndex ?? 0);
          return i != 0 ? i : a.createdAt.compareTo(b.createdAt);
        });
      out.add(
        rows.length > 1 ? _StarredEntry.album(rows) : _StarredEntry.single(rows.first),
      );
    }
    return out;
  },
);


class StarredMessagesScreen extends ConsumerWidget {
  const StarredMessagesScreen({
    super.key,
    required this.conversationId,
    this.onJump,
  });
  final String conversationId;
  /// Called when the user taps a card to jump to that message in the chat.
  final void Function(Message)? onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(_starredEntriesProvider(conversationId));
    void refresh() {
      ref.invalidate(_starredProvider(conversationId));
      ref.invalidate(_starredEntriesProvider(conversationId));
    }

    return Scaffold(
      appBar: pageAppBar(
        context,
        'Starred Messages',
        actions: [
          IconButton(
            icon:     const Icon(Icons.refresh),
            onPressed: refresh,
          ),
        ],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // R7: plain copy and a Retry, never the exception.
        error:   (_, __) => EmptyState(
          title: "Couldn't load starred messages.",
          subtitle: kConnectionRetryCopy,
          // The mascot does not fit at 200% text on a 360dp phone.
          withMascot: false,
          action: AppButton(
            onPressed: refresh,
            child: const Text('Retry'),
          ),
        ),
        data:    (entries) => entries.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.star_outline, size: 64,
                        color: context.t.ink.withValues(alpha: 0.2)),
                    const SizedBox(height: 12),
                    Text('No starred messages',
                        style: TextStyle(
                          color: context.t.ink.withValues(alpha: 0.4),
                        )),
                  ],
                ),
              )
            : ListView.separated(
                padding:    const EdgeInsets.all(16),
                itemCount:  entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _StarredCard(
                  entry: entries[i],
                  onJump:  onJump != null
                      ? () {
                          Navigator.of(context).pop();
                          // Give the chat screen one frame to remount before scrolling
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            onJump!(entries[i].cover);
                          });
                        }
                      : null,
                ),
              ),
      ),
    );
  }
}

class _StarredCard extends ConsumerStatefulWidget {
  const _StarredCard({required this.entry, this.onJump});
  final _StarredEntry entry;
  final VoidCallback? onJump;

  @override
  ConsumerState<_StarredCard> createState() => _StarredCardState();
}

class _StarredCardState extends ConsumerState<_StarredCard> {
  File? _thumbFile;
  bool _loadingImage = true;

  Message get _cover => widget.entry.cover;

  @override
  void initState() {
    super.initState();
    final cover = _cover;
    final hasThumb =
        cover.type == 'image' || (widget.entry.isAlbum && cover.type == 'video');
    if (hasThumb && cover.serverId != null) {
      _loadImage();
    } else {
      _loadingImage = false;
    }
  }

  Future<void> _loadImage() async {
    final cover = _cover;
    final media = await ref.read(messageRepositoryProvider).getDecryptedMedia(
          cover.conversationId,
          cover.serverId!,
          thumb: true,
        );
    if (mounted) {
      setState(() {
        _thumbFile = media?.file;
        _loadingImage = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId   = ref.watch(currentUserIdProvider).asData?.value ?? '';
    final isMine = _cover.senderId == myId;

    return GestureDetector(
      onTap: widget.onJump,
      child: Container(
      padding:    const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        context.t.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: WarmPopTokens.cardShadow(context.t.shadow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: context.t.accent, size: 14),
              const SizedBox(width: 6),
              Text(
                isMine ? 'You' : 'Contact',
                style: TextStyle(
                  fontSize:   12,
                  fontWeight: FontWeight.w600,
                  color:      context.t.accent,
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM d, HH:mm')
                    .format(_cover.createdAt.toLocal()),
                style: TextStyle(
                  fontSize: 11,
                  color:    context.t.ink.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildContent(context),
          if (widget.onJump != null) ...[
            const SizedBox(height: 8),
            Text(
              'Tap to jump to message',
              style: TextStyle(
                fontSize: 11,
                color:    context.t.ink.withValues(alpha: 0.35),
              ),
            ),
          ],
        ],
      ),
    ),
    );
  }

  /// Media-aware card content — never blank, even for video/voice/document.
  Widget _buildContent(BuildContext context) {
    if (widget.entry.isAlbum) return _buildAlbumContent(context);
    final msg  = _cover;
    // Voice duration / file name decrypt on device after a cold start.
    final body = ref.watch(messageBodyProvider(msg.localId)).valueOrNull ??
        msg.decryptedBody ??
        '';

    switch (msg.type) {
      case 'image':
        if (msg.serverId != null) return _buildImageContent();
        return _mediaRow(
            context, Icons.camera_alt_outlined, kMediaRowPhotoLabel);
      case 'video':
        return _mediaRow(
            context, Icons.videocam_outlined, kMediaRowVideoLabel);
      case 'voice':
        final dur = body.replaceFirst('🎤', '').trim();
        return _mediaRow(
          context,
          Icons.mic_none,
          dur.isNotEmpty && dur != kMediaRowVoiceLabel
              ? voiceMessageRowCopy(dur)
              : kMediaRowVoiceLabel,
        );
      case 'document':
        return _mediaRow(
          context,
          Icons.description_outlined,
          body.isNotEmpty ? body : kMediaRowDocumentLabel,
        );
      case 'sticker':
        return Row(
          children: [
            SizedBox.square(dimension: 48, child: stickerThumb(body, 48)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sticker',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  color: context.t.ink.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        );
      default:
        // Body resolves on device (cache → decrypt); never a server copy.
        return MessageBodyText(
          messageId: msg.localId,
          styleContext: 'bubble',
          decryptState: msg.decryptState,
          ciphertextLength: msg.ciphertextLength,
        );
    }
  }

  /// F7: one card for the album — the cover's thumbnail and **5 photos**.
  Widget _buildAlbumContent(BuildContext context) {
    final label = albumLabel(widget.entry.rows);
    if (_loadingImage) {
      return const SizedBox(
        height: 120,
        child: Center(child: BusySpinner()),
      );
    }
    final thumb = _thumbFile;
    if (thumb == null) {
      return _mediaRow(context, Icons.photo_library_outlined, label);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            thumb,
            height: 200,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 8),
        _mediaRow(context, Icons.photo_library_outlined, label),
      ],
    );
  }

  Widget _mediaRow(BuildContext context, IconData icon, String label) {
    final color =
        context.t.ink.withValues(alpha: 0.7);
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 15, color: color),
          ),
        ),
      ],
    );
  }

  Widget _buildImageContent() {
    if (_loadingImage) {
      return const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    // If thumb decryption/download failed (stale media ref, missing key, etc.)
    // fall back to the icon-row so the card is helpful instead of empty.
    if (_thumbFile == null) {
      return _mediaRow(
        context,
        Icons.camera_alt_outlined,
        // Reuse any caption/body if present, otherwise just the label.
        (_cover.decryptedBody ?? '').isNotEmpty
            ? _cover.decryptedBody!
            : kMediaRowPhotoLabel,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        _thumbFile!,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
        // Decode failure inside Image.file (corrupt/truncated thumb) — fall
        // through to the same icon row so the user always sees context.
        errorBuilder: (_, __, ___) => _mediaRow(
          context,
          Icons.camera_alt_outlined,
          (_cover.decryptedBody ?? '').isNotEmpty
              ? _cover.decryptedBody!
              : kMediaRowPhotoLabel,
        ),
      ),
    );
  }
}
