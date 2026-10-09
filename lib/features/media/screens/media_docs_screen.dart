import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_file/open_file.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/media_utils.dart';
import '../../../infrastructure/services/media_gallery_service.dart';
import '../../chat/providers/chat_provider.dart';
import '../../media/screens/media_viewer_screen.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class MediaDocsScreen extends ConsumerWidget {
  const MediaDocsScreen({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Media & Docs'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Photos'),
              Tab(text: 'Videos'),
              Tab(text: 'Voice'),
              Tab(text: 'Docs'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _PhotosTab(conversationId: conversationId),
            _VideosTab(conversationId: conversationId),
            _VoiceTab(conversationId: conversationId),
            _DocsTab(conversationId: conversationId),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

DateTime? _expiresAt(MediaRecord r) {
  final raw = r.data['expires_at']?.toString() ?? '';
  return raw.isNotEmpty ? DateTime.tryParse(raw)?.toLocal() : null;
}

String _formatSize(dynamic raw) {
  final bytes = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
  if (bytes <= 0)   return '';
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDuration(dynamic raw) {
  final secs = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
  final m = secs ~/ 60;
  final s = secs % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String _formatDate(String iso) {
  try {
    return DateFormat('MMM d, yyyy').format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}

IconData _docIcon(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  return switch (ext) {
    'pdf'                         => Icons.picture_as_pdf_outlined,
    'doc' || 'docx'               => Icons.description_outlined,
    'xls' || 'xlsx'               => Icons.table_chart_outlined,
    'ppt' || 'pptx'               => Icons.slideshow_outlined,
    'zip' || 'rar' || '7z' || 'gz'=> Icons.folder_zip_outlined,
    'txt' || 'md'                 => Icons.text_snippet_outlined,
    _                             => Icons.insert_drive_file_outlined,
  };
}

Widget _emptyState(BuildContext context, String label, IconData icon) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: context.t.inkFaint),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(color: context.t.inkSoft, fontSize: 15),
          ),
        ],
      ),
    );

// ── Grid tile (photos + videos) ────────────────────────────────────────────────

/// A single grid tile that watches its own thumbnail via [mediaFileProvider]
/// (decrypted local file), and fetches the full file on tap before opening the
/// viewer.
class _MediaGridTile extends ConsumerWidget {
  const _MediaGridTile({
    required this.conversationId,
    required this.serverId,
    required this.heroTag,
    required this.mediaType,
    required this.senderName,
    required this.created,
    this.durationLabel,
  });

  final String   conversationId;
  final String   serverId;
  final String   heroTag;
  final String   mediaType; // 'image' | 'video'
  final String   senderName;
  final DateTime created;
  final String?  durationLabel;

  Widget _placeholder(BuildContext context) => Shimmer.fromColors(
        baseColor:      context.t.line,
        highlightColor: context.t.surface2,
        child: Container(color: context.t.line),
      );

  Widget _broken(BuildContext context) => Container(
        color: mediaType == 'video' ? context.t.ink : context.t.surface2,
        child: Icon(
          mediaType == 'video' ? Icons.videocam : Icons.broken_image,
          color: mediaType == 'video' ? context.t.inkFaint : context.t.inkSoft,
          size:  mediaType == 'video' ? 32 : 24,
        ),
      );

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final media = await ref.read(
      mediaFileProvider(MediaRef(conversationId, serverId)).future,
    );
    if (media != null && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaViewerScreen(
            args: MediaViewerArgs(
              localPath:  media.file.path,
              mediaType:  mediaType,
              senderName: senderName,
              timestamp:  created,
              heroTag:    heroTag,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbAsync = ref.watch(
      mediaFileProvider(MediaRef(conversationId, serverId, thumb: true)),
    );

    final thumbWidget = thumbAsync.when(
      loading: () => _placeholder(context),
      error:   (_, __) => _broken(context),
      data: (media) => media == null
          ? _broken(context)
          : Image.file(
              media.file,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _broken(context),
            ),
    );

    return GestureDetector(
      onTap: () => _open(context, ref),
      child: mediaType == 'video'
          ? Stack(
              fit: StackFit.expand,
              children: [
                thumbWidget,
                Center(
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                  ),
                ),
                if (durationLabel != null && durationLabel != '0:00')
                  Positioned(
                    left: 4, bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        durationLabel!,
                        style: const TextStyle(color: Colors.white, fontSize: 9),
                      ),
                    ),
                  ),
              ],
            )
          : Hero(tag: heroTag, child: thumbWidget),
    );
  }
}

