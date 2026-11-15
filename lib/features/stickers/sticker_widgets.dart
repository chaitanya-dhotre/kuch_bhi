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

/// Motion C1: decodes every sticker at chat size, so a sent sticker paints
/// on its row's first frame and its flight from the composer has pixels.
void precacheChatStickers(BuildContext context) {
  final px = (kStickerChatSize * MediaQuery.devicePixelRatioOf(context))
      .round();
  for (final s in kStickers) {
    precacheImage(
      ResizeImage.resizeIfNeeded(px, null, AssetImage(s.asset)),
      context,
    );
  }
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

/// The chat bubble of a `sticker` message: the image with no bubble fill
/// (§J2.5). Its time is on the line under the run (chat calm B2). [body] is
/// null while decrypting.
class StickerBubble extends StatelessWidget {
  const StickerBubble({
    super.key,
    required this.message,
    required this.body,
    required this.isMine,
    this.runStart = true,
  });

  final Message message;
  final String? body;
  final bool isMine;
  final bool runStart;

  @override
  Widget build(BuildContext context) {
    final body = this.body;
    final sticker = body == null ? null : stickerById(stickerIdOf(body) ?? '');
    final Widget picture;
    if (body == null) {
      picture = const SizedBox.square(dimension: kStickerChatSize);
    } else if (sticker == null) {
      return _UnknownStickerBubble(isMine: isMine, runStart: runStart);
    } else {
      picture = StickerImage(sticker, size: kStickerChatSize);
    }
    return ChatBubbleFrame(
      isMine: isMine,
      chrome: false,
      padding: EdgeInsets.zero,
      child: picture,
    );
  }
}

/// J2.2: a sticker this app does not have (sent by a newer app).
class _UnknownStickerBubble extends StatelessWidget {
  const _UnknownStickerBubble({required this.isMine, required this.runStart});

  final bool isMine;
  final bool runStart;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ChatBubbleFrame(
      isMine: isMine,
      runStart: runStart,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sticker', style: TextStyle(fontSize: 15, color: t.ink)),
            Text(
              'Update Kuch Bhi to see it',
              style: TextStyle(fontSize: 13, color: t.inkSoft),
            ),
          ],
        ),
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
