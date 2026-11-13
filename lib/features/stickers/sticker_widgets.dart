import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/app_haptic.dart';
import '../../core/widgets/app_sheet.dart';
import '../../domain/entities/message.dart';
import '../chat/widgets/expiry_badge.dart';
import 'stickers.dart';

/// Size of a sticker in the chat (§J2.5, decision 3).
const double kStickerChatSize = 128;

/// A sticker picture decoded at its shown size (J2.5.2), never 384² per copy.
class StickerImage extends StatelessWidget {
  const StickerImage(this.sticker, {super.key, required this.size});

  final Sticker sticker;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    sticker.asset,
    width: size,
    height: size,
    cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
    filterQuality: FilterQuality.medium,
    excludeFromSemantics: true,
  );
}

/// The thumbnail for a sticker message in the reply quote, pinned banner and
/// starred list; nothing for an unknown id or an undecrypted body.
Widget stickerThumb(String? body, double size) {
  final sticker = body == null ? null : stickerById(stickerIdOf(body) ?? '');
  if (sticker == null) return const SizedBox.shrink();
  return ExcludeSemantics(child: StickerImage(sticker, size: size));
}

/// "Sticker, Hi" (J2.5.1); "Sticker" for an unknown id.
String stickerSemanticsLabel(String body) {
  final sticker = stickerById(stickerIdOf(body) ?? '');
  return sticker == null ? 'Sticker' : 'Sticker, ${sticker.label}';
}

/// The chat bubble of a `sticker` message: the image with no bubble fill and
/// the media time pill under it (§J2.5). [body] is null while decrypting.
class StickerBubble extends StatelessWidget {
  const StickerBubble({
    super.key,
    required this.message,
    required this.body,
    required this.isMine,
    required this.runEnd,
  });

  final Message message;
  final String? body;
  final bool isMine;
  final bool runEnd;

  @override
  Widget build(BuildContext context) {
    final body = this.body;
    final sticker = body == null ? null : stickerById(stickerIdOf(body) ?? '');
    final Widget picture;
    if (body == null) {
      picture = const SizedBox.square(dimension: kStickerChatSize);
    } else if (sticker == null) {
      return _UnknownStickerBubble(
        message: message,
        isMine: isMine,
        runEnd: runEnd,
      );
    } else {
      picture = StickerImage(sticker, size: kStickerChatSize);
    }
    return ChatBubbleFrame(
      isMine: isMine,
      runEnd: runEnd,
      chrome: false,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          picture,
          if (runEnd || ChatInfoMode.of(context)) ...[
            const SizedBox(height: ChatBubbleGeometry.metadataGap),
            ChatBubbleTimestamp(
              isMine: isMine,
              createdAt: message.createdAt,
              status: message.status,
              overlay: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// J2.2: a sticker this app does not have (sent by a newer app).
class _UnknownStickerBubble extends StatelessWidget {
  const _UnknownStickerBubble({
    required this.message,
    required this.isMine,
    required this.runEnd,
  });

  final Message message;
  final bool isMine;
  final bool runEnd;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ChatBubbleFrame(
      isMine: isMine,
      runEnd: runEnd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sticker',
                  style: TextStyle(
                    fontSize: 15,
                    color: isMine ? t.onAccent : t.ink,
                  ),
                ),
                Text(
                  'Update Kuch Bhi to see it',
                  style: TextStyle(
                    fontSize: 13,
                    color: isMine
                        ? t.onAccent.withValues(alpha: 0.7)
                        : t.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          if (runEnd || ChatInfoMode.of(context)) ...[
            const SizedBox(height: ChatBubbleGeometry.metadataGap),
            ChatBubbleTimestamp(
              isMine: isMine,
              createdAt: message.createdAt,
              status: message.status,
            ),
          ],
        ],
      ),
    );
  }
}

/// §J3: the Stickers sheet. A tap sends once and closes the sheet.
Future<void> showStickerSheet(
  BuildContext context, {
  required Future<void> Function(Sticker sticker) onSend,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  var sent = false; // J3.2: one sticker per open sheet, even mid-close
  return showAppSheet<void>(
    context: context,
    builder: (sheetContext) {
      return AppSheetChrome(
        title: 'Stickers',
        children: [
          GridView.count(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final s in kStickers)
                Semantics(
                  button: true,
                  label: 'Send sticker: ${s.label}',
                  child: InkWell(
                    key: ValueKey('sticker-tile-${s.id}'),
                    borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
                    onTap: () {
                      if (sent) return;
                      sent = true;
                      appHaptic(HapticsType.light);
                      Navigator.of(sheetContext).pop();
                      onSend(s);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: LayoutBuilder(
                        builder: (context, c) =>
                            StickerImage(s, size: c.biggest.shortestSide),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );
}
