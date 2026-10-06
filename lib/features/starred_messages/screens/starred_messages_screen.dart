import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/tokens.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../chat/providers/chat_provider.dart';

final _starredProvider = FutureProvider.autoDispose
    .family<List<Message>, String>((ref, conversationId) {
  return ref.read(messageRepositoryProvider).getStarredMessages(conversationId);
});

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
    final starredAsync = ref.watch(_starredProvider(conversationId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Starred Messages'),
        actions: [
          IconButton(
            icon:     const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_starredProvider(conversationId)),
          ),
        ],
      ),
      body: starredAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (messages) => messages.isEmpty
            ? Center(
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
                              .withValues(alpha: 0.4),
                        )),
                  ],
                ),
              )
            : ListView.separated(
                padding:    const EdgeInsets.all(16),
                itemCount:  messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _StarredCard(
                  message: messages[i],
                  onJump:  onJump != null
                      ? () {
                          Navigator.of(context).pop();
                          // Give the chat screen one frame to remount before scrolling
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            onJump!(messages[i]);
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
  const _StarredCard({required this.message, this.onJump});
  final Message message;
  final VoidCallback? onJump;

  @override
  ConsumerState<_StarredCard> createState() => _StarredCardState();
}

class _StarredCardState extends ConsumerState<_StarredCard> {
  File? _thumbFile;
  bool _loadingImage = true;

  @override
  void initState() {
    super.initState();
    if (widget.message.type == 'image' && widget.message.serverId != null) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final media = await ref.read(messageRepositoryProvider).getDecryptedMedia(
          widget.message.conversationId,
          widget.message.serverId!,
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
    final isMine = widget.message.senderId == myId;

    return GestureDetector(
      onTap: widget.onJump,
      child: Container(
      padding:    const EdgeInsets.all(14),
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
                    .format(widget.message.createdAt.toLocal()),
                style: TextStyle(
                  fontSize: 11,
                  color:    Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
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

  /// Media-aware card content — never blank, even for video/voice/document.
  Widget _buildContent(BuildContext context) {
    final msg  = widget.message;
    final body = msg.decryptedBody ?? '';

    switch (msg.type) {
      case 'image':
        if (msg.serverId != null) return _buildImageContent();
        return _mediaRow(context, Icons.camera_alt_outlined, 'Photo');
      case 'video':
        return _mediaRow(context, Icons.videocam_outlined, 'Video');
      case 'voice':
        final dur = body.replaceFirst('🎤', '').trim();
        return _mediaRow(
          context,
          Icons.mic_none,
          dur.isNotEmpty && dur != 'Voice message'
              ? 'Voice message · $dur'
              : 'Voice message',
        );
      case 'document':
        return _mediaRow(
          context,
          Icons.description_outlined,
          body.isNotEmpty ? body : 'Document',
        );
      default:
        return Text(
          msg.decryptedBody ?? '🔒 Encrypted',
          style: const TextStyle(fontSize: 15),
        );
    }
  }

  Widget _mediaRow(BuildContext context, IconData icon, String label) {
    final color =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);
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
        (widget.message.decryptedBody ?? '').isNotEmpty
            ? widget.message.decryptedBody!
            : 'Photo',
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
          (widget.message.decryptedBody ?? '').isNotEmpty
              ? widget.message.decryptedBody!
              : 'Photo',
        ),
      ),
    );
  }
}
