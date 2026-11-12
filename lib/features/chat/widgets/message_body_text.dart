import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/decrypt/body_cache.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/entities/conversation.dart';
import '../chat_run_grouping.dart' show albumLabel;
import '../providers/album_provider.dart';
import '../providers/message_body_provider.dart';

/// THE body renderer (spec §8 placeholder law — Task 9).
///
/// Every consumer that displays a message body goes through this widget:
/// it watches `messageBodyProvider(messageId)` and renders
/// - text when a body is available — the synchronous [bodyCache] fast-path
///   resolves the very FIRST frame (own-sent messages never flash a
///   placeholder, spec §5.1), else when the provider emits;
/// - a geometry-preserving neutral placeholder while a body is transiently
///   unavailable; a lock/error indicator is reserved for terminal decrypt
///   states (`key_missing`/`failed`).
///
/// [styleContext] picks the typography/color slot:
/// `'bubble.mine' | 'bubble' | 'emoji' | 'system' | 'preview'`.
/// [style] overrides the slot wholesale (parent-controlled coloring).
class MessageBodyText extends ConsumerStatefulWidget {
  const MessageBodyText({
    super.key,
    required this.messageId,
    required this.styleContext,
    this.decryptState = 'ready',
    this.ciphertextLength = 0,
    this.skeletonShell = false,
    this.highlightQuery,
    this.highlightCurrent = false,
    this.style,
  });

  final String messageId;
  final String styleContext;
  final String decryptState;
  final int ciphertextLength;
  final bool skeletonShell;
  final String? highlightQuery;
  final bool highlightCurrent;
  final TextStyle? style;

  /// The placeholder's finder key — brief tests pin
  /// `ValueKey('body-placeholder-<messageId>')`.
  static ValueKey<String> placeholderKey(String messageId) =>
      ValueKey('body-placeholder-$messageId');

  TextStyle _slotStyle(BuildContext context) {
    final t = context.t;
    return switch (styleContext) {
      'bubble.mine' => TextStyle(color: t.onAccent, fontSize: 15),
      'bubble' => TextStyle(color: t.ink, fontSize: 15),
      'emoji' => const TextStyle(fontSize: 40),
      'system' => TextStyle(
        fontSize: 12,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w500,
        color: context.t.ink.withValues(alpha: 0.55),
      ),
      'preview' => TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: t.inkSoft,
      ),
      _ => const TextStyle(fontSize: 15),
    };
  }

  @override
  ConsumerState<MessageBodyText> createState() => _MessageBodyTextState();
}

class _MessageBodyTextState extends ConsumerState<MessageBodyText> {
  String? _lastBody;
  late String _lastMessageId;
  bool _hasRenderedBody = false;

  @override
  void initState() {
    super.initState();
    _lastMessageId = widget.messageId;
    _lastBody = _nonEmptyBody(bodyCache.get(widget.messageId));
    _hasRenderedBody = _lastBody != null;
  }

  @override
  void didUpdateWidget(covariant MessageBodyText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId == widget.messageId) return;

    _lastMessageId = widget.messageId;
    _lastBody = _nonEmptyBody(bodyCache.get(widget.messageId));
    _hasRenderedBody = _lastBody != null;
  }

  @override
  Widget build(BuildContext context) {
    // Cache fast-path: resolves instantly (and synchronously) so a resident
    // body never flashes the placeholder for a frame. The provider watch
    // below stays UNCONDITIONAL (Riverpod rule) and covers the miss path.
    final cached = bodyCache.get(widget.messageId);
    final providerBody = ref
        .watch(messageBodyProvider(widget.messageId))
        .valueOrNull;
    final resolved = _rememberBody(cached ?? providerBody);
    final slot = widget.style ?? widget._slotStyle(context);
    final metrics = _placeholderMetricsFor(
      context,
      style: slot,
      styleContext: widget.styleContext,
      ciphertextLength: widget.ciphertextLength,
    );

    final Widget content;
    if (resolved != null) {
      final lockSize = !_hasRenderedBody;
      _hasRenderedBody = true;
      content = _ResolvedBody(
        key: ValueKey('body-content-${widget.messageId}'),
        body: resolved,
        messageId: widget.messageId,
        style: slot,
        styleContext: widget.styleContext,
        metrics: metrics,
        lockSize: lockSize,
        highlightQuery: widget.highlightQuery,
        highlightCurrent: widget.highlightCurrent,
      );
    } else {
      content = _BodyPlaceholder(
        key: MessageBodyText.placeholderKey(widget.messageId),
        style: slot,
        styleContext: widget.styleContext,
        decryptState: widget.decryptState,
        ciphertextLength: widget.ciphertextLength,
        skeletonShell: widget.skeletonShell,
      );
    }

    // The provider can complete after the bubble has painted. Keep the slot
    // stable while the decrypted text fades in over roughly 100ms.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 100),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: content,
    );
  }

  String? _rememberBody(String? body) {
    if (_lastMessageId != widget.messageId) {
      _lastMessageId = widget.messageId;
      _lastBody = null;
      _hasRenderedBody = false;
    }
    final nonEmpty = _nonEmptyBody(body);
    if (nonEmpty != null) _lastBody = nonEmpty;
    return _lastBody;
  }
}