// ── Photos tab ────────────────────────────────────────────────────────────────

class _PhotosTab extends ConsumerWidget {
  const _PhotosTab({required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mediaPageProvider(
      (conversationId: conversationId, mediaType: 'image'),
    ));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState(context, 'No photos yet', Icons.photo_outlined);
        }
        final visible = items.where((r) => !isExpired(_expiresAt(r))).toList();
        final hiddenCount = items.length - visible.length;
        if (visible.isEmpty) {
          return _emptyState(context, 'No photos yet', Icons.photo_outlined);
        }
        return Column(
          children: [
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text(
                  '$hiddenCount expired item${hiddenCount == 1 ? '' : 's'} hidden',
                  style: TextStyle(fontSize: 12, color: context.t.inkSoft),
                ),
              ),
            Expanded(
              child: GridView.builder(
          padding:     const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:   3,
            mainAxisSpacing:  2,
            crossAxisSpacing: 2,
          ),
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final r        = visible[i];
            final serverId = r.getStringValue('message_id');
            final created  = DateTime.tryParse(r.data['created']?.toString() ?? '') ?? DateTime.now();
            return _MediaGridTile(
              conversationId: conversationId,
              serverId:       serverId,
              heroTag:        'media_docs_${r.id}',
              mediaType:      'image',
              senderName:     'Photo',
              created:        created,
            );
          },
        ),
            ),
          ],
        );
      },
    );
  }
}

// ── Videos tab ────────────────────────────────────────────────────────────────

class _VideosTab extends ConsumerWidget {
  const _VideosTab({required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mediaPageProvider(
      (conversationId: conversationId, mediaType: 'video'),
    ));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState(context, 'No videos yet', Icons.videocam_outlined);
        }
        final visible = items.where((r) => !isExpired(_expiresAt(r))).toList();
        final hiddenCount = items.length - visible.length;
        if (visible.isEmpty) {
          return _emptyState(context, 'No videos yet', Icons.videocam_outlined);
        }
        return Column(
          children: [
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text(
                  '$hiddenCount expired item${hiddenCount == 1 ? '' : 's'} hidden',
                  style: TextStyle(fontSize: 12, color: context.t.inkSoft),
                ),
              ),
            Expanded(
              child: GridView.builder(
          padding:     const EdgeInsets.all(2),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:   3,
            mainAxisSpacing:  2,
            crossAxisSpacing: 2,
          ),
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final r        = visible[i];
            final serverId = r.getStringValue('message_id');
            final dur      = _formatDuration(r.data['duration_seconds']);
            final created  = DateTime.tryParse(r.data['created']?.toString() ?? '') ?? DateTime.now();

            return _MediaGridTile(
              conversationId: conversationId,
              serverId:       serverId,
              heroTag:        'media_docs_${r.id}',
              mediaType:      'video',
              senderName:     'Video',
              created:        created,
              durationLabel:  dur,
            );
          },
        ),
            ),
          ],
        );
      },
    );
  }
}

// ── Voice tab ─────────────────────────────────────────────────────────────────

class _VoiceTab extends ConsumerWidget {
  const _VoiceTab({required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mediaPageProvider(
      (conversationId: conversationId, mediaType: 'voice'),
    ));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState(context, 'No voice messages yet', Icons.mic_none_outlined);
        }
        final visible = items.where((r) => !isExpired(_expiresAt(r))).toList();
        final hiddenCount = items.length - visible.length;
        if (visible.isEmpty) {
          return _emptyState(context, 'No voice messages yet', Icons.mic_none_outlined);
        }
        return Column(
          children: [
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text(
                  '$hiddenCount expired item${hiddenCount == 1 ? '' : 's'} hidden',
                  style: TextStyle(fontSize: 12, color: context.t.inkSoft),
                ),
              ),
            Expanded(
              child: ListView.separated(
          itemCount:    visible.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder:  (context, i) {
            final r        = visible[i];
            final serverId = r.getStringValue('message_id');
            final dur      = _formatDuration(r.data['duration_seconds']);
            final date     = _formatDate(r.data['created']?.toString() ?? '');
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: context.t.accent.withValues(alpha: 0.12),
                child: Icon(Icons.mic, color: context.t.accent),
              ),
              title: Text('Voice message · $dur'),
              subtitle: Text(date),
              trailing: Icon(Icons.play_circle_outline, color: context.t.accent),
              onTap: () => _playInSheet(context, conversationId, serverId, dur),
            );
          },
        ),
            ),
          ],
        );
      },
    );
  }

  void _playInSheet(
    BuildContext context,
    String conversationId,
    String serverId,
    String duration,
  ) {
    showModalBottomSheet(
      context:     context,
      builder:     (_) => _VoicePlaySheet(
        conversationId: conversationId,
        serverId:       serverId,
        duration:       duration,
      ),
      isScrollControlled: false,
    );
  }
}

