import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../message_offline_policy.dart';
import '../providers/chat_provider.dart';
import 'expiry_badge.dart';

class VoiceMessageBubble extends ConsumerStatefulWidget {
  const VoiceMessageBubble({
    super.key,
    required this.conversationId,
    required this.serverId,
    required this.isMine,
    this.runEnd = true,
    this.durationText,
    this.status,
    this.createdAt,
  });

  final String conversationId;
  final String serverId;
  final bool isMine;
  final bool runEnd;
  final String? durationText;
  final String? status;
  final DateTime? createdAt;

  @override
  ConsumerState<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends ConsumerState<VoiceMessageBubble> {
  final _player = AudioPlayer();

  bool _isLoading = false;
  bool _hasError = false;
  String? _cachedPath;

  Duration _position = Duration.zero;
  Duration _total = Duration.zero;
  bool _isPlaying = false;

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
      final playing =
          state.playing && state.processingState != ProcessingState.completed;
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

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final voice = mediaFileProvider(
        MediaRef(widget.conversationId, widget.serverId),
      );
      // A failed or empty load stays cached: drop it, or this tap replays it.
      final cached = ref.read(voice);
      if (!cached.isLoading &&
          (cached.hasError || (cached.hasValue && cached.value == null))) {
        ref.invalidate(voice);
      }
      // Download + decrypt the voice note to a local file, then play it.
      final media = await ref.read(voice.future);
      if (media == null) throw Exception('No media found');

      _cachedPath = media.file.path;
      await _player.setFilePath(_cachedPath!);
      await _player.setSpeed(_speed);
      // play() completes only when playback stops; awaiting it kept the
      // spinner up for the whole clip.
      unawaited(_player.play());
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

  @override
  Widget build(BuildContext context) {
    final onBubble = widget.isMine
        ? context
              .t
              .onAccent // on the marigold sent bubble (never raw white)
        : context.t.ink;

    final progress = _total.inMilliseconds > 0
        ? (_position.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final displayDuration = _total > Duration.zero
        ? '${formatMmSs((_total - _position).inSeconds)} / ${formatMmSs(_total.inSeconds)}'
        : widget.durationText ?? '0:00';

    // Purged on the server for sure: no download, no retry.
    final gone = isPastRetention('voice', widget.createdAt);
    final mediaAsync = gone
        ? const AsyncData(null)
        : ref.watch(
            mediaFileProvider(MediaRef(widget.conversationId, widget.serverId)),
          );
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    // A failed load cannot be retried offline; reconnect re-enables the tap.
    final retryOffline = _hasError && !online;
    final expiresAt = mediaAsync.valueOrNull?.expiresAt;
    final expired = gone || isExpired(expiresAt);
    final badgeText = compactExpiryLabel(expiresAt);

    // ── Expired state ───────────────────────────────────────
    if (expired) {
      return ChatBubbleFrame(
        isMine: widget.isMine,
        runEnd: widget.runEnd,
        fillWidth: true,
        showTimestamp: true,
        timestampOverlay: false,
        createdAt: widget.createdAt,
        status: widget.status,
        child: ExpiredPlaceholder(
          glyph: Icons.timer_off_outlined,
          decorate: false,
          inline: true,
          ink: widget.isMine
              ? context.t.onAccent.withValues(alpha: 0.70)
              : null,
        ),
      );
    }

    return ChatBubbleFrame(
      isMine: widget.isMine,
      runEnd: widget.runEnd,
      fillWidth: true,
      showTimestamp: true,
      timestampOverlay: false,
      createdAt: widget.createdAt,
      status: widget.status,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Play / pause / loading
                  Semantics(
                    button: true,
                    enabled: !retryOffline,
                    label: _hasError
                        ? "Voice message didn't load. "
                              '${online ? 'Tap to retry' : kOfflineActionHint}'
                        : _isPlaying
                        ? 'Pause voice message'
                        : 'Play voice message',
                    child: GestureDetector(
                      onTap: retryOffline ? null : _loadAndPlay,
                      child: Opacity(
                        opacity: retryOffline ? .38 : 1,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.isMine
                                ? context.t.onAccent.withValues(alpha: 0.16)
                                : context.t.accent.withValues(alpha: 0.15),
                          ),
                          child: _isLoading
                              ? BusySpinner(
                                  size: 16,
                                  strokeWidth: 2,
                                  color: widget.isMine
                                      ? context.t.onAccent
                                      : context.t.accent,
                                )
                              : _hasError
                              ? Icon(
                                  Icons.error_outline,
                                  color: context.t.error,
                                  size: 22,
                                )
                              : Icon(
                                  _isPlaying ? Icons.pause : Icons.play_arrow,
                                  color: widget.isMine
                                      ? context.t.onAccent
                                      : context.t.accent,
                                  size: 20,
                                ),
                        ),
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
                          value: progress,
                          backgroundColor: onBubble.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            widget.isMine
                                ? context.t.onAccent
                                : context.t.accent,
                          ),
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          retryOffline ? kOfflineActionHint : displayDuration,
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
                  Semantics(
                    button: true,
                    label: 'Playback speed',
                    child: GestureDetector(
                      onTap: _cycleSpeed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
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
                  ),
                ],
              ),
            ],
          ),
          if (badgeText != null) ExpiryBadge(label: badgeText),
        ],
      ),
    );
  }
}
