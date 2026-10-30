import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../services/media_upload_service.dart';
import '../../chat/message_offline_policy.dart';
import '../../chat/providers/chat_provider.dart';
import '../../chat/widgets/expiry_badge.dart';
import '../../settings/providers/font_provider.dart';
import '../providers/media_viewer_providers.dart';

/// What the viewer needs to open at once; the full file is loaded inside it.
class MediaViewerArgs {
  const MediaViewerArgs({
    required this.conversationId,
    required this.serverId,
    required this.mediaType,
    required this.senderName,
    required this.timestamp,
    this.heroTag,
    this.thumbPath,
  });

  final String conversationId;
  final String serverId;
  final String mediaType; // 'image' | 'video'
  final String senderName;
  final DateTime timestamp;
  final String? heroTag;

  /// The decrypted thumbnail the caller already shows (poster + Hero).
  final String? thumbPath;
}

/// A5: pushes the viewer now, on a see-through fade route. Never await a
/// load before calling this.
void pushMediaViewer(BuildContext context, MediaViewerArgs args) {
  final still = MediaQuery.disableAnimationsOf(context);
  Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: still ? Duration.zero : WarmPopTokens.motionBase,
    reverseTransitionDuration: still ? Duration.zero : WarmPopTokens.motionFast,
    pageBuilder: (_, __, ___) => MediaViewerScreen(args: args),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
}

enum _View { loading, loaded, loadFailed, expired, cantDecrypt, playFailed }

/// C10: the one fullscreen viewer for photos and videos.
class MediaViewerScreen extends ConsumerStatefulWidget {
  const MediaViewerScreen({super.key, required this.args});

  final MediaViewerArgs args;

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _full =
      MediaRef(widget.args.conversationId, widget.args.serverId);
  bool get _isVideo => widget.args.mediaType == 'video';

  bool _chrome = true;
  bool _saving = false;
  bool _sharing = false;
  bool _decodeFailed = false;

  final _zoom = TransformationController();
  late final _zoomAnim =
      AnimationController(vsync: this, duration: WarmPopTokens.motionBase);
  Animation<Matrix4>? _zoomTween;
  bool _zoomed = false;
  Offset _doubleTapAt = Offset.zero;
  Orientation? _orientation;

  double _dragDy = 0;
  double _snapFrom = 0;
  late final _snapAnim =
      AnimationController(vsync: this, duration: WarmPopTokens.motionFast);

  VideoPlayerController? _video;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.addObserver(this);
    _zoom.addListener(_onZoom);
    _zoomAnim.addListener(() => _zoom.value = _zoomTween!.value);
    _snapAnim.addListener(
        () => setState(() => _dragDy = _snapFrom * (1 - _snapAnim.value)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    if (_orientation == null) _start();
    // H2: a zoomed photo resets to fit on rotation.
    if (_orientation != null && orientation != _orientation) {
      _zoomAnim.stop();
      _zoomed = false;
      _zoom.value = Matrix4.identity();
    }
    _orientation = orientation;
  }

  /// Once, on the first dependencies pass (invalidate is not allowed in
  /// initState).
  void _start() {
    // D6: a failure cached by an earlier attempt is not this viewer's load.
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
      ref.listenManual(mediaFileProvider(_full), (_, next) {
        final file = next.valueOrNull;
        if (next.isLoading || file == null || _video != null) return;
        if (!isExpired(file.expiresAt)) _initVideo(file.file);
      }, fireImmediately: true);
    }
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
    _video?.dispose();
    _zoomAnim.dispose();
    _snapAnim.dispose();
    _zoom.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
  }