// ── Voice playback bottom sheet ───────────────────────────────────────────────

class _VoicePlaySheet extends ConsumerStatefulWidget {
  const _VoicePlaySheet({
    required this.conversationId,
    required this.serverId,
    required this.duration,
  });

  final String conversationId;
  final String serverId;
  final String duration;

  @override
  ConsumerState<_VoicePlaySheet> createState() => _VoicePlaySheetState();
}

class _VoicePlaySheetState extends ConsumerState<_VoicePlaySheet> {
  final _player  = AudioPlayer();
  bool  _loading = true;
  bool  _playing = false;
  Duration _pos  = Duration.zero;
  Duration _total = Duration.zero;

  @override
  void initState() {
    super.initState();
    _init();
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _total = d);
    });
    _player.playerStateStream.listen((s) {
      if (!mounted) return;
      setState(() => _playing =
          s.playing && s.processingState != ProcessingState.completed);
      if (s.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });
  }

  Future<void> _init() async {
    try {
      // Download + decrypt the voice note to a local file, then play it.
      final media = await ref.read(mediaFileProvider(
          MediaRef(widget.conversationId, widget.serverId)).future);
      if (media == null) throw Exception('No media found');

      await _player.setFilePath(media.file.path);
      await _player.play();
    } catch (e) {
      debugPrint('[VoiceSheet] Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total.inMilliseconds > 0
        ? (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic, size: 40, color: context.t.accent),
            const SizedBox(height: 12),
            Text(
              'Voice message · ${widget.duration}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value:           progress,
              backgroundColor: context.t.surface2,
              valueColor:      AlwaysStoppedAnimation(context.t.accent),
              minHeight:       4,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(_pos),   style: const TextStyle(fontSize: 12)),
                Text(_fmt(_total), style: const TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              CircularProgressIndicator(color: context.t.accent)
            else
              IconButton(
                iconSize: 48,
                onPressed: () => _playing ? _player.pause() : _player.play(),
                icon: Icon(
                  _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: context.t.accent,
                  size: 48,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Docs tab ──────────────────────────────────────────────────────────────────

class _DocsTab extends ConsumerWidget {
  const _DocsTab({required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mediaPageProvider(
      (conversationId: conversationId, mediaType: 'document'),
    ));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState(context, 'No documents yet', Icons.folder_open_outlined);
        }
        final visible = items.where((r) => !isExpired(_expiresAt(r))).toList();
        final hiddenCount = items.length - visible.length;
        if (visible.isEmpty) {
          return _emptyState(context, 'No documents yet', Icons.folder_open_outlined);
        }
        return Column(
          children: [
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text(
                  '$hiddenCount expired item${hiddenCount == 1 ? '' : 's'} hidden',
                  style: TextStyle(fontSize: 12, color: context.t.inkSoft),
                ),
              ),
            Expanded(
              child: ListView.separated(
          itemCount:    visible.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder:  (context, i) {
            final r        = visible[i];
            final serverId = r.getStringValue('message_id');
            final fileName = r.data['file_name']?.toString() ?? 'Document';
            final size     = _formatSize(r.data['file_size']);
            final date     = _formatDate(r.data['created']?.toString() ?? '');
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: context.t.accent.withValues(alpha: 0.12),
                child: Icon(_docIcon(fileName), color: context.t.accent),
              ),
              title:    Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('$size · $date'),
              trailing: Icon(Icons.download_outlined, color: context.t.accent),
              onTap:    () => _openDoc(context, ref, serverId),
            );
          },
        ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openDoc(
    BuildContext context,
    WidgetRef ref,
    String serverId,
  ) async {
    try {
      // Download + decrypt the document to a local file, then open it.
      final media = await ref.read(mediaFileProvider(
          MediaRef(conversationId, serverId)).future);
      if (media == null) throw Exception('No media found');

      await OpenFile.open(media.file.path);
    } catch (e) {
      debugPrint('[DocsTab] Open failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: $e')),
        );
      }
    }
  }
}
