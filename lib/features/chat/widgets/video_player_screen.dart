import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_colors.dart';

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.url});

  final String url;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _videoCtrl;
  ChewieController? _chewieCtrl;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _downloadVideo() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      final response = await HttpClient().getUrl(Uri.parse(widget.url));
      final body    = await response.close();
      final bytes   = await body.expand((b) => b).toList();

      final tmpDir  = await getTemporaryDirectory();
      final ts      = DateTime.now().millisecondsSinceEpoch;
      final outPath = '${tmpDir.path}/kb_video_$ts.mp4';
      final file    = File(outPath);
      await file.writeAsBytes(bytes);

      await Gal.putVideo(file.path);
      await file.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved to gallery'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[VideoPlayer] Download failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _initPlayer() async {
    _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    await _videoCtrl.initialize();

    if (!mounted) return;

    _chewieCtrl = ChewieController(
      videoPlayerController: _videoCtrl,
      autoPlay: true,
      looping: false,
      allowFullScreen: false,
      allowMuting: true,
      showControls: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: AppColors.primary,
        handleColor: AppColors.primary,
        backgroundColor: Colors.grey,
        bufferedColor: Colors.white54,
      ),
    );
    setState(() {});
  }

  @override
  void dispose() {
    _chewieCtrl?.dispose();
    _videoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: Colors.white),
        ),
        actions: [
          if (_isDownloading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _downloadVideo,
              icon: const Icon(Icons.download, color: Colors.white),
            ),
        ],
      ),
      body: Center(
        child: _chewieCtrl != null &&
                _chewieCtrl!.videoPlayerController.value.isInitialized
            ? Chewie(controller: _chewieCtrl!)
            : const CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
