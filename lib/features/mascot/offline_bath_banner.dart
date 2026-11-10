import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_strings.dart';
import '../../core/theme/tokens.dart';
import '../../infrastructure/offline/connectivity_signal.dart';
import '../chat/providers/outbox_status_provider.dart';
import 'capy.dart';

/// E1 / I1, the yuzu bath: the offline banner on Home and in a chat.
enum BathPhase { hidden, offline, sending, done }

/// Banner state machine (spec §E1). Timers (10 s cap, the "All sent." beat)
/// live in the widget; this is only the data-driven part.
BathPhase nextBathPhase(
  BathPhase phase, {
  required bool online,
  required int queued,
}) {
  if (!online) return BathPhase.offline;
  return switch (phase) {
    BathPhase.offline => queued > 0 ? BathPhase.sending : BathPhase.hidden,
    BathPhase.sending => queued == 0 ? BathPhase.done : BathPhase.sending,
    _ => phase,
  };
}

/// After reconnecting, the banner leaves after this whatever the count, so a
/// stuck or failed op never pins it.
const kBathSendingCap = Duration(seconds: 10);
const kBathHopDelay = Duration(milliseconds: 400);
const kBathDoneHold = Duration(milliseconds: 1600);

List<String> bathCopy(BathPhase phase, int queued) => switch (phase) {
  BathPhase.offline => [kOfflineSendCopy, if (queued > 0) '$queued waiting'],
  BathPhase.sending => ['Back online, sending $queued…'],
  BathPhase.done => ['All sent.'],
  BathPhase.hidden => const [],
};

class OfflineBathBanner extends ConsumerStatefulWidget {
  const OfflineBathBanner({
    super.key,
    required this.onRetry,
    this.padding = EdgeInsets.zero,
    this.bordered = false,
    this.tapToRetry = false,
  });

  final VoidCallback onRetry;
  final EdgeInsets padding;
  final bool bordered;

  /// The whole banner is a Retry target (Home). A tap on the capybara pets it
  /// instead (F8).
  final bool tapToRetry;

  @override
  ConsumerState<OfflineBathBanner> createState() => _OfflineBathBannerState();
}

class _OfflineBathBannerState extends ConsumerState<OfflineBathBanner> {
  late BathPhase _phase;
  Timer? _timer;
  int _hops = 0;
  int _flushes = 0;

  bool get _online => ref.read(isOnlineProvider).valueOrNull ?? true;
  int get _queued => ref.read(queuedCountProvider).valueOrNull ?? 0;

  @override
  void initState() {
    super.initState();
    _phase = _online ? BathPhase.hidden : BathPhase.offline;
  }

  void _apply() {
    // Hidden ignores the count, and reading it there would open the stream.
    final queued = _phase == BathPhase.hidden ? 0 : _queued;
    final next = nextBathPhase(_phase, online: _online, queued: queued);
    if (next == _phase) return;
    _timer?.cancel();
    if (next == BathPhase.sending) {
      _timer = Timer(kBathSendingCap, () => _to(BathPhase.hidden));
    } else if (next == BathPhase.done) {
      // Let the last yuzu's flush play first: two triggers in one frame and
      // the rig takes only one.
      _timer = Timer(kBathHopDelay, () {
        if (!mounted) return;
        setState(() => _hops++);
        _timer = Timer(kBathDoneHold, () => _to(BathPhase.hidden));
      });
    }
    setState(() => _phase = next);
  }

  void _to(BathPhase phase) {
    if (mounted) setState(() => _phase = phase);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(isOnlineProvider, (_, __) => _apply());
    if (_phase == BathPhase.hidden) return _switch(context, null);
    ref.listen<AsyncValue<int>>(queuedCountProvider, (prev, next) {
      final a = prev?.valueOrNull, b = next.valueOrNull;
      if (_phase == BathPhase.sending && a != null && b != null && b < a) {
        setState(() => _flushes++);
      }
      _apply();
    });
    final queued = ref.watch(queuedCountProvider).valueOrNull ?? 0;
    return _switch(context, _banner(context, queued));
  }

  Widget _switch(BuildContext context, Widget? banner) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduced ? Duration.zero : WarmPopTokens.motionBase,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: banner == null
          ? const SizedBox.shrink(key: ValueKey('bath-hidden'))
          : Padding(
              key: const ValueKey('offline-bath'),
              padding: widget.padding,
              child: banner,
            ),
    );
  }

  Widget _banner(BuildContext context, int queued) {
    final t = context.t;
    final lines = bathCopy(_phase, queued);
    final radius = BorderRadius.circular(WarmPopTokens.radiusMd);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      child: Row(
        children: [
          Capy(
            view: CapyView.onsen,
            size: 40,
            flip: true,
            animated: true,
            mood: switch (_phase) {
              BathPhase.sending => CapyMood.active,
              BathPhase.done => CapyMood.happy,
              _ => CapyMood.chill,
            },
            queued: _phase == BathPhase.done ? 0 : queued,
            hops: _hops,
            flushes: _flushes,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(lines.first, style: TextStyle(fontSize: 12, color: t.ink)),
                if (lines.length > 1)
                  Text(
                    lines[1],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
              ],
            ),
          ),
          if (_phase != BathPhase.done)
            TextButton(
              onPressed: widget.onRetry,
              style: TextButton.styleFrom(
                foregroundColor: t.ink,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: lines.join('. '),
      child: Material(
        color: t.accentSoft,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: widget.bordered
              ? BorderSide(color: t.accent.withValues(alpha: 0.45))
              : BorderSide.none,
        ),
        child: widget.tapToRetry
            ? InkWell(borderRadius: radius, onTap: widget.onRetry, child: row)
            : row,
      ),
    );
  }
}
