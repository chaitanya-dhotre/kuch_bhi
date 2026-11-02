import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../services/media_upload_service.dart';
import '../../chat/message_offline_policy.dart';
import '../../chat/providers/chat_provider.dart';
import '../../chat/widgets/expiry_badge.dart';
import '../providers/media_viewer_providers.dart';

enum _View { loading, loaded, loadFailed, expired, cantDecrypt, playFailed }

/// 12.5 E5: one item of the pager. Owns the zoom layer, its clamp, double-tap,
/// the video controller and loading / error states. The shell
/// (`MediaViewerScreen`) owns system UI, chrome, the pager and Save / Share.
///
/// Only the [active] (current) page reads the full file; a neighbour shows
/// its thumbnail with the not-downloaded disc until it becomes current (E9).
class MediaViewerPage extends ConsumerStatefulWidget {
  const MediaViewerPage({
    super.key,
    required this.conversationId,
    required this.serverId,
    required this.mediaType,
    required this.senderName,
    required this.timestamp,
    required this.active,
    required this.chromeShown,
    required this.onTap,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onZoomChanged,
    required this.onVideoPlayingChanged,
    required this.onPausePressed,
    required this.onPlayPressed,
    required this.onFileChanged,
    this.heroTag,
    this.thumbPath,
  });

  final String conversationId;
  final String serverId;
  final String mediaType;
  final String senderName;
  final DateTime timestamp;
  final String? heroTag;
  final String? thumbPath;

  /// The pager's current page.
  final bool active;
  final bool chromeShown;

  final VoidCallback onTap;
  final void Function(double dy) onDragUpdate;
  final void Function(DragEndDetails details) onDragEnd;
  final ValueChanged<bool> onZoomChanged;
  final ValueChanged<bool> onVideoPlayingChanged;
  final VoidCallback onPausePressed;
  final VoidCallback onPlayPressed;

  /// The full file this page currently shows (null until loaded / on error),
  /// so the shell's Save and Share act on the current item only.
  final ValueChanged<LocalMediaFile?> onFileChanged;

  @override
  ConsumerState<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends ConsumerState<MediaViewerPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _full = MediaRef(widget.conversationId, widget.serverId);
  bool get _isVideo => widget.mediaType == 'video';

  bool _started = false;
  ProviderSubscription<AsyncValue<LocalMediaFile?>>? _videoSub;

  bool _decodeFailed = false;

  final _zoom = TransformationController();
  // The photo's fitted rect inside the zoom layer (null = size unknown).
  Rect? _photoRect;
  Size _viewport = Size.zero;
  bool _clamping = false;
  late final _zoomAnim =
      AnimationController(vsync: this, duration: WarmPopTokens.motionBase);
  Animation<Matrix4>? _zoomTween;
  bool _zoomed = false;
  Offset _doubleTapAt = Offset.zero;
  Orientation? _orientation;

