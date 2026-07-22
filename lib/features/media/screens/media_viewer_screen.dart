import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_colors.dart';

// ── Args passed via GoRouter extra or MaterialPageRoute ──────────────────────

class MediaViewerArgs {
  const MediaViewerArgs({
    required this.localPath,
    required this.mediaType,
    required this.senderName,
    required this.timestamp,
    this.heroTag,
  });

  /// Path to the already-decrypted local file (media is E2E-encrypted, so we
  /// never load it directly from a server URL).
  final String  localPath;
  final String  mediaType;   // 'image' | 'video'
  final String  senderName;
  final DateTime timestamp;
  final String? heroTag;
}

// ── Screen ────────────────────────────────────────────────────────────────────

class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({super.key, required this.args});

  final MediaViewerArgs args;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen>
    with SingleTickerProviderStateMixin {
  // ── shared state
  bool _barsVisible   = true;
  bool _isDownloading = false;
  bool _isSharing     = false;

  // ── video state
  VideoPlayerController? _videoCtrl;
  ChewieController?      _chewieCtrl;

  // ── swipe-to-close state
  double _dragOffset = 0;

  late final AnimationController _barAnimCtrl;
  late final Animation<double>   _barAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _barAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1,
    );
    _barAnim = CurvedAnimation(parent: _barAnimCtrl, curve: Curves.easeInOut);

    if (widget.args.mediaType == 'video') _initVideoPlayer();
  }

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _videoCtrl?.dispose();
    _barAnimCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  // ── video initialisation ─────────────────────────────────────────────────

  Future<void> _initVideoPlayer() async {
    _videoCtrl = VideoPlayerController.file(File(widget.args.localPath));
    await _videoCtrl!.initialize();
    if (!mounted) return;

    _chewieCtrl = ChewieController(
      videoPlayerController: _videoCtrl!,
      autoPlay:        true,
      looping:         false,
      allowFullScreen: false,
      allowMuting:     true,
      showControls:    true,
      materialProgressColors: ChewieProgressColors(
        playedColor:    AppColors.primary,
        handleColor:    AppColors.primary,
        backgroundColor: Colors.grey,
        bufferedColor:  Colors.white54,
      ),
    );
    setState(() {});
  }

  // ── toggle bars ──────────────────────────────────────────────────────────

  void _toggleBars() {
    setState(() => _barsVisible = !_barsVisible);
    if (_barsVisible) {
      _barAnimCtrl.forward();
    } else {
      _barAnimCtrl.reverse();
    }
  }

  // ── actions ──────────────────────────────────────────────────────────────

  Future<void> _share() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      await Share.shareXFiles(
        [XFile(widget.args.localPath)],
        subject: 'Shared from Kuch Bhi',
      );
    } catch (e) {
      debugPrint('[MediaViewer] Share failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Future<void> _download() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final file = File(widget.args.localPath);
      if (widget.args.mediaType == 'video') {
        await Gal.putVideo(file.path);
      } else {
        await Gal.putImageBytes(await file.readAsBytes());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:  Text('Saved to gallery'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[MediaViewer] Download failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.args.mediaType == 'video';

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleBars,
        onVerticalDragUpdate: (d) {
          if (isVideo) return; // disable swipe-close for video
          setState(() => _dragOffset += d.delta.dy);
        },
        onVerticalDragEnd: (d) {
          if (isVideo) return;
          if (_dragOffset.abs() > 120 ||
              d.primaryVelocity != null && d.primaryVelocity!.abs() > 600) {
            Navigator.of(context).pop();
          } else {
            setState(() => _dragOffset = 0);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Media content ─────────────────────────────────────────
            Transform.translate(
              offset: Offset(0, _dragOffset),
              child: isVideo ? _buildVideo() : _buildImage(),
            ),

            // ── Top bar: sender + timestamp ───────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: FadeTransition(
                opacity: _barAnim,
                child: _TopBar(
                  senderName: widget.args.senderName,
                  timestamp:  widget.args.timestamp,
                  onClose:    () => Navigator.of(context).pop(),
                ),
              ),
            ),

            // ── Bottom bar: share + download ──────────────────────────
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: FadeTransition(
                opacity: _barAnim,
                child: _BottomBar(
                  isDownloading: _isDownloading,
                  isSharing:     _isSharing,
                  onShare:       _share,
                  onDownload:    _download,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    final imageWidget = PhotoView(
      imageProvider: FileImage(File(widget.args.localPath)),
      minScale:            PhotoViewComputedScale.contained,
      maxScale:            PhotoViewComputedScale.covered * 4,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      loadingBuilder: (_, __) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image, color: Colors.white70, size: 64),
      ),
    );

    if (widget.args.heroTag != null) {
      return Hero(tag: widget.args.heroTag!, child: imageWidget);
    }
    return imageWidget;
  }

  Widget _buildVideo() {
    if (_chewieCtrl == null ||
        !_chewieCtrl!.videoPlayerController.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(child: Chewie(controller: _chewieCtrl!));
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.senderName,
    required this.timestamp,
    required this.onClose,
  });

  final String   senderName;
  final DateTime timestamp;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize:       MainAxisSize.min,
                  children: [
                    Text(
                      senderName,
                      style: const TextStyle(
                        color:      Colors.white,
                        fontSize:   15,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      DateFormat('MMM d, yyyy · HH:mm').format(timestamp.toLocal()),
                      style: const TextStyle(
                        color:   Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom bar ────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.isDownloading,
    required this.isSharing,
    required this.onShare,
    required this.onDownload,
  });

  final bool isDownloading;
  final bool isSharing;
  final VoidCallback onShare;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end:   Alignment.topCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Share
              _ActionButton(
                icon:    Icons.share_outlined,
                label:   'Share',
                loading: isSharing,
                onTap:   onShare,
              ),
              // Download
              _ActionButton(
                icon:    Icons.download_outlined,
                label:   'Save',
                loading: isDownloading,
                onTap:   onDownload,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final IconData     icon;
  final String       label;
  final bool         loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          loading
              ? const SizedBox(
                  width:  24,
                  height: 24,
                  child:  CircularProgressIndicator(
                    strokeWidth: 2,
                    color:       Colors.white,
                  ),
                )
              : Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
