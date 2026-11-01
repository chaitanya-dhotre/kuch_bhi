import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/tokens.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../media/providers/media_viewer_providers.dart';
import '../message_offline_policy.dart';
import '../providers/chat_provider.dart';

/// One hero-tag namespace for a message's media (audit §3.10): the bubble's
/// thumbnail and its fullscreen viewer must agree on the tag, so both wrap it
/// in this helper.
String mediaHeroTag(String serverId) => 'media_$serverId';

/// The placeholder for a photo, video or document whose load came back
/// empty. mediaFileProvider keeps that result, so the tap drops it and the
/// bubble fetches again. Offline the tap waits for the network (38% + hint);
/// the provider re-runs by itself on reconnect. A blob the store marked
/// failed (expired, dead link, can't decrypt) is final: no retry is offered.
class MediaRetry extends ConsumerWidget {
  const MediaRetry({
    super.key,
    required this.media,
    required this.what,
    required this.icon,
    this.ink,
  });

  final MediaRef media;

  /// "Photo", "Video", "Document": the start of the spoken label.
  final String what;
  final IconData icon;

  /// Caption colour; defaults to the soft ink of a surface placeholder.
  final Color? ink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(mediaBlobStatusProvider(media)).valueOrNull;
    final ended =
        status == MediaBlobStatus.expired ||
        status == MediaBlobStatus.deadLink ||
        status == MediaBlobStatus.cantDecrypt;
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final caption = ended
        ? status == MediaBlobStatus.expired
              ? kMediaExpired
              : status == MediaBlobStatus.deadLink
              ? kMediaNoLongerAvailable
              : kMediaCantDecrypt
        : online
        ? 'Tap to retry'
        : kOfflineActionHint;
    final color = ink ?? context.t.inkSoft;
    final canRetry = online && !ended;
    return Semantics(
      button: !ended,
      enabled: canRetry,
      label: ended ? '$what. $caption' : "$what didn't load. $caption",
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: canRetry
            ? () {
                ref.invalidate(mediaBlobStatusProvider(media));
                ref.invalidate(mediaFileProvider(media));
              }
            : null,
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(8),
              // A fixed-height photo slot at 200% text: shrink, never clip.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: online || ended ? 1 : .38,
                      child: Icon(
                        status == MediaBlobStatus.cantDecrypt
                            ? Icons.lock_outline
                            : status == MediaBlobStatus.expired
                            ? Icons.timer_off_outlined
                            : icon,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      caption,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: color, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
