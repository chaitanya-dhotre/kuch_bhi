import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/pocketbase_client.dart';
import '../../../core/utils/media_utils.dart';
import '../../media/screens/media_viewer_screen.dart';

// ── Provider ─────────────────────────────────────────────────────────────────

final _mediaPageProvider = FutureProvider.autoDispose
    .family<List<RecordModel>, ({String conversationId, String mediaType})>(
  (ref, args) async {
    final pb = ref.read(pocketbaseClientProvider).pb;
    final result = await pb.collection('message_media').getList(
      filter:  'conversation_id="${args.conversationId}"'
               '&&media_type="${args.mediaType}"',
      sort:    '-created',
      perPage: 100,
    );
    return result.items;
  },
);

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

String _fileUrl(PocketBase pb, RecordModel r, String field) {
  final data = r.data[field];
  String? name;
  if (data is String && data.isNotEmpty) {
    name = data;
  } else if (data is List && data.isNotEmpty) {
    name = data.first.toString();
  }
  if (name == null || name.isEmpty) return '';
  return '${pb.baseUrl}/api/files/message_media/${r.id}/$name';
}

String _thumbUrl(PocketBase pb, RecordModel r) =>
    _fileUrl(pb, r, 'thumbnail');

String _fullUrl(PocketBase pb, RecordModel r) =>
    _fileUrl(pb, r, 'file');

DateTime? _expiresAt(RecordModel r) {
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

Widget _emptyState(String label, IconData icon) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
          ),
        ],
      ),
    );

// ── Photos tab ────────────────────────────────────────────────────────────────

