import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../services/media_upload_service.dart';
import '../../chat/widgets/expiry_badge.dart';
import '../../chat/widgets/media_retry.dart';
import '../../settings/providers/font_provider.dart';
import '../providers/media_viewer_providers.dart';
import 'media_viewer_page.dart';

/// One item in the viewer's pager. A single open is a pager of one.
class MediaViewerItem {
  const MediaViewerItem({
    required this.serverId,
    required this.mediaType,
    this.heroTag,
    this.thumbPath,
  });

  final String serverId;
  final String mediaType; // 'image' | 'video'
  final String? heroTag;

  /// The decrypted thumbnail the caller already shows (poster + Hero).
  final String? thumbPath;
}

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
    this.items,
    this.initialIndex = 0,
  });

  final String conversationId;
  final String serverId;
  final String mediaType; // 'image' | 'video'
  final String senderName;
  final DateTime timestamp;
  final String? heroTag;

  /// The decrypted thumbnail the caller already shows (poster + Hero).
  final String? thumbPath;

  /// 12.5 E5: the album's items in order. Null = one item (today's viewer).
  final List<MediaViewerItem>? items;
  final int initialIndex;

  List<MediaViewerItem> get allItems => items ??
      [
        MediaViewerItem(
          serverId: serverId,
          mediaType: mediaType,
          heroTag: heroTag,
          thumbPath: thumbPath,
        ),
      ];
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

/// C10 / 12.5 E5: the fullscreen shell. It owns system UI, chrome auto-hide,
/// the top bar, swipe-down and the pager; each page owns its media.
class MediaViewerScreen extends ConsumerStatefulWidget {
  const MediaViewerScreen({super.key, required this.args});

  final MediaViewerArgs args;

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen>
    with TickerProviderStateMixin {
  late final List<MediaViewerItem> _items = widget.args.allItems;
  late final PageController _pager =
      PageController(initialPage: widget.args.initialIndex);
  late int _index = widget.args.initialIndex.clamp(0, _items.length - 1);

  bool _chrome = true;
  bool _saving = false;
  bool _sharing = false;
  bool _zoomed = false;
  bool _videoPlaying = false;
  LocalMediaFile? _pageFile;

  double _dragDy = 0;
  double _snapFrom = 0;
  late final _snapAnim =
      AnimationController(vsync: this, duration: WarmPopTokens.motionFast);

  Timer? _chromeTimer;

  MediaViewerItem get _current => _items[_index];
  bool get _isVideo => _current.mediaType == 'video';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _snapAnim.addListener(
        () => setState(() => _dragDy = _snapFrom * (1 - _snapAnim.value)));
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    _snapAnim.dispose();
    _pager.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _setChrome(bool shown) {
    if (shown == _chrome) return;
    SystemChrome.setEnabledSystemUIMode(
        shown ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
    setState(() => _chrome = shown);
  }

  void _scheduleChromeHide() {
    _chromeTimer?.cancel();
    if (!_videoPlaying || MediaQuery.accessibleNavigationOf(context)) return;
    _chromeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _videoPlaying) _setChrome(false);
    });
  }

  void _onTap() {
    // B4: under TalkBack the chrome never hides.
    if (MediaQuery.accessibleNavigationOf(context)) return;
    _setChrome(!_chrome);
    if (_chrome) {
      _scheduleChromeHide();
    } else {
      _chromeTimer?.cancel();
    }
  }

  void _onVideoPlayingChanged(bool playing) {
    // Ticks arrive every 100 ms while playing: act on a change only, or the
    // 3 s hide timer restarts forever.
    if (!mounted || playing == _videoPlaying) return;
    _videoPlaying = playing;
    if (playing) {
      _scheduleChromeHide();
    } else {
      _chromeTimer?.cancel();
      _setChrome(true);
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _index = index;
      _zoomed = false;
      _dragDy = 0;
      _pageFile = null;
      _videoPlaying = false;
    });
    _chromeTimer?.cancel();
    _setChrome(true);
    if (_items.length > 1) {
      final kind = _isVideo ? kMediaRowVideoLabel : kMediaRowPhotoLabel;
      SemanticsService.sendAnnouncement(
        View.of(context),
        '$kind ${index + 1} of ${_items.length}',
        Directionality.of(context),
      );
    }
  }

  void _onDragUpdate(double dy) {
    _snapAnim.stop();
    setState(() => _dragDy += dy);
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
        _ => kSaveFailedCopy,
      };
    } catch (e) {
      debugPrint('[MediaViewer] save failed: $e');
      message = kSaveFailedCopy;
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

  @override
  Widget build(BuildContext context) {
    final font = ref.watch(fontFamilyProvider).valueOrNull?.fontFamily;
    // B1: black in every app theme.
    return Theme(
      data: warmPopDark(amoled: true, fontFamily: font),
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    final t = context.t;
    final still = MediaQuery.disableAnimationsOf(context);
    final shown = _chrome || MediaQuery.accessibleNavigationOf(context);
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
            // C3: the ground fades as the media is dragged away.
            ColoredBox(
              color: t.bg.withValues(
                  alpha: (1 - _dragDy.abs() / 300).clamp(0.3, 1.0)),
            ),
            Transform.translate(
              offset: Offset(0, _dragDy),
              child: PageView.builder(
                controller: _pager,
                // E6: paging only at fit; a zoomed photo owns horizontal
                // drags for panning.
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                onPageChanged: _onPageChanged,
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final item = _items[i];
                  return MediaViewerPage(
                    key: ValueKey(item.serverId),
                    conversationId: widget.args.conversationId,
                    serverId: item.serverId,
                    mediaType: item.mediaType,
                    senderName: widget.args.senderName,
                    timestamp: widget.args.timestamp,
                    heroTag: item.heroTag ?? mediaHeroTag(item.serverId),
                    thumbPath: item.thumbPath,
                    active: i == _index,
                    chromeShown: shown,
                    onTap: _onTap,
                    onDragUpdate: _onDragUpdate,
                    onDragEnd: _onDragEnd,
                    onZoomChanged: (zoomed) {
                      if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
                    },
                    onVideoPlayingChanged: _onVideoPlayingChanged,
                    onPausePressed: () {
                      _chromeTimer?.cancel();
                      _setChrome(true);
                    },
                    onPlayPressed: _scheduleChromeHide,
                    onFileChanged: (file) {
                      if (!mounted || i != _index) return;
                      if (identical(file, _pageFile)) return;
                      setState(() => _pageFile = file);
                    },
                  );
                },
              ),
            ),
            _chromeLayer(
              shown,
              still,
              Align(
                alignment: Alignment.topCenter,
                child: _bar(context, _pageFile),
              ),
            ),
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

  Widget _bar(BuildContext context, LocalMediaFile? file) {
    final t = context.t;
    final expiry = file == null ? null : viewerExpiryLabel(file.expiresAt);
    final counter = _items.length > 1 ? '${_index + 1} of ${_items.length}' : null;
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.args.senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(height: 22 / 16, color: t.ink),
                          ),
                        ),
                        if (counter != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            counter,
                            maxLines: 1,
                            style: _caption(context)?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ],
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

  TextStyle? _caption(BuildContext context) => Theme.of(context)
      .textTheme
      .bodySmall
      ?.copyWith(height: 18 / 13, color: context.t.ink);
}
