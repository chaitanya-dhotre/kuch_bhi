import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/busy_spinner.dart';
import 'voice_waveform.dart';

enum VoiceRecorderPanelMode { locked, paused, preview }

class VoiceHoldStrip extends StatefulWidget {
  const VoiceHoldStrip({
    super.key,
    required this.elapsed,
    required this.levels,
    required this.dragX,
    required this.dragY,
    required this.cancelled,
    required this.pulse,
  });

  final Duration elapsed;
  final List<double> levels;
  final double dragX;
  final double dragY;
  final bool cancelled;
  final Animation<double> pulse;

  @override
  State<VoiceHoldStrip> createState() => _VoiceHoldStripState();
}

class _VoiceHoldStripState extends State<VoiceHoldStrip>
    with SingleTickerProviderStateMixin {
  // B2: the chevron nudges 4 dp up and back every 1.2 s (600 ms each way).
  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  bool _motionInitialized = false;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (_motionInitialized && reduced == _reduced) return;
    _motionInitialized = true;
    _reduced = reduced;
    if (reduced) {
      _nudge
        ..stop()
        ..value = 0;
    } else {
      _nudge.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _nudge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final reduced = _reduced;
    final micScale = reduced ? 1.0 : 1.15;
    final elapsed = widget.elapsed;
    final levels = widget.levels;
    final dragX = widget.dragX;
    final dragY = widget.dragY;
    final cancelled = widget.cancelled;
    final pulse = widget.pulse;
    return ExcludeSemantics(
      child: SizedBox(
        height: 64,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.centerRight,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 68),
              child: Row(
                children: [
                  reduced
                      ? _dot(t.error)
                      : FadeTransition(opacity: pulse, child: _dot(t.error)),
                  const SizedBox(width: 10),
                  Text(
                    formatMmSs(elapsed.inSeconds),
                    style: TextStyle(
                      color: t.ink,
                      fontSize: 16,
                      height: 22 / 16,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 28,
                      child: VoiceWaveform(levels: levels, live: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      cancelled ? 'Release to cancel' : 'Slide to cancel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: t.inkSoft,
                        fontSize: 13,
                        height: 18 / 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 4,
              bottom: 34,
              child: Transform.translate(
                offset: Offset(0, dragY),
                child: Container(
                  width: 40,
                  height: 88,
                  decoration: BoxDecoration(
                    color: t.surface,
                    border: Border.all(color: t.line),
                    borderRadius: BorderRadius.circular(
                      WarmPopTokens.radiusPill,
                    ),
                    boxShadow: WarmPopTokens.cardShadow(t.shadow),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_open_outlined,
                        color: t.inkSoft,
                        size: 20,
                      ),
                      AnimatedBuilder(
                        animation: _nudge,
                        builder: (context, child) => Transform.translate(
                          offset: Offset(0, -4 * _nudge.value),
                          child: child,
                        ),
                        child: Icon(
                          Icons.keyboard_arrow_up,
                          color: t.inkSoft,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(dragX, dragY),
              child: Transform.scale(
                scale: micScale,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.accent,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(Icons.mic, color: t.onAccent, size: 22),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class VoiceRecorderPanel extends StatefulWidget {
  const VoiceRecorderPanel({
    super.key,
    required this.mode,
    required this.filePath,
    required this.seconds,
    required this.levels,
    required this.isDraft,
    required this.isSending,
    required this.onDelete,
    required this.onCenter,
    required this.onSend,
    this.onStopAndListen,
  });

  final VoiceRecorderPanelMode mode;
  final String filePath;
  final int seconds;
  final List<double> levels;
  final bool isDraft;
  final bool isSending;
  final VoidCallback onDelete;
  final VoidCallback onCenter;
  final VoidCallback onSend;
  final VoidCallback? onStopAndListen;

  @override
  State<VoiceRecorderPanel> createState() => _VoiceRecorderPanelState();
}

class _VoiceRecorderPanelState extends State<VoiceRecorderPanel> {
  final _player = AudioPlayer();
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;
  AppLifecycleListener? _lifecycle;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;
  bool _loaded = false;
  bool _loading = false;
  bool _playing = false;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.positionStream.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _durationSub = _player.durationStream.listen((duration) {
      if (mounted && duration != null) setState(() => _total = duration);
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      final playing =
          state.playing && state.processingState != ProcessingState.completed;
      setState(() => _playing = playing);
      if (state.processingState == ProcessingState.completed) {
        _player.seek(Duration.zero);
        _player.pause();
      }
    });
    _lifecycle = AppLifecycleListener(
      onHide: () {
        if (widget.mode == VoiceRecorderPanelMode.preview) {
          unawaited(_player.pause());
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<bool> _load() async {
    if (_loaded) return true;
    if (_loading) return false;
    setState(() => _loading = true);
    try {
      await _player.setFilePath(widget.filePath);
      _loaded = true;
      return true;
    } catch (_) {
      if (mounted)
        showToast(context, "Couldn't play the recording.", error: true);
      return false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    if (!await _load() || widget.isSending) return;
    await _player.play();
  }

  Future<void> _seek(double fraction) async {
    if (widget.isSending || !await _load()) return;
    final total = _total > Duration.zero
        ? _total
        : Duration(seconds: widget.seconds);
    await _player.seek(total * fraction.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final isPreview = widget.mode == VoiceRecorderPanelMode.preview;
    final status = switch (widget.mode) {
      VoiceRecorderPanelMode.locked => _status(
        widget.seconds >= AppConstants.maxVoiceMessageSeconds - 10
            ? '10 seconds left'
            : 'Recording',
        t,
      ),
      VoiceRecorderPanelMode.paused => _status('Paused', t),
      VoiceRecorderPanelMode.preview => widget.isDraft ? 'Draft' : '',
    };
    final totalSeconds = _total > Duration.zero
        ? _total.inSeconds
        : widget.seconds;
    final shownSeconds = isPreview && _loaded && _position > Duration.zero
        ? _position.inSeconds
        : widget.seconds;
    final progress = totalSeconds > 0
        ? (_position.inMilliseconds / (totalSeconds * 1000)).clamp(0.0, 1.0)
        : 0.0;

    final panel = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Voice note',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.ink,
                fontSize: 16,
                height: 22 / 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Semantics(
            liveRegion: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 18),
              child: status.isEmpty
                  ? const SizedBox.shrink()
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.mode == VoiceRecorderPanelMode.locked) ...[
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: t.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            status,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: t.inkSoft,
                              fontSize: 13,
                              height: 18 / 13,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              // D1: the seek fraction comes from the waveform's own width.
              final width = constraints.maxWidth;
              void seekAt(Offset localPosition) {
                if (!isPreview || widget.isSending || width <= 0) return;
                unawaited(_seek(localPosition.dx / width));
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => seekAt(details.localPosition),
                onHorizontalDragStart: (details) =>
                    seekAt(details.localPosition),
                onHorizontalDragUpdate: (details) =>
                    seekAt(details.localPosition),
                child: VoiceWaveform(
                  levels: widget.levels,
                  progress: isPreview ? progress : null,
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Semantics(
            label: '${shownSeconds ~/ 60} minutes ${shownSeconds % 60} seconds',
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                formatMmSs(shownSeconds),
                style: TextStyle(
                  color: t.ink,
                  fontSize: 28,
                  height: 34 / 28,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _disc(
                context,
                size: 56,
                background: t.surface2,
                foreground: t.ink,
                icon: Icons.close,
                label: 'Delete voice note',
                onTap: widget.isSending ? null : widget.onDelete,
              ),
              const SizedBox(width: 32),
              _disc(
                context,
                size: 72,
                background: t.accent,
                foreground: t.onAccent,
                icon: widget.mode == VoiceRecorderPanelMode.locked
                    ? Icons.pause
                    : widget.mode == VoiceRecorderPanelMode.paused
                    ? Icons.mic
                    : _playing
                    ? Icons.pause
                    : Icons.play_arrow,
                label: widget.mode == VoiceRecorderPanelMode.locked
                    ? 'Pause recording'
                    : widget.mode == VoiceRecorderPanelMode.paused
                    ? 'Resume recording'
                    : _playing
                    ? 'Pause voice note'
                    : 'Play voice note',
                onTap: widget.isSending
                    ? null
                    : (isPreview ? _togglePlay : widget.onCenter),
                busy: isPreview && _loading,
              ),
              const SizedBox(width: 32),
              _disc(
                context,
                size: 56,
                background: t.accent,
                foreground: t.onAccent,
                icon: Icons.send_rounded,
                label: 'Send voice note',
                onTap: widget.isSending ? null : widget.onSend,
                busy: widget.isSending,
              ),
            ],
          ),
          if (widget.mode == VoiceRecorderPanelMode.paused &&
              widget.onStopAndListen != null)
            AppButton(
              variant: AppButtonVariant.text,
              onPressed: widget.isSending ? null : widget.onStopAndListen,
              child: const Text('Stop and listen'),
            ),
        ],
      ),
    );
    return reduced
        ? panel
        : AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: WarmPopTokens.motionBase,
            child: panel,
          );
  }

  String _status(String value, ColorTokens t) => value;

  Widget _disc(
    BuildContext context, {
    required double size,
    required Color background,
    required Color foreground,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return Semantics(
      button: true,
      label: label,
      // excludeSemantics also drops the GestureDetector's tap below: without
      // these two a screen reader can't press the control.
      enabled: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: SizedBox(
          width: math.max(48, size),
          height: math.max(48, size),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Center(
                    child: busy
                        ? BusySpinner(color: foreground)
                        : Icon(
                            icon,
                            color: foreground,
                            size: size == 72 ? 32 : 24,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