class _PhotosTab extends ConsumerWidget {
  const _PhotosTab({required this.conversationId});
  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_mediaPageProvider(
      (conversationId: conversationId, mediaType: 'image'),
    ));
    final pb    = ref.read(pocketbaseClientProvider).pb;
    final token = pb.authStore.token;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState('No photos yet', Icons.photo_outlined);
        }
        final visible = items.where((r) => !isExpired(_expiresAt(r))).toList();
        final hiddenCount = items.length - visible.length;
        if (visible.isEmpty) {
          return _emptyState('No photos yet', Icons.photo_outlined);
        }
        return Column(
          children: [
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text(
                  '$hiddenCount expired item${hiddenCount == 1 ? '' : 's'} hidden',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
            final thumb    = _thumbUrl(pb, r);
            final full     = _fullUrl(pb, r);
            final created  = DateTime.tryParse(r.data['created']?.toString() ?? '') ?? DateTime.now();
            return GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MediaViewerScreen(
                    args: MediaViewerArgs(
                      mediaUrl:   full.isNotEmpty ? full : thumb,
                      mediaType:  'image',
                      authToken:  token,
                      senderName: 'Photo',
                      timestamp:  created,
                      heroTag:    'media_docs_${r.id}',
                    ),
                  ),
                ),
              ),
              child: Hero(
                tag: 'media_docs_${r.id}',
                child: thumb.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: thumb,
                        fit:      BoxFit.cover,
                        placeholder: (_, __) => Shimmer.fromColors(
                          baseColor:      Colors.grey.shade300,
                          highlightColor: Colors.grey.shade100,
                          child: Container(color: Colors.grey.shade300),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      )
                    : Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
              ),
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
    final async = ref.watch(_mediaPageProvider(
      (conversationId: conversationId, mediaType: 'video'),
    ));
    final pb    = ref.read(pocketbaseClientProvider).pb;
    final token = pb.authStore.token;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState('No videos yet', Icons.videocam_outlined);
        }
        final visible = items.where((r) => !isExpired(_expiresAt(r))).toList();
        final hiddenCount = items.length - visible.length;
        if (visible.isEmpty) {
          return _emptyState('No videos yet', Icons.videocam_outlined);
        }
        return Column(
          children: [
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text(
                  '$hiddenCount expired item${hiddenCount == 1 ? '' : 's'} hidden',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
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
            final r       = visible[i];
            final thumb   = _thumbUrl(pb, r);
            final full    = _fullUrl(pb, r);
            final dur     = _formatDuration(r.data['duration_seconds']);
            final created = DateTime.tryParse(r.data['created']?.toString() ?? '') ?? DateTime.now();

            return GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MediaViewerScreen(
                    args: MediaViewerArgs(
                      mediaUrl:   full,
                      mediaType:  'video',
                      authToken:  token,
                      senderName: 'Video',
                      timestamp:  created,
                    ),
                  ),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumb.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: thumb,
                          fit:      BoxFit.cover,
                          placeholder: (_, __) => Shimmer.fromColors(
                            baseColor:      Colors.grey.shade300,
                            highlightColor: Colors.grey.shade100,
                            child: Container(color: Colors.grey.shade300),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey.shade800,
                            child: const Icon(Icons.videocam, color: Colors.white38, size: 32),
                          ),
                        )
                      : Container(
                          color: Colors.grey.shade800,
                          child: const Icon(Icons.videocam, color: Colors.white38, size: 32),
                        ),
                  // Play icon overlay
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
                  // Duration badge
                  if (dur != '0:00')
                    Positioned(
                      left: 4, bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          dur,
                          style: const TextStyle(color: Colors.white, fontSize: 9),
                        ),
                      ),
                    ),
                ],
              ),
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
    final async = ref.watch(_mediaPageProvider(
      (conversationId: conversationId, mediaType: 'voice'),
    ));
    final pb    = ref.read(pocketbaseClientProvider).pb;
    final token = pb.authStore.token;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState('No voice messages yet', Icons.mic_none_outlined);
        }
        final visible = items.where((r) => !isExpired(_expiresAt(r))).toList();
        final hiddenCount = items.length - visible.length;
        if (visible.isEmpty) {
          return _emptyState('No voice messages yet', Icons.mic_none_outlined);
        }
        return Column(
          children: [
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text(
                  '$hiddenCount expired item${hiddenCount == 1 ? '' : 's'} hidden',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            Expanded(
              child: ListView.separated(
          itemCount:    visible.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder:  (context, i) {
            final r   = visible[i];
            final dur = _formatDuration(r.data['duration_seconds']);
            final date = _formatDate(r.data['created']?.toString() ?? '');
            final url  = _fullUrl(pb, r);
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: const Icon(Icons.mic, color: AppColors.primary),
              ),
              title: Text('Voice message · $dur'),
              subtitle: Text(date),
              trailing: const Icon(Icons.play_circle_outline, color: AppColors.primary),
              onTap: () => _playInSheet(context, url, token, dur),
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
    String url,
    String token,
    String duration,
  ) {
    showModalBottomSheet(
      context:     context,
      builder:     (_) => _VoicePlaySheet(url: url, token: token, duration: duration),
      isScrollControlled: false,
    );
  }
}

// ── Voice playback bottom sheet ───────────────────────────────────────────────

class _VoicePlaySheet extends StatefulWidget {
  const _VoicePlaySheet({
    required this.url,
    required this.token,
    required this.duration,
  });

  final String url;
  final String token;
  final String duration;

  @override
  State<_VoicePlaySheet> createState() => _VoicePlaySheetState();
}

class _VoicePlaySheetState extends State<_VoicePlaySheet> {
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
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(widget.url),
          headers: {'Authorization': 'Bearer ${widget.token}'},
        ),
      );
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
            const Icon(Icons.mic, size: 40, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              'Voice message · ${widget.duration}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value:           progress,
              backgroundColor: Colors.grey.shade300,
              valueColor:      const AlwaysStoppedAnimation(AppColors.primary),
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
              const CircularProgressIndicator(color: AppColors.primary)
            else
              IconButton(
                iconSize: 48,
                onPressed: () => _playing ? _player.pause() : _player.play(),
                icon: Icon(
                  _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: AppColors.primary,
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
    final async = ref.watch(_mediaPageProvider(
      (conversationId: conversationId, mediaType: 'document'),
    ));
    final pb    = ref.read(pocketbaseClientProvider).pb;
    final token = pb.authStore.token;

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (e, _) => Center(child: Text('Error: $e')),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState('No documents yet', Icons.folder_open_outlined);
        }
        final visible = items.where((r) => !isExpired(_expiresAt(r))).toList();
        final hiddenCount = items.length - visible.length;
        if (visible.isEmpty) {
          return _emptyState('No documents yet', Icons.folder_open_outlined);
        }
        return Column(
          children: [
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Text(
                  '$hiddenCount expired item${hiddenCount == 1 ? '' : 's'} hidden',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ),
            Expanded(
              child: ListView.separated(
          itemCount:    visible.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder:  (context, i) {
            final r        = visible[i];
            final fileName = r.data['file_name']?.toString() ?? 'Document';
            final size     = _formatSize(r.data['file_size']);
            final date     = _formatDate(r.data['created']?.toString() ?? '');
            final url      = _fullUrl(pb, r);
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Icon(_docIcon(fileName), color: AppColors.primary),
              ),
              title:    Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('$size · $date'),
              trailing: const Icon(Icons.download_outlined, color: AppColors.primary),
              onTap:    () => _openDoc(context, url, token, fileName),
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
    String url,
    String token,
    String fileName,
  ) async {
    if (url.isEmpty) return;
    try {
      final cacheDir = await getTemporaryDirectory();
      final file     = File('${cacheDir.path}/$fileName');
      if (!file.existsSync()) {
        final request = await HttpClient().getUrl(Uri.parse(url));
        request.headers.set('Authorization', 'Bearer $token');
        final response = await request.close();
        final bytes    = await response.expand((b) => b).toList();
        await file.writeAsBytes(bytes);
      }
      await OpenFile.open(file.path);
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
