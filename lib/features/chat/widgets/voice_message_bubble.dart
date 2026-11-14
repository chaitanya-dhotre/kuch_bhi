import 'dart:async';
import '../voice_body.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../message_offline_policy.dart';
import '../../media/providers/media_viewer_providers.dart';
import '../providers/chat_provider.dart';
import 'expiry_badge.dart';
import 'media_upload_disc.dart';
import 'voice_waveform.dart';

class VoiceMessageBubble extends ConsumerStatefulWidget {
  const VoiceMessageBubble({
    super.key,
    required this.conversationId,
    required this.serverId,
    required this.isMine,
    this.runStart = true,
    this.durationText,
    this.status,
    this.createdAt,
    this.localId,
    this.waveSeed,
  });

  final String conversationId;
  final String serverId;
  final bool isMine;
  final bool runStart;

  /// D-3 B: the bars come from this id (the message's), the same for both
  /// people. Falls back to [serverId].
  final String? waveSeed;
  final String? durationText;
  final String? status;
  final DateTime? createdAt;
  final String? localId;

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
      // Await the (re)load: right after the invalidate above it is still
      // loading, and reading its value failed the first retry tap. Safe to
      // await: the family is not autoDispose.
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

  /// E3: a tap or drag on the bars seeks, once the note is loaded.
  void _seekTo(double dx, double width) {
    if (_cachedPath == null || _total <= Duration.zero || width <= 0) return;
    final f = (dx / width).clamp(0.0, 1.0);
    _player.seek(_total * f);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final width = ChatBubbleGeometry.attachmentWidthOf(context);

    final progress = _total.inMilliseconds > 0
        ? (_position.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final body = parseVoiceBody(widget.durationText);
    final started =
        _total > Duration.zero && (_isPlaying || _position > Duration.zero);
    final displayDuration = started
        ? formatMmSs(_position.inSeconds)
        : body.duration.isEmpty
        ? '0:00'
        : body.duration;

    // Purged on the server for sure: no download, no retry.
    final gone = isPastRetention('voice', widget.createdAt);
    final mediaAsync = gone
        ? const AsyncData(null)
        : ref.watch(
            mediaFileProvider(MediaRef(widget.conversationId, widget.serverId)),
          );
    final blobStatus = ref
        .watch(
          mediaBlobStatusProvider(
            MediaRef(widget.conversationId, widget.serverId),
          ),
        )
        .valueOrNull;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    // A failed load cannot be retried offline; reconnect re-enables the tap.
    final retryOffline = _hasError && !online;
    final expiresAt = mediaAsync.valueOrNull?.expiresAt;
    final expired =
        gone || isExpired(expiresAt) || blobStatus == MediaBlobStatus.expired;
    final badgeText = compactExpiryLabel(expiresAt);

    // ── Expired state ───────────────────────────────────────
    if (blobStatus == MediaBlobStatus.deadLink ||
        blobStatus == MediaBlobStatus.cantDecrypt ||
        expired) {
      final caption = blobStatus == MediaBlobStatus.cantDecrypt
          ? kMediaCantDecrypt
          : blobStatus == MediaBlobStatus.deadLink
          ? kMediaNoLongerAvailable
          : kMediaExpired;
      return ChatBubbleFrame(
        isMine: widget.isMine,
        runStart: widget.runStart,
        width: width,
        padding: ChatBubbleGeometry.attachmentPadding,
        child: Row(
          children: [
            SizedBox.square(
              dimension: ChatBubbleGeometry.leadingSize,
              child: Icon(
                blobStatus == MediaBlobStatus.cantDecrypt
                    ? Icons.lock_outline
                    : expired
                    ? Icons.timer_off_outlined
                    : Icons.info_outline,
                color: t.inkSoft,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                caption,
                style: TextStyle(
                  color: t.inkSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final Widget lead = widget.localId != null
        ? MediaUploadControl(
            localId: widget.localId!,
            status: widget.status,
            kind: 'Voice message',
            size: ChatBubbleGeometry.leadingSize,
          )
        : Semantics(
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
                  key: const ValueKey('voice-play-disc'),
                  width: ChatBubbleGeometry.leadingSize,
                  height: ChatBubbleGeometry.leadingSize,
                  // E3: the one solid accent spot in a bubble.
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: t.accent,
                  ),
                  child: _isLoading
                      ? BusySpinner(size: 18, strokeWidth: 2, color: t.onAccent)
                      : Icon(
                          _hasError
                              ? Icons.error_outline
                              : _isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: t.onAccent,
                          size: 24,
                        ),
                ),
              ),
            ),
          );

    // D-3: the sender's levels; a body without them gets generated bars.
    final levels =
        body.levels ?? generatedWaveLevels(widget.waveSeed ?? widget.serverId);

    return ChatBubbleFrame(
      isMine: widget.isMine,
      runStart: widget.runStart,
      width: width,
      padding: ChatBubbleGeometry.attachmentPadding,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: [
              lead,
              const SizedBox(width: 10),
              // Offline after a failed load: the hint takes the bars' place,
              // so it wraps instead of overflowing at large text.
              if (retryOffline)
                Expanded(
                  child: Text(
                    kOfflineActionHint,
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: t.inkSoft,
                    ),
                  ),
                )
              else ...[
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) =>
                          _seekTo(d.localPosition.dx, box.maxWidth),
                      onHorizontalDragUpdate: (d) =>
                          _seekTo(d.localPosition.dx, box.maxWidth),
                      child: VoiceWaveform(
                        key: const ValueKey('voice-bubble-wave'),
                        levels: levels,
                        bars: kVoiceBubbleBars,
                        height: 28,
                        progress: progress,
                        restAlpha: 0.3,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  displayDuration,
                  style: TextStyle(
                    fontSize: 13,
                    height: 18 / 13,
                    color: t.inkSoft,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              // E3: speed only while playing.
              if (_isPlaying) ...[
                const SizedBox(width: 6),
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
                        color: t.ink.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(
                          WarmPopTokens.radiusPill,
                        ),
                      ),
                      child: Text(
                        '${_speed == _speed.truncateToDouble() ? _speed.toInt() : _speed}×',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (badgeText != null) ExpiryBadge(label: badgeText),
        ],
      ),
    );
  }
}
