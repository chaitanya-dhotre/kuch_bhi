import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_file/open_file.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/page_app_bar.dart';
import '../../../core/utils/media_utils.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../infrastructure/services/media_gallery_service.dart';
import '../../chat/message_offline_policy.dart';
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
        appBar: pageAppBar(
          context,
          'Media & Docs',
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

String _formatDuration(dynamic raw) {
  final secs = raw is int ? raw : int.tryParse(raw?.toString() ?? '') ?? 0;
  return formatMmSs(secs);
}

String _formatDate(String iso) {
  try {
    return DateFormat('MMM d, yyyy').format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return iso;
  }
}

/// E2: voice and doc rows, as Chat calm E4. No marigold.
class _RowTile extends StatelessWidget {
  const _RowTile(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: context.t.ink.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
    ),
    child: Icon(icon, color: context.t.ink),
  );
}

TextStyle _rowTitle(BuildContext context) => TextStyle(
  fontSize: 15,
  height: 22 / 15,
  fontWeight: FontWeight.w600,
  color: context.t.ink,
);

TextStyle _rowMeta(BuildContext context) =>
    TextStyle(fontSize: 13, height: 18 / 13, color: context.t.inkSoft);

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

/// A tab's page did not load: plain copy and a Retry (never the exception).
class _LoadFailed extends ConsumerWidget {
  const _LoadFailed(this.args);
  final ({String conversationId, String mediaType}) args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final caption = TextStyle(color: context.t.inkSoft, fontSize: 13);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 56, color: context.t.inkFaint),
            const SizedBox(height: 12),
            Text(
              "Couldn't load this chat's media.",
              textAlign: TextAlign.center,
              style: TextStyle(color: context.t.inkSoft, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Opacity(
              opacity: online ? 1 : .38,
              child: AppButton(
                variant: AppButtonVariant.text,
                onPressed: online
                    ? () => ref.invalidate(mediaPageProvider(args))
                    : null,
                child: const Text('Retry'),
              ),
            ),
            if (!online) Text(kOfflineActionHint, style: caption),
          ],
        ),
      ),
    );
  }
}

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

  Widget _placeholder(BuildContext context) =>
      const Skeleton.fill(radius: 0);

  Widget _broken(BuildContext context) => Container(
        color: mediaType == 'video' ? context.t.ink : context.t.surface2,
        child: Icon(
          mediaType == 'video' ? Icons.videocam : Icons.broken_image,
          color: mediaType == 'video' ? context.t.inkFaint : context.t.inkSoft,
          size:  mediaType == 'video' ? 32 : 24,
        ),
      );

  void _open(BuildContext context, WidgetRef ref) {
    // Opens at once on the thumbnail; the viewer loads the full file.
    final thumb = ref
        .read(mediaFileProvider(MediaRef(conversationId, serverId, thumb: true)))
        .valueOrNull;
    pushMediaViewer(
      context,
      MediaViewerArgs(
        conversationId: conversationId,
        serverId:       serverId,
        mediaType:      mediaType,
        senderName:     senderName,
        timestamp:      created,
        heroTag:        heroTag,
        thumbPath:      thumb?.file.path,
      ),
    );
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
                        borderRadius:
                            BorderRadius.circular(WarmPopTokens.radiusPill),
                      ),
                      child: Text(
                        durationLabel!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 14 / 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : Hero(tag: heroTag, child: thumbWidget),
    );
  }
}