String? _nonEmptyBody(String? body) =>
    body == null || body.isEmpty ? null : body;

/// Holds the ciphertext-sized slot only while a newly resolved body replaces
/// its placeholder. Once the switcher has landed, [AnimatedSize] settles to
/// the body's natural layout instead of leaving a permanent minimum size.
class _ResolvedBody extends StatefulWidget {
  const _ResolvedBody({
    super.key,
    required this.body,
    required this.messageId,
    required this.style,
    required this.styleContext,
    required this.metrics,
    required this.lockSize,
    required this.highlightQuery,
    required this.highlightCurrent,
  });

  final String body;
  final String messageId;
  final TextStyle style;
  final String styleContext;
  final _PlaceholderMetrics metrics;
  final bool lockSize;
  final String? highlightQuery;
  final bool highlightCurrent;

  @override
  State<_ResolvedBody> createState() => _ResolvedBodyState();
}

class _ResolvedBodyState extends State<_ResolvedBody> {
  Timer? _unlockTimer;
  late bool _locked;

  @override
  void initState() {
    super.initState();
    _locked = widget.lockSize;
    if (_locked) _scheduleUnlock();
  }

  @override
  void didUpdateWidget(covariant _ResolvedBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.body == oldWidget.body) return;
    if (widget.lockSize) {
      _unlockTimer?.cancel();
      _locked = true;
      _scheduleUnlock();
    } else if (_locked) {
      _unlockTimer?.cancel();
      _unlockTimer = null;
      _locked = false;
    }
  }

  void _scheduleUnlock() {
    _unlockTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted) return;
      setState(() => _locked = false);
    });
  }

  @override
  void dispose() {
    _unlockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.highlightQuery?.trim() ?? '';
    final text = query.isEmpty
        ? Text(
            widget.body,
            key: ValueKey('body-text-${widget.messageId}'),
            style: widget.style,
            maxLines: widget.styleContext == 'preview' ? 1 : null,
            overflow: widget.styleContext == 'preview'
                ? TextOverflow.ellipsis
                : null,
          )
        : Text.rich(
            TextSpan(
              style: widget.style,
              children: _highlightSpans(context, widget.body, query),
            ),
            key: ValueKey('body-text-${widget.messageId}'),
            maxLines: widget.styleContext == 'preview' ? 1 : null,
            overflow: widget.styleContext == 'preview'
                ? TextOverflow.ellipsis
                : null,
          );
    final child = _locked
        ? ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: widget.metrics.width,
              minHeight: widget.metrics.height,
            ),
            child: text,
          )
        : text;
    return AnimatedSize(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      alignment: AlignmentDirectional.topStart,
      child: child,
    );
  }

  List<InlineSpan> _highlightSpans(
    BuildContext context,
    String body,
    String query,
  ) {
    final lowerBody = body.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final markStyle = widget.style.copyWith(
      backgroundColor: widget.highlightCurrent
          ? context.t.accent.withValues(alpha: 0.30)
          : context.t.accentSoft,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    while (cursor < body.length) {
      final match = lowerBody.indexOf(lowerQuery, cursor);
      if (match < 0) {
        spans.add(TextSpan(text: body.substring(cursor)));
        break;
      }
      if (match > cursor) {
        spans.add(TextSpan(text: body.substring(cursor, match)));
      }
      final end = match + query.length;
      spans.add(TextSpan(text: body.substring(match, end), style: markStyle));
      cursor = end;
    }
    return spans;
  }
}

/// A transient body paints its estimated neutral skeleton immediately. The
/// existing 150ms grace remains as a low-contrast-to-normal transition; the
/// bubble never has a transparent body during that grace. Terminal decrypt
/// states show one explicit lock/error state instead.
class _BodyPlaceholder extends StatefulWidget {
  const _BodyPlaceholder({
    super.key,
    required this.style,
    required this.styleContext,
    required this.decryptState,
    required this.ciphertextLength,
    required this.skeletonShell,
  });

