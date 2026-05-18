import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../../services/media_upload_service.dart';

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
              const Icon(Icons.star, color: AppColors.warning, size: 14),
              const SizedBox(width: 6),
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
          if (widget.message.type == 'image' && widget.message.serverId != null)
            _buildImageContent()
          else
            Text(
              widget.message.decryptedBody ?? '🔒 Encrypted',
              style: const TextStyle(fontSize: 15),
            ),
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