/// G1, live: a message deleted for everyone while this tab is open leaves
/// at once (the server list is fetched only once per open).
List<MediaRecord> _withoutDeleted(
  WidgetRef ref,
  String conversationId,
  List<MediaRecord> items,
) {
  final gone =
      ref.watch(deletedMessageIdsProvider(conversationId)).valueOrNull;
  if (gone == null || gone.isEmpty) return items;
  return [
    for (final r in items)
      if (!gone.contains(r.getStringValue('message_id'))) r,
  ];
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
      loading: () => const Center(child: BusySpinner()),
      error: (_, __) => _LoadFailed(
        (conversationId: conversationId, mediaType: 'image'),
      ),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState(context, 'No photos yet', Icons.photo_outlined);
        }
        final live = _withoutDeleted(ref, conversationId, items);
        final visible = live.where((r) => !isExpired(_expiresAt(r))).toList();
        final hiddenCount = live.length - visible.length;
        if (visible.isEmpty) {
          return _emptyState(context, 'No photos yet', Icons.photo_outlined);
        }
        return Column(
          children: [
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Text(
                  '$hiddenCount expired item${hiddenCount == 1 ? '' : 's'} hidden',
                  style: TextStyle(
                      fontSize: 13, height: 18 / 13, color: context.t.inkSoft),
                ),
              ),
            Expanded(
              child: GridView.builder(
          padding:     const EdgeInsets.all(4),
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
              senderName:     kMediaRowPhotoLabel,
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
      loading: () => const Center(child: BusySpinner()),
      error: (_, __) => _LoadFailed(
        (conversationId: conversationId, mediaType: 'video'),
      ),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState(context, 'No videos yet', Icons.videocam_outlined);
        }
        final live = _withoutDeleted(ref, conversationId, items);
        final visible = live.where((r) => !isExpired(_expiresAt(r))).toList();
        final hiddenCount = live.length - visible.length;
        if (visible.isEmpty) {
          return _emptyState(context, 'No videos yet', Icons.videocam_outlined);
        }
        return Column(
          children: [
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Text(
                  '$hiddenCount expired item${hiddenCount == 1 ? '' : 's'} hidden',
                  style: TextStyle(
                      fontSize: 13, height: 18 / 13, color: context.t.inkSoft),
                ),
              ),
            Expanded(
              child: GridView.builder(
          padding:     const EdgeInsets.all(4),
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
              senderName:     kMediaRowVideoLabel,
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
      loading: () => const Center(child: BusySpinner()),
      error: (_, __) => _LoadFailed(
        (conversationId: conversationId, mediaType: 'voice'),
      ),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState(context, 'No voice messages yet', Icons.mic_none_outlined);
        }
        final live = _withoutDeleted(ref, conversationId, items);
        final visible = live.where((r) => !isExpired(_expiresAt(r))).toList();
        final hiddenCount = live.length - visible.length;
        if (visible.isEmpty) {
          return _emptyState(context, 'No voice messages yet', Icons.mic_none_outlined);
        }
        return Column(
          children: [
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Text(
                  '$hiddenCount expired item${hiddenCount == 1 ? '' : 's'} hidden',
                  style: TextStyle(
                      fontSize: 13, height: 18 / 13, color: context.t.inkSoft),
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
              leading: _RowTile(Icons.mic_none_rounded),
              title: Text(voiceMessageRowCopy(dur), style: _rowTitle(context)),
              subtitle: Text(date, style: _rowMeta(context)),
              trailing:
                  Icon(Icons.play_circle_outline, color: context.t.inkSoft),
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
    showAppSheet<void>(
      context:     context,
      builder:     (_) => _VoicePlaySheet(
        conversationId: conversationId,
        serverId:       serverId,
        duration:       duration,
      ),
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
  bool  _failed  = false;
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
      // play() completes only when playback stops; awaiting it kept the
      // spinner up for the whole clip.
      unawaited(_player.play());
    } catch (e) {
      debugPrint('[VoiceSheet] Error: $e');
      _failed = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _failed = false;
    });
    // mediaFileProvider caches its null (it is not auto-disposed): drop it,
    // or Try again would get the same failure back.
    ref.invalidate(
        mediaFileProvider(MediaRef(widget.conversationId, widget.serverId)));
    _init();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total.inMilliseconds > 0
        ? (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final t = context.t;
    final caption = TextStyle(
      fontSize: 13,
      height: 18 / 13,
      color: t.inkSoft,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final total =
        _total > Duration.zero ? formatMmSs(_total.inSeconds) : widget.duration;

    final Widget control;
    if (_failed) {
      control = Column(
        children: [
          Text(
            "Couldn't load this voice message.",
            textAlign: TextAlign.center,
            style: caption,
          ),
          AppButton(
            variant: AppButtonVariant.text,
            onPressed: _retry,
            child: const Text('Try again'),
          ),
        ],
      );
    } else if (_loading) {
      control = Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: t.surface2, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const BusySpinner(),
      );
    } else {
      control = Semantics(
        button: true,
        label: _playing ? 'Pause' : 'Play',
        // excludeSemantics drops the child's tap; give it back here.
        onTap: () => _playing ? _player.pause() : _player.play(),
        excludeSemantics: true,
        child: Material(
          color: t.accent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _playing ? _player.pause() : _player.play(),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 32,
                color: t.onAccent,
              ),
            ),
          ),
        ),
      );
    }

    return AppSheetChrome(
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
              ),
              child: Icon(Icons.mic_none_rounded, color: t.inkSoft),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                kMediaRowVoiceLabel,
                style: TextStyle(
                  fontSize: 16,
                  height: 22 / 16,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusPill),
          child: LinearProgressIndicator(
            value:           progress,
            backgroundColor: t.surface2,
            valueColor:      AlwaysStoppedAnimation(t.accent),
            minHeight:       4,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatMmSs(_pos.inSeconds), style: caption),
            Text(total,      style: caption),
          ],
        ),
        const SizedBox(height: 12),
        Center(child: control),
      ],
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
      loading: () => const Center(child: BusySpinner()),
      error: (_, __) => _LoadFailed(
        (conversationId: conversationId, mediaType: 'document'),
      ),
      data: (items) {
        if (items.isEmpty) {
          return _emptyState(context, 'No documents yet', Icons.folder_open_outlined);
        }
        final live = _withoutDeleted(ref, conversationId, items);
        final visible = live.where((r) => !isExpired(_expiresAt(r))).toList();
        final hiddenCount = live.length - visible.length;
        if (visible.isEmpty) {
          return _emptyState(context, 'No documents yet', Icons.folder_open_outlined);
        }
        return Column(
          children: [
            if (hiddenCount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: Text(
                  '$hiddenCount expired item${hiddenCount == 1 ? '' : 's'} hidden',
                  style: TextStyle(
                      fontSize: 13, height: 18 / 13, color: context.t.inkSoft),
                ),
              ),
            Expanded(
              child: ListView.separated(
          itemCount:    visible.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder:  (context, i) {
            final r        = visible[i];
            final serverId = r.getStringValue('message_id');
            final fileName =
                r.data['file_name']?.toString() ?? kMediaRowDocumentLabel;
            final size     =
                formatFileSize(r.data['file_size'], bytesUnitSpaced: false);
            final date     = _formatDate(r.data['created']?.toString() ?? '');
            return ListTile(
              leading: _RowTile(_docIcon(fileName)),
              title:    Text(fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowTitle(context)),
              subtitle: Text('$size · $date', style: _rowMeta(context)),
              trailing:
                  Icon(Icons.download_outlined, color: context.t.inkSoft),
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
      final doc = mediaFileProvider(MediaRef(conversationId, serverId));
      // A failed or empty load stays cached: drop it, or this tap replays it.
      final cached = ref.read(doc);
      if (!cached.isLoading &&
          (cached.hasError || (cached.hasValue && cached.value == null))) {
        ref.invalidate(doc);
      }
      // Download + decrypt the document to a local file, then open it.
      final media = await ref.read(doc.future);
      if (media == null) throw Exception('No media found');

      await OpenFile.open(media.file.path);
    } catch (e) {
      debugPrint('[DocsTab] Open failed: $e');
      if (context.mounted) {
        showToast(context, "Couldn't open the file. Try again.", error: true);
      }
    }
  }
}