  void _onVideoTick() {
    if (!mounted) return;
    // E3: at the end the chrome comes back with Play again.
    if (_video?.value.isCompleted ?? false) _setChrome(true);
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

  void _onZoom() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _setChrome(bool shown) {
    if (shown == _chrome) return;
    SystemChrome.setEnabledSystemUIMode(
        shown ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
    setState(() => _chrome = shown);
  }

  void _onTap() {
    // B4: under TalkBack the chrome never hides.
    if (MediaQuery.accessibleNavigationOf(context)) return;
    _setChrome(!_chrome);
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

  void _onDragUpdate(DragUpdateDetails d) {
    _snapAnim.stop();
    setState(() => _dragDy += d.delta.dy);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragDy.abs() > 120 || (d.primaryVelocity ?? 0).abs() > 600) {
      Navigator.of(context).pop();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      setState(() => _dragDy = 0);
      return;
    }
    _snapFrom = _dragDy;
    _snapAnim.forward(from: 0);
  }

  Future<void> _save(BuildContext context, LocalMediaFile file) async {
    if (_saving) return;
    setState(() => _saving = true);
    var message = 'Saved to gallery';
    var error = true;
    try {
      final saved = await ref
          .read(mediaActionsProvider)
          .save(file.file.path, video: _isVideo);
      if (saved) {
        error = false;
      } else {
        message = 'Allow photo access in Settings to save.';
      }
    } on GalException catch (e) {
      debugPrint('[MediaViewer] save failed: $e');
      message = switch (e.type) {
        GalExceptionType.accessDenied => 'Allow photo access in Settings to save.',
        GalExceptionType.notEnoughSpace => 'Not enough space to save.',
        _ => "Couldn't save. Try again.",
      };
    } catch (e) {
      debugPrint('[MediaViewer] save failed: $e');
      message = "Couldn't save. Try again.";
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (context.mounted) showToast(context, message, error: error);
  }

  Future<void> _share(BuildContext context, LocalMediaFile file) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    var failed = false;
    try {
      // A dismissed share sheet returns normally; it is not an error.
      await ref.read(mediaActionsProvider).share(file.file.path);
    } catch (e) {
      debugPrint('[MediaViewer] share failed: $e');
      failed = true;
    }
    if (!mounted) return;
    setState(() => _sharing = false);
    if (failed && context.mounted) {
      showToast(context, "Couldn't share.", error: true);
    }
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
    final font = ref.watch(fontFamilyProvider).valueOrNull?.fontFamily;
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
    // B1: black in every app theme.
    return Theme(
      data: warmPopDark(amoled: true, fontFamily: font),
      child: Builder(
          builder: (context) => _build(context, view, file, online)),
    );
  }

  Widget _build(
      BuildContext context, _View view, LocalMediaFile? file, bool online) {
    final t = context.t;
    final still = MediaQuery.disableAnimationsOf(context);
    final shown = _chrome || MediaQuery.accessibleNavigationOf(context);
    final video = _video;
    final playing = video != null && video.value.isInitialized;
    final busy = view == _View.loading ||
        (_isVideo && view == _View.loaded && !playing);
    final clear = t.bg.withValues(alpha: 0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: clear,
        systemNavigationBarColor: clear,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: clear,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // The chrome sits outside this detector, so its buttons never
            // wait out the photo's double-tap timeout.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTap,
              onDoubleTapDown: _isVideo || file == null
                  ? null
                  : (d) => _doubleTapAt = d.localPosition,
              onDoubleTap: _isVideo || file == null ? null : _onDoubleTap,
              onVerticalDragUpdate: _zoomed ? null : _onDragUpdate,
              onVerticalDragEnd: _zoomed ? null : _onDragEnd,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // C3: the ground fades as the media is dragged away.
                  ColoredBox(
                    color: t.bg.withValues(
                        alpha: (1 - _dragDy.abs() / 300).clamp(0.3, 1.0)),
                  ),
                  Transform.translate(
                    offset: Offset(0, _dragDy),
                    child: view == _View.loading || view == _View.loaded
                        ? _media(context, file, still)
                        : _block(context, view, online),
                  ),
                  // Only a real load waits on the network.
              if (busy) _busy(context, online || view != _View.loading),
                ],
              ),
            ),
            _chromeLayer(
              shown,
              still,
              Align(
                alignment: Alignment.topCenter,
                child: _bar(context, file),
              ),
            ),
            if (playing && view == _View.loaded)
              _chromeLayer(shown, still, _videoControls(context, video)),
          ],
        ),
      ),
    );
  }

  String get _date =>
      DateFormat('MMM d, yyyy · HH:mm').format(widget.args.timestamp.toLocal());

  Widget _chromeLayer(bool shown, bool still, Widget child) => AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: still ? Duration.zero : WarmPopTokens.motionFast,
        child: IgnorePointer(
          ignoring: !shown,
          child: ExcludeSemantics(excluding: !shown, child: child),
        ),
      );

  Widget _media(BuildContext context, LocalMediaFile? file, bool still) {
    final a = widget.args;
    final kind = _isVideo ? 'Video' : 'Photo';
    Widget? poster = a.thumbPath == null
        ? null
        : Image.file(
            File(a.thumbPath!),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
    // G1/G2: the thumbnail flies; no Hero at all under reduced motion.
    if (poster != null && a.heroTag != null && !still) {
      poster = Hero(tag: a.heroTag!, child: poster);
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
      media = InteractiveViewer(
        transformationController: _zoom,
        minScale: 1,
        maxScale: 4,
        child: media,
      );
    }
    return Semantics(
      container: true,
      image: true,
      excludeSemantics: true,
      // Media & docs passes the fallback word itself as the sender.
      label: a.senderName == kind
          ? '$kind, $_date'
          : '$kind from ${a.senderName}, $_date',
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

  Widget _bar(BuildContext context, LocalMediaFile? file) {
    final t = context.t;
    final expiry = file == null ? null : viewerExpiryLabel(file.expiresAt);
    return ColoredBox(
      // B3: flat 64% scrim, no gradient (C1).
      color: t.bg.withValues(alpha: .64),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Close',
                color: t.ink,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.args.senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          height: 22 / 16, color: t.ink),
                    ),
                    Text(
                      _date,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _caption(context),
                    ),
                    if (expiry != null)
                      Text(
                        expiry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _caption(context),
                      ),
                  ],
                ),
              ),
              // B5: actions only once the full file is here.
              if (file != null) ...[
                IconButton(
                  tooltip: 'Share',
                  color: t.ink,
                  onPressed: () => _share(context, file),
                  icon: _sharing
                      ? const BusySpinner(size: 24)
                      : const Icon(Icons.share_outlined),
                ),
                IconButton(
                  tooltip: 'Save to gallery',
                  color: t.ink,
                  onPressed: () => _save(context, file),
                  icon: _saving
                      ? const BusySpinner(size: 24)
                      : const Icon(Icons.download_outlined),
                ),
              ],
            ],
          ),
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
            onPressed: v.isPlaying ? video.pause : video.play,
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
