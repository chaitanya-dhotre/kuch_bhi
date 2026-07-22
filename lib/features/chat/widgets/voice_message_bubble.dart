import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/media_utils.dart';
import '../providers/chat_provider.dart';

class VoiceMessageBubble extends ConsumerStatefulWidget {
  const VoiceMessageBubble({
    super.key,
    required this.conversationId,
    required this.serverId,
    required this.isMine,
    this.durationText,
    this.status,
    this.createdAt,
  });

  final String   conversationId;
  final String   serverId;
  final bool     isMine;
  final String?  durationText;
  final String?  status;
  final DateTime? createdAt;

  @override
  ConsumerState<VoiceMessageBubble> createState() =>
      _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends ConsumerState<VoiceMessageBubble> {
  final _player = AudioPlayer();

  bool    _isLoading   = false;
  bool    _hasError    = false;
  String? _cachedPath;

  Duration _position  = Duration.zero;
  Duration _total     = Duration.zero;
  bool     _isPlaying = false;

  double _speed = 1.0;
  static const _speeds = [1.0, 1.5, 2.0];

  @override
  void initState() {
    super.initState();

    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.durationStream.listen((dur) {
      if (mounted && dur != null) setState(() => _total = dur);
    });

    _player.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing = state.playing &&
          state.processingState != ProcessingState.completed;
      setState(() => _isPlaying = playing);
      if (state.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _loadAndPlay() async {
    if (_cachedPath != null) {
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.play();
      }
      return;
    }

    setState(() { _isLoading = true; _hasError = false; });

    try {
      // Download + decrypt the voice note to a local file, then play it.
      final media = await ref.read(mediaFileProvider(
          MediaRef(widget.conversationId, widget.serverId)).future);
      if (media == null) throw Exception('No media found');

      _cachedPath = media.file.path;
      await _player.setFilePath(_cachedPath!);
      await _player.setSpeed(_speed);
      await _player.play();
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _cycleSpeed() {
    final idx = _speeds.indexOf(_speed);
    setState(() => _speed = _speeds[(idx + 1) % _speeds.length]);
    _player.setSpeed(_speed);
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bubbleColor = widget.isMine
        ? AppColors.sentBubble
        : isDark
            ? AppColors.receivedBubbleDark
            : AppColors.receivedBubbleLight;

    final onBubble = widget.isMine
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;

    final progress = _total.inMilliseconds > 0
        ? (_position.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final displayDuration = _total > Duration.zero
        ? _fmtDur(_total - _position)
        : widget.durationText ?? '0:00';

    final mediaAsync  = ref.watch(mediaFileProvider(
        MediaRef(widget.conversationId, widget.serverId)));
    final expiresAt   = mediaAsync.valueOrNull?.expiresAt;
    final expired     = isExpired(expiresAt);
    final badgeText   = expiryBadgeText(expiresAt);

    // ── Expired state ───────────────────────────────────────
    if (expired) {
      return Container(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_off_outlined, color: Colors.grey, size: 20),
            SizedBox(width: 8),
            Text('Media expired', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset:     const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Play / pause / loading
              GestureDetector(
                onTap: _loadAndPlay,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isMine
                        ? Colors.white.withValues(alpha: 0.25)
                        : AppColors.primary.withValues(alpha: 0.15),
                  ),
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : _hasError
                          ? const Icon(Icons.error_outline,
                              color: AppColors.error, size: 22)
                          : Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: widget.isMine
                                  ? Colors.white
                                  : AppColors.primary,
                              size: 24,
                            ),
                ),
              ),

              const SizedBox(width: 10),

              // Progress + duration
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value:            progress,
                      backgroundColor:  onBubble.withValues(alpha: 0.2),
                      valueColor:       AlwaysStoppedAnimation<Color>(
                        widget.isMine
                            ? Colors.white
                            : AppColors.primary,
                      ),
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayDuration,
                      style: TextStyle(
                        fontSize: 11,
                        color: onBubble.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Speed toggle
              GestureDetector(
                onTap: _cycleSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: onBubble.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_speed == _speed.truncateToDouble() ? _speed.toInt() : _speed}×',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: onBubble.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // ── Expiry label ──────────────────────────────────────
          if (badgeText != null) ...[  
            const SizedBox(height: 4),
            Text(
              badgeText,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          // ── Timestamp + tick ───────────────────────────────────
          if (widget.createdAt != null || widget.status != null) ...[  
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize:      MainAxisSize.max,
              children: [
                if (widget.createdAt != null)
                  Text(
                    DateFormat('HH:mm').format(widget.createdAt!.toLocal()),
                    style: TextStyle(
                      fontSize: 10,
                      color: onBubble.withValues(alpha: 0.6),
                    ),
                  ),
                if (widget.isMine && widget.status != null) ...[
                  const SizedBox(width: 4),
                  _VoiceTickIndicator(status: widget.status!, isMine: widget.isMine),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Tick indicator for voice bubble ─────────────────────────────────────

class _VoiceTickIndicator extends StatelessWidget {
  const _VoiceTickIndicator({required this.status, required this.isMine});
  final String status;
  final bool   isMine;

  @override
  Widget build(BuildContext context) {
    final color = isMine ? Colors.white70 : Colors.grey;
    if (status == 'pending') {
      return SizedBox(
        width: 10, height: 10,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
      );
    }
    if (status == 'read') {
      return Icon(Icons.done_all, size: 12,
          color: isMine ? Colors.white : AppColors.primary);
    }
    if (status == 'delivered') {
      return Icon(Icons.done_all, size: 12, color: color);
    }
    if (status == 'sent') {
      return Icon(Icons.done, size: 12, color: color);
    }
    return Icon(Icons.schedule, size: 12, color: color);
  }
}
