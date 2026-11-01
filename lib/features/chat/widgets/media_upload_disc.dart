import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../providers/upload_progress_provider.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart'
    show messageRepositoryProvider;
import 'expiry_badge.dart';
import '../message_offline_policy.dart';

/// The upload control shown over an optimistic photo or video.
class MediaUploadDisc extends StatelessWidget {
  const MediaUploadDisc({
    super.key,
    this.progress,
    this.onCancel,
    this.onRetry,
    this.enabled = true,
    required this.label,
    this.size = 44,
    this.onAccent = false,
  });

  final double? progress;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final bool enabled;
  final String label;
  final double size;
  final bool onAccent;

  @override
  Widget build(BuildContext context) {
    final failed = onRetry != null;
    final callback = failed ? onRetry : onCancel;
    final icon = failed ? Icons.refresh_rounded : Icons.close;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? callback : null,
        child: Opacity(
          opacity: enabled ? 1 : .38,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: MediaDisc(
                    icon: icon,
                    background: size == 30 ? context.t.accent : null,
                    foreground: size == 30 ? context.t.onAccent : null,
                    iconSize: size * .52,
                  ),
                ),
                if (progress != null)
                  CustomPaint(
                    key: const Key('upload-progress-arc'),
                    size: Size.square(size),
                    painter: _ProgressPainter(
                      value: progress!.clamp(0, 1),
                      color: onAccent ? context.t.onAccent : context.t.accent,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MediaUploadControl extends ConsumerWidget {
  const MediaUploadControl({
    super.key,
    required this.localId,
    required this.status,
    required this.kind,
    this.size = 44,
    this.onAccent = false,
  });

  final String localId;
  final String? status;
  final String kind;
  final double size;
  final bool onAccent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(uploadProgressProvider(localId)).valueOrNull;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final failed = status == 'failed';
    final waiting = !failed && progress == null;
    final enabled = !failed || online;
    final label = failed
        ? '$kind not sent. $kUploadTryAgain'
        : waiting
        ? '$kind, ${kUploadWaiting.toLowerCase()}. Cancel'
        : '$kind, sending, ${(progress! * 100).round()} percent. Cancel';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MediaUploadDisc(
          progress: waiting || failed ? null : progress,
          enabled: enabled,
          label: label,
          size: size,
          onAccent: onAccent,
          onCancel: failed
              ? null
              : () async {
                  final cancelled = await ref
                      .read(messageRepositoryProvider)
                      .cancelMediaUpload(localId);
                  if (cancelled && context.mounted) {
                    showToast(context, 'Upload cancelled');
                  }
                },
          onRetry: failed
              ? () => ref.read(messageRepositoryProvider).retryMessage(localId)
              : null,
        ),
        if (failed && online)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$kUploadNotSent · $kUploadTryAgain',
                style: TextStyle(
                  color: onAccent ? context.t.onAccent : context.t.inkSoft,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        if (failed && !online)
          Text(
            kOfflineActionHint,
            style: TextStyle(
              color: onAccent ? context.t.onAccent : context.t.inkSoft,
              fontSize: 12,
            ),
          ),
      ],
    );
  }
}

class _ProgressPainter extends CustomPainter {
  const _ProgressPainter({required this.value, required this.color});
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    canvas.drawArc(
      rect.deflate(1.5),
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.value != value || old.color != color;
}