  final TextStyle style;
  final String styleContext;
  final String decryptState;
  final int ciphertextLength;
  final bool skeletonShell;

  @override
  State<_BodyPlaceholder> createState() => _BodyPlaceholderState();
}

class _BodyPlaceholderState extends State<_BodyPlaceholder> {
  Timer? _timer;
  bool _showSkeleton = false;

  bool get _terminal =>
      widget.decryptState == 'key_missing' || widget.decryptState == 'failed';

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    if (_terminal) return;
    _timer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _showSkeleton = true);
    });
  }

  @override
  void didUpdateWidget(covariant _BodyPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasTerminal =
        oldWidget.decryptState == 'key_missing' ||
        oldWidget.decryptState == 'failed';
    if (_terminal) {
      _timer?.cancel();
      _timer = null;
      _showSkeleton = false;
      return;
    }
    if (wasTerminal && !_terminal) {
      _timer?.cancel();
      _showSkeleton = false;
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _placeholderMetricsFor(
      context,
      style: widget.style,
      styleContext: widget.styleContext,
      ciphertextLength: widget.ciphertextLength,
    );
    final t = context.t;
    final dim = widget.style.color ?? t.inkSoft;
    if (_terminal) {
      final isBubbleContext =
          widget.styleContext == 'bubble' ||
          widget.styleContext == 'bubble.mine';
      final isPreviewContext = widget.styleContext == 'preview';
      final terminalStyle = widget.style.copyWith(
        color: dim,
        fontSize: (widget.style.fontSize ?? 15).clamp(11.0, 15.0).toDouble(),
        fontStyle: FontStyle.normal,
        fontWeight: FontWeight.w500,
      );
      return Row(
        key: const ValueKey('body-terminal-decrypt'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              widget.decryptState == 'failed'
                  ? Icons.error_outline
                  : Icons.lock_outline,
              size: 14,
              color: dim.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Can't decrypt",
                style: terminalStyle,
                maxLines: isPreviewContext ? 1 : null,
                overflow: isPreviewContext ? TextOverflow.ellipsis : null,
              ),
              if (isBubbleContext) ...[
                const SizedBox(height: 2),
                Text(
                  'Ask them to resend',
                  style: TextStyle(
                    color: t.inkFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    // Keep the 150ms grace, but paint bars during it so a text bubble is
    // never an empty painted chrome. The grace only raises bar contrast.
    final barAlpha = _showSkeleton ? 0.18 : 0.10;
    final bars = <Widget>[];
    for (var i = 0; i < metrics.lineWidths.length; i++) {
      bars.add(
        Container(
          width: metrics.lineWidths[i],
          height: metrics.lineHeight,
          decoration: BoxDecoration(
            color: dim.withValues(alpha: barAlpha),
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
          ),
        ),
      );
      if (i + 1 < metrics.lineWidths.length) {
        bars.add(SizedBox(height: metrics.lineGap));
      }
    }
    final skeletonBody = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: bars,
    );
    if (!widget.skeletonShell) {
      return KeyedSubtree(
        key: ValueKey('body-skeleton-${widget.ciphertextLength}'),
        child: skeletonBody,
      );
    }

    return Container(
      key: ValueKey('body-skeleton-${widget.ciphertextLength}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.styleContext == 'bubble.mine'
            ? t.accent.withValues(alpha: 0.18)
            : t.surface2,
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusBubble),
      ),
      child: skeletonBody,
    );
  }
}

_PlaceholderMetrics _placeholderMetricsFor(
  BuildContext context, {
  required TextStyle style,
  required String styleContext,
  required int ciphertextLength,
}) {
  final fontSize = style.fontSize ?? 15;
  if (styleContext == 'emoji') {
    return const _PlaceholderMetrics(
      width: 56,
      height: 48,
      lineHeight: 40,
      lineGap: 0,
      lineWidths: [56],
    );
  }

  // Use ciphertext length only as a coarse geometry signal. No plaintext is
  // decoded or retained by this widget.
  final int estimatedChars = ciphertextLength <= 0
      ? 12
      : (((ciphertextLength * 3) / 4).round() - 28).clamp(8, 480).toInt();
  final charWidth = fontSize * 0.52;
  final preview = styleContext == 'preview';
  final double maxWidth = preview
      ? 180.0
      : (MediaQuery.sizeOf(context).width * 0.64)
            .clamp(150.0, 280.0)
            .toDouble();
  final int lines = preview
      ? 1
      : (estimatedChars / (maxWidth / charWidth)).ceil().clamp(1, 6).toInt();
  final double width = preview
      ? (estimatedChars * charWidth).clamp(42.0, maxWidth).toDouble()
      : (estimatedChars * charWidth).clamp(54.0, maxWidth).toDouble();
  final double lineHeight = (fontSize * 1.25).clamp(12.0, 24.0).toDouble();
  final lineWidths = <double>[];
  for (var i = 0; i < lines; i++) {
    lineWidths.add(
      i == lines - 1 && lines > 1
          ? (width * 0.72).clamp(36.0, width).toDouble()
          : width,
    );
  }
  return _PlaceholderMetrics(
    width: width,
    height: lineHeight * lines + (lines - 1) * 3,
    lineHeight: lineHeight,
    lineGap: 3,
    lineWidths: lineWidths,
  );
}

class _PlaceholderMetrics {
  const _PlaceholderMetrics({
    required this.width,
    required this.height,
    required this.lineHeight,
    required this.lineGap,
    required this.lineWidths,
  });

  final double width;
  final double height;
  final double lineHeight;
  final double lineGap;
  final List<double> lineWidths;
}

/// Constant label for a NON-text last message (spec §3 / P7: derived at
/// render time from the row's `type` — the same glyphs the old stored
/// `last_message_preview` column held, but never written anywhere).
String conversationPreviewLabel(String type) => switch (type) {
  'image' => kPreviewPhotoLabel,
  'video' => kPreviewVideoLabel,
  'voice' => kPreviewVoiceLabel,
  'document' => kPreviewDocumentLabel,
  'sticker' => kPreviewStickerLabel,
  'poll' => '📊 Poll',
  'system' => 'New message',
  _ => 'New message',
};

/// Conversation-list preview body (spec §8 placeholder law + P7 sealed
/// previews, spec §3: NOTHING preview-shaped is durable).
///
/// Every branch DERIVES from the newest message row of [conversation]:
/// * `text`      → [MessageBodyText] ⇒ `messageBodyProvider` (placeholder
///   until the body emits, never blank, never ciphertext);
/// * media/system → [conversationPreviewLabel] (a CONSTANT, not a body);
/// * no row at all (fresh chat / evicted last row) → [fallback], the
///   constant the caller passes.
/// There is deliberately no stored-preview fallback anywhere.
class ConversationPreviewText extends ConsumerWidget {
  const ConversationPreviewText({
    super.key,
    required this.conversation,
    required this.fallback,
    this.style,
  });

  final Conversation conversation;
  final String fallback;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastMsgAsync = ref.watch(
      conversationLastMessageProvider(conversation.id),
    );
    final lastMsg = lastMsgAsync.valueOrNull;
    if (lastMsg == null) {
      if (lastMsgAsync.isLoading) return const _PreviewLoadingPlaceholder();
      return _label(fallback, context);
    }
    // 12.5 F5: the newest row of an album previews what is inside it.
    final albumId = lastMsg.albumId;
    final albumRows = albumId == null
        ? null
        : ref
              .watch(
                albumRowsProvider(
                  AlbumKey(lastMsg.conversationId, albumId),
                ),
              )
              .valueOrNull;
    final album = albumRows != null && albumRows.length >= 2
        ? albumRows
        : null;
    if (album != null &&
        (lastMsg.type == 'image' || lastMsg.type == 'video')) {
      return _label(albumLabel(album), context);
    }
    if (lastMsg.type == 'text') {
      return MessageBodyText(
        messageId: lastMsg.localId,
        styleContext: 'preview',
        decryptState: lastMsg.decryptState,
        ciphertextLength: lastMsg.encryptedBody.length,
        style: style,
      );
    }
    return _label(conversationPreviewLabel(lastMsg.type), context);
  }

  Widget _label(String text, BuildContext context) => Text(
    text,
    style:
        style ??
        TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: context.t.inkSoft,
        ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

/// Loading state for the preview-row query itself. A row does not yet exist,
/// so there is no ciphertext length to estimate from. Keep the tile geometry
/// quiet for fast reads and show a short neutral line only after the same
/// 150ms grace period used by body decrypts.
class _PreviewLoadingPlaceholder extends StatefulWidget {
  const _PreviewLoadingPlaceholder();

  @override
  State<_PreviewLoadingPlaceholder> createState() =>
      _PreviewLoadingPlaceholderState();
}

class _PreviewLoadingPlaceholderState
    extends State<_PreviewLoadingPlaceholder> {
  Timer? _timer;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox(width: 96, height: 16);
    return Container(
      width: 96,
      height: 10,
      decoration: BoxDecoration(
        color: context.t.inkSoft.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
      ),
    );
  }
}