  VideoPlayerController? _video;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _zoom.addListener(_onZoom);
    _zoomAnim.addListener(() => _zoom.value = _zoomTween!.value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (_orientation == null && widget.active) _start();
    // H2: a zoomed photo resets to fit on rotation.
    if (_orientation != null && orientation != _orientation) {
      _zoomAnim.stop();
      // Not during build: the shell's setState runs after this frame.
      if (_zoomed) {
        _zoomed = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onZoomChanged(false);
        });
      }
      _zoom.value = Matrix4.identity();
    }
    _orientation = orientation;
  }

  @override
  void didUpdateWidget(MediaViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active) _deactivate();
    if (!oldWidget.active && widget.active) _start();
  }

  /// Once per activation (invalidate is not allowed in initState).
  void _start() {
    if (_started) return;
    _started = true;
    // D6: a failure cached by an earlier attempt is not this page's load.
    if (ref.exists(mediaFileProvider(_full))) {
      final cached = ref.read(mediaFileProvider(_full));
      // A load still in flight (an earlier offline open) restarts too; the
      // store shares any download already running.
      if (cached.isLoading ||
          cached.hasError ||
          (cached.hasValue && cached.value == null)) {
        ref.invalidate(mediaFileProvider(_full));
      }
    }
    if (_isVideo) {
      _videoSub = ref.listenManual(mediaFileProvider(_full), (_, next) {
        final file = next.valueOrNull;
        if (next.isLoading || file == null || _video != null) return;
        if (!isExpired(file.expiresAt)) _initVideo(file.file);
      }, fireImmediately: true);
    }
  }

  /// E8: leaving the page pauses and disposes its controller; the full file
  /// stops being read until the page is current again.
  void _deactivate() {
    _videoSub?.close();
    _videoSub = null;
    _started = false;
    _video?.pause();
    _video?.dispose();
    _video = null;
    _videoFailed = false;
    // A partial swipe back reports the file again (Save/Share come back).
    _reportedFile = null;
    // The shell resets its play state and chrome in its own page change.
  }

  // E6: pause before the plugin's own observer records "was playing" at
  // `paused`; otherwise it plays again on resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _video?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoSub?.close();
    _video?.dispose();
    _zoomAnim.dispose();
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _initVideo(File file) async {
    final controller = VideoPlayerController.file(file);
    _video = controller;
    try {
      await controller.initialize();
    } catch (e) {
      debugPrint('[MediaViewer] video init failed: $e');
      if (!mounted || _video != controller) return;
      controller.dispose();
      setState(() {
        _video = null;
        _videoFailed = true;
      });
      return;
    }
    if (!mounted || _video != controller) return;
    controller.addListener(_onVideoTick);
    setState(() {});
    await controller.play();
    widget.onVideoPlayingChanged(true);
  }

  void _onVideoTick() {
    if (!mounted) return;
    widget.onVideoPlayingChanged(_video?.value.isPlaying == true);
    setState(() {});
  }

  /// Any retry drops the cached result first (a failed load stays failed).
  void _retry() {
    final loaded = ref.read(mediaFileProvider(_full)).valueOrNull;
    if (loaded != null) FileImage(loaded.file).evict();
    _video?.dispose();
    setState(() {
      _video = null;
      _videoFailed = false;
      _decodeFailed = false;
    });
    ref.invalidate(mediaBlobStatusProvider(_full));
    ref.invalidate(mediaFileProvider(_full));
  }

  void _setZoomed(bool zoomed) {
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  void _onZoom() {
    _clampZoom();
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _setZoomed(zoomed));
  }

  /// 13.9: while the scaled photo is smaller than the screen on an axis it
  /// stays centred on it; once bigger, its edges can't move inside the
  /// screen's. So zoom and pan never show black past the photo.
  void _clampZoom() {
    final photo = _photoRect;
    if (_clamping || photo == null) return;
    final m = _zoom.value;
    final s = m.getMaxScaleOnAxis();
    final t = m.getTranslation();
    double fit(double tr, double view, double start, double len) {
      final scaled = len * s;
      if (scaled <= view) return (view - scaled) / 2 - start * s;
      return tr.clamp(view - (start + len) * s, -start * s);
    }

    final x = fit(t.x, _viewport.width, photo.left, photo.width);
    final y = fit(t.y, _viewport.height, photo.top, photo.height);
    if ((x - t.x).abs() < 0.01 && (y - t.y).abs() < 0.01) return;
    _clamping = true;
    _zoom.value = m.clone()..setTranslationRaw(x, y, t.z);
    _clamping = false;
  }

  void _onDoubleTap() {
    final p = _doubleTapAt;
    // C2: 2.5× with the tapped point staying under the finger.
    final target = _zoomed
        ? Matrix4.identity()
        : (Matrix4.diagonal3Values(2.5, 2.5, 1)
          ..setTranslationRaw(-p.dx * 1.5, -p.dy * 1.5, 0));
    if (MediaQuery.disableAnimationsOf(context)) {
      _zoom.value = target;
      return;
    }
    _zoomTween = Matrix4Tween(begin: _zoom.value, end: target).animate(
        CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic));
    _zoomAnim.forward(from: 0);
  }

  _View _view(AsyncValue<LocalMediaFile?> load) {
    // D4: a blob already failed for good is shown at once, not after the
    // provider's 45s wait for a media row that will never help.
    final status = ref.watch(mediaBlobStatusProvider(_full));
    final dead = switch (status.valueOrNull) {
      MediaBlobStatus.expired => _View.expired,
      MediaBlobStatus.cantDecrypt => _View.cantDecrypt,
      _ => null,
    };
    if (load.isLoading) return dead ?? _View.loading;
    final file = load.valueOrNull;
    if (file == null) {
      if (status.isLoading) return _View.loading;
      return dead ?? _View.loadFailed;
    }
    if (isExpired(file.expiresAt)) return _View.expired;
    if (_decodeFailed) return _View.loadFailed;
    if (_videoFailed) return _View.playFailed;
    return _View.loaded;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return _idle(context);
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    ref.listen(isOnlineProvider, (prev, next) {
      // D2: back online with nothing loaded → read again.
      if (prev?.valueOrNull == false &&
          next.valueOrNull == true &&
          ref.read(mediaFileProvider(_full)).valueOrNull == null) {
        _retry();
      }
    });
    // The load itself can fail the blob: read its row again when it ends.
    ref.listen(mediaFileProvider(_full), (_, next) {
      if (!next.isLoading) ref.invalidate(mediaBlobStatusProvider(_full));
    });
    final load = ref.watch(mediaFileProvider(_full));
    final view = _view(load);
    final file = view == _View.loaded ? load.valueOrNull : null;
    _reportFile(file);
    return _build(context, view, file, online);
  }

  LocalMediaFile? _reportedFile;

  void _reportFile(LocalMediaFile? file) {
    if (file?.file.path == _reportedFile?.file.path) return;
    _reportedFile = file;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFileChanged(file);
    });
  }

  /// E9: a neighbour is its thumbnail with the not-downloaded disc; it reads
  /// no file until it is current.
  Widget _idle(BuildContext context) {
    final thumb = widget.thumbPath;
    return Semantics(
      image: true,
      label: _isVideo ? kMediaRowVideoLabel : kMediaRowPhotoLabel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null)
            Image.file(
              File(thumb),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          const Center(child: MediaDisc(icon: Icons.download_rounded)),
        ],
      ),
    );
  }

  Widget _build(
      BuildContext context, _View view, LocalMediaFile? file, bool online) {
    final still = MediaQuery.disableAnimationsOf(context);
    final video = _video;
    final playing = video != null && video.value.isInitialized;
    final busy = view == _View.loading ||
        (_isVideo && view == _View.loaded && !playing);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: _isVideo || file == null
          ? null
          : (d) => _doubleTapAt = d.localPosition,
      onDoubleTap: _isVideo || file == null ? null : _onDoubleTap,
      onVerticalDragUpdate:
          _zoomed ? null : (d) => widget.onDragUpdate(d.delta.dy),
      onVerticalDragEnd: _zoomed ? null : widget.onDragEnd,
      child: Stack(
        fit: StackFit.expand,
        children: [
          view == _View.loading || view == _View.loaded
              ? _media(context, file, still)
              : _block(context, view, online),
          if (busy) _busy(context, online || view != _View.loading),
          if (playing && view == _View.loaded)
            _chromeLayer(
              widget.chromeShown || MediaQuery.accessibleNavigationOf(context),
              still,
              _videoControls(context, video),
            ),
        ],
      ),
    );
  }

  String get _date =>
      DateFormat('MMM d, yyyy · HH:mm').format(widget.timestamp.toLocal());

  Widget _chromeLayer(bool shown, bool still, Widget child) => AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: still ? Duration.zero : WarmPopTokens.motionFast,
        child: IgnorePointer(
          ignoring: !shown,
          child: ExcludeSemantics(excluding: !shown, child: child),
        ),
      );

  Widget _media(BuildContext context, LocalMediaFile? file, bool still) {
    final kind = _isVideo ? kMediaRowVideoLabel : kMediaRowPhotoLabel;
    Widget? poster = widget.thumbPath == null
        ? null
        : Image.file(
            File(widget.thumbPath!),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
    // G1/G2: the thumbnail flies; no Hero at all under reduced motion.
    if (poster != null && widget.heroTag != null && !still) {
      poster = Hero(tag: widget.heroTag!, child: poster);
    }
    final video = _video;
    Widget media = Stack(
      fit: StackFit.expand,
      children: [
        if (poster != null) poster,
        if (file != null && !_isVideo)
          Image.file(
            file.file,
            fit: BoxFit.contain,
            // D1: the full photo fades in over the thumbnail.
            frameBuilder: (_, child, frame, sync) => sync
                ? child
                : AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration:
                        still ? Duration.zero : WarmPopTokens.motionFast,
                    child: child,
                  ),
            errorBuilder: (_, e, __) {
              debugPrint('[MediaViewer] photo decode failed: $e');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_decodeFailed) {
                  setState(() => _decodeFailed = true);
                  // Hide the shell's actions in the same frame the block
                  // replaces the photo.
                  widget.onFileChanged(null);
                }
              });
              return const SizedBox.shrink();
            },
          ),
        if (file != null && video != null && video.value.isInitialized)
          Center(
            child: AspectRatio(
              aspectRatio: video.value.aspectRatio,
              child: VideoPlayer(video),
            ),
          ),
      ],
    );
    if (!_isVideo) {
      final content = media;
      final w = file?.width?.toDouble() ?? 0;
      final h = file?.height?.toDouble() ?? 0;
      media = LayoutBuilder(builder: (context, box) {
        _viewport = box.biggest;
        // The photo is drawn contain-centred in the full-screen layer.
        if (w > 0 && h > 0) {
          final fit = math.min(box.maxWidth / w, box.maxHeight / h);
          _photoRect = Rect.fromCenter(
            center: box.biggest.center(Offset.zero),
            width: w * fit,
            height: h * fit,
          );
        } else {
          _photoRect = null;
        }
        return InteractiveViewer(
          transformationController: _zoom,
          minScale: 1,
          maxScale: 4,
          child: content,
        );
      });
    }
    return Semantics(
      container: true,
      image: true,
      excludeSemantics: true,
      // Media & docs passes the fallback word itself as the sender.
      label: widget.senderName == kind
          ? '$kind, $_date'
          : '$kind from ${widget.senderName}, $_date',
      child: media,
    );
  }

  Widget _busy(BuildContext context, bool online) {
    final t = context.t;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BusySpinner(size: 32),
          if (!online) ...[
            const SizedBox(height: 12),
            // D2: on the bar's scrim so it reads over any thumbnail.
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: t.bg.withValues(alpha: .64),
                borderRadius: BorderRadius.circular(WarmPopTokens.radiusPill),
              ),
              child: Text(
                'Waiting for a connection',
                textAlign: TextAlign.center,
                style: _body(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  TextStyle? _body(BuildContext context) => Theme.of(context)
      .textTheme
      .bodyMedium
      ?.copyWith(height: 22 / 15, color: context.t.ink);

  TextStyle? _caption(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall
      ?.copyWith(height: 18 / 13, color: context.t.ink);

  Widget _block(BuildContext context, _View view, bool online) {
    final t = context.t;
    final noun = _isVideo ? 'video' : 'photo';
    final (icon, copy, retry) = switch (view) {
      _View.expired => (Icons.timer_off_outlined, 'This $noun has expired.', false),
      _View.cantDecrypt => (Icons.lock_outline, "Can't decrypt", false),
      _View.playFailed => (Icons.error_outline, "Couldn't play this video.", true),
      _ => (Icons.error_outline, "Couldn't load this $noun.", true),
    };
    // D3: only a fresh download needs the network.
    final dim = !online && view == _View.loadFailed && !_decodeFailed;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: t.ink),
            const SizedBox(height: 12),
            Text(copy, textAlign: TextAlign.center, style: _body(context)),
            if (retry) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Opacity(
                    opacity: dim ? .38 : 1,
                    child: AppButton(
                      variant: AppButtonVariant.secondary,
                      onPressed: dim ? null : _retry,
                      child: const Text('Try again'),
                    ),
                  ),
                  if (dim) Text(kOfflineActionHint, style: _caption(context)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _clock(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _videoControls(BuildContext context, VideoPlayerController video) {
    final t = context.t;
    final v = video.value;
    final (icon, label) = v.isCompleted
        ? (Icons.replay, 'Play again')
        : v.isPlaying
            ? (Icons.pause, 'Pause')
            : (Icons.play_arrow, 'Play');
    final clock = _caption(context)
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Stack(
      children: [
        Center(
          child: IconButton(
            tooltip: label,
            iconSize: 32,
            style: IconButton.styleFrom(
              backgroundColor: t.accent,
              foregroundColor: t.onAccent,
              fixedSize: const Size.square(64),
            ),
            // play() restarts from 0 at the end.
            onPressed: () {
              if (v.isPlaying) {
                widget.onPausePressed();
                video.pause();
              } else {
                video.play();
                widget.onPlayPressed();
              }
            },
            icon: Icon(icon),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ColoredBox(
            color: t.bg.withValues(alpha: .64),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(_clock(v.position), style: clock),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        container: true,
                        label: 'Video position',
                        child: VideoProgressIndicator(
                          video,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          colors: VideoProgressColors(
                            playedColor: t.accent,
                            bufferedColor: t.ink.withValues(alpha: .4),
                            backgroundColor: t.ink.withValues(alpha: .16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(_clock(v.duration), style: clock),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
