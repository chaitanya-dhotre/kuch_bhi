import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../../chat/providers/chat_provider.dart';
import '../../chat/providers/message_body_provider.dart';
import '../../chat/widgets/message_body_text.dart';

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
      appBar: pageAppBar(
        context,
        'Starred Messages',
        actions: [
          IconButton(
            icon:     const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_starredProvider(conversationId)),
          ),
        ],
      ),
      body: starredAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // R7: plain copy and a Retry, never the exception.
        error:   (_, __) => EmptyState(
          title: "Couldn't load starred messages.",
          subtitle: kConnectionRetryCopy,
          // The mascot does not fit at 200% text on a 360dp phone.
          withMascot: false,
          action: AppButton(
            onPressed: () => ref.invalidate(_starredProvider(conversationId)),
            child: const Text('Retry'),
          ),
        ),
        data:    (messages) => messages.isEmpty
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
                    .format(widget.message.createdAt.toLocal()),
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
    final msg  = widget.message;
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
        (widget.message.decryptedBody ?? '').isNotEmpty
            ? widget.message.decryptedBody!
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
          (widget.message.decryptedBody ?? '').isNotEmpty
              ? widget.message.decryptedBody!
              : kMediaRowPhotoLabel,
        ),
      ),
    );
  }
}
