import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/decrypt/body_cache.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/busy_spinner.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/utils/emoji_utils.dart';
import '../../../data/local/database/app_database.dart' show OutboxTableData;
import '../../../data/local/database/tables/outbox_table.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart'
    show messageRepositoryProvider;
import '../providers/message_body_provider.dart';
import '../providers/outbox_status_provider.dart';
import '../providers/upload_progress_provider.dart';
import '../chat_run_grouping.dart' show albumLabel;
import '../message_offline_policy.dart';
import 'message_body_text.dart';
import 'link_preview_card.dart';
import 'album_bubble.dart';
import 'document_message_bubble.dart';
import 'image_message_bubble.dart';
import 'video_message_bubble.dart';
import 'voice_message_bubble.dart';
import 'voice_waveform.dart';
import 'reaction_bar.dart';
import 'reply_quote.dart';
import 'swipe_to_reply.dart';
import 'message_context_menu.dart';
import 'expiry_badge.dart';
import '../../stickers/sticker_widgets.dart';
import '../../mascot/capy.dart';

// 5 deterministic sender name colors — Warm Pop tokens only (no violet/
// indigo; spec veto). Names render on t.surface. Light surface needs dark
// ink (accent/keyGold are ~2.2:1 on white); dark surface gets the warm
// highlight pair. Same slot count both themes so hash → index is stable.
List<Color> _senderPalette(Brightness brightness) =>
    brightness == Brightness.dark
    ? const [
        WarmPopTokens.accent, // 8.0:1 on dark surface
        WarmPopTokens.keyGold, // 7.6:1
        WarmPopTokens.info,
        WarmPopTokens.success,
        WarmPopTokens.error,
      ]
    : const [
        WarmPopTokens.info, // ~4.7:1 on white
        WarmPopTokens.success, // ~3.4:1
        WarmPopTokens.error, // ~3.9:1
        WarmPopTokens.inkSoft, // ~5.3:1
        WarmPopTokens.mascotSnout, // ~5.7:1 warm brown
      ];

Color _colorForSender(String senderId, Brightness brightness) {
  final palette = _senderPalette(brightness);
  return palette[senderId.hashCode.abs() % palette.length];
}

String _messageTypeLabel(String type) => switch (type) {
  'image' => kMediaRowPhotoLabel,
  'video' => kMediaRowVideoLabel,
  'voice' => kMediaRowVoiceLabel,
  'document' => kMediaRowDocumentLabel,
  'poll' => 'Poll',
  'system' => 'System message',
  'sticker' => 'Sticker',
  _ => 'Message',
};

String _messageBodyLabel(Message message, String resolvedBody) {
  if (message.isDeletedForEveryone) return 'Message deleted';
  if (message.decryptState == 'key_missing' ||
      message.decryptState == 'failed') {
    return "Can't decrypt";
  }

  final body = resolvedBody.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (message.type == 'text' || message.type == 'system') {
    return body.isEmpty ? _messageTypeLabel(message.type) : body;
  }
  if (message.type == 'sticker') return stickerSemanticsLabel(body);
  return _messageTypeLabel(message.type);
}

String _messageRowSemanticsLabel({
  required Message message,
  required bool isMine,
  required String senderName,
  required String resolvedBody,
}) {
  final sender = isMine
      ? 'You'
      : senderName.trim().isEmpty
      ? 'Unknown sender'
      : senderName.trim();
  final body = _messageBodyLabel(message, resolvedBody);
  final time = DateFormat('HH:mm').format(message.createdAt.toLocal());
  final status = message.status.trim().isEmpty ? 'unknown' : message.status;
  // J2.5.1: a sticker is content, read first ("Sticker, Hi").
  if (message.type == 'sticker' && !message.isDeletedForEveryone) {
    return '$body. From $sender. Time $time. Status $status.';
  }
  return 'From $sender. $body. Time $time. Status $status.';
}

/// D7: "Album, 3 photos and 2 videos, from Asha, 12:41".
String albumSemanticsLabel(
  List<Message> rows, {
  required bool isMine,
  required String senderName,
}) {
  final sender = isMine
      ? 'You'
      : senderName.trim().isEmpty
      ? 'Unknown sender'
      : senderName.trim();
  final earliest = rows
      .map((m) => m.createdAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final time = DateFormat('HH:mm').format(earliest.toLocal());
  return 'Album, ${albumLabel(rows)}, from $sender, $time';
}

Widget _messageRowSemantics({
  required String label,
  required Widget child,
  required bool preserveChildNodes,
  bool? selected,
  VoidCallback? onTap,
}) => Semantics(
  // Text-only rows collapse into one semantic leaf. Rows with media,
  // reactions, reply quotes, or retry controls keep explicit child nodes so
  // their labelled actions remain independently reachable.
  container: true,
  explicitChildNodes: preserveChildNodes,
  // 12.8 G1: while selecting, the row is one button that toggles.
  label: selected == null
      ? label
      : '$label, ${selected ? 'selected' : 'not selected'}',
  selected: selected,
  button: selected == null ? null : true,
  onTap: onTap,
  onTapHint: selected == null ? null : (selected ? 'Deselect' : 'Select'),
  child: child,
);

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.senderName = 'Unknown',
    this.isGroup = false,
    this.runStart = true,
    this.runEnd = true,
    this.streakStart = true,
    this.searchQuery,
    this.searchCurrent = false,
    this.selected = false,
    this.selecting = false,
    this.onSelect,
    this.onReply,
    this.onReplyTap,
    this.album,
    this.onOpenAlbum,
  });

  final Message message;
  final bool isMine;
  final String senderName;
  final bool isGroup;
  final bool runStart;
  final bool runEnd;

  /// B3: first of a same-sender streak; the group name shows here only.
  final bool streakStart;
  final String? searchQuery;
  final bool searchCurrent;
  final bool selected;

  /// 12.8 B1: the chat is selecting, so every inner tap, the long-press menu
  /// and [SwipeToReply] are off; the chat's row gestures toggle instead.
  final bool selecting;

  /// The menu's Select; while [selecting], the row's toggle.
  final VoidCallback? onSelect;
  final VoidCallback? onReply;
  final VoidCallback? onReplyTap;

  /// 12.5: an album's rows (2+, in order); [message] is its earliest row.
  final List<Message>? album;

  /// Tap on album tile i (D5).
  final ValueChanged<int>? onOpenAlbum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // T9 (spec §5.1): THE body read goes through messageBodyProvider —
    // cache-resident text resolves synchronously (no frame of placeholder
    // for own-sent), a miss watches the family and rebuilds when it emits.
    // `resolved` stays null while unresolved → branch to the placeholder-
    // rendering surfaces below (never ciphertext, never a blank).
    final String? resolved =
        bodyCache.get(message.localId) ??
        ref.watch(messageBodyProvider(message.localId)).valueOrNull;
    final body = resolved ?? '';
    // B3: an own media send's localId IS its server id, so the real media
    // bubble draws from the first frame (no placeholder swap, same Hero
    // tag). Older rows (uuid localId) keep the placeholder.
    final media = mediaBubbleInputs(ref, message, isMine: isMine);
    final mediaId = media.mediaId;
    final ownUpload = media.uploadLocalId != null;
    final emojiOnly = isEmojiOnly(body) && message.type == 'text';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final url = extractFirstUrl(body);
    final album = this.album;
    // F1/D6: an album's reactions, reply and pin act on its cover.
    final cover = album?.first ?? message;
    final rowSemanticsLabel = album != null
        ? albumSemanticsLabel(album, isMine: isMine, senderName: senderName)
        : _messageRowSemanticsLabel(
            message: message,
            isMine: isMine,
            senderName: senderName,
            resolvedBody: body,
          );

    // ── System / info bubbles — no reply, no long-press, no sender meta ─
    if (message.type == 'system') {
      return _messageRowSemantics(
        label: rowSemanticsLabel,
        preserveChildNodes: false,
        child: _SystemMessageBubble(
          messageId: message.localId,
          decryptState: message.decryptState,
          ciphertextLength: message.ciphertextLength,
        ),
      );
    }

    // ── Terminal-failure lookup (Task 4) ───────────────────────────────
    // One shared outbox stream per conversation; find THIS message's op.
    // A `failedTerminal` row = stuck message → visible banner below.
    OutboxTableData? failedOp;
    final outboxRows =
        ref.watch(outboxStatusProvider(message.conversationId)).value ??
        const <OutboxTableData>[];
    for (final row in outboxRows) {
      if (row.ref == message.localId &&
          row.state == OutboxState.failedTerminal) {
        failedOp = row;
        break;
      }
    }
    final terminalOp = failedOp; // effectively final → promotable in closures

    // A receipt can reach an acked row mid-upload: keep the clock.
    final mediaStatus = ownUpload && message.status != 'failed'
        ? 'pending'
        : message.status;
    final Widget core;
    if (album != null) {
      core = AlbumBubble(
        rows: album,
        isMine: isMine,
        runStart: runStart,
        senderName: senderName,
        onOpen: onOpenAlbum,
      );
    } else if (message.type == 'voice' && mediaId != null) {
      core = VoiceMessageBubble(
        conversationId: message.conversationId,
        serverId: mediaId,
        isMine: isMine,
        runStart: runStart,
        durationText: resolved,
        status: mediaStatus,
        createdAt: message.createdAt,
        localId: ownUpload ? message.localId : null,
        waveSeed: cover.serverId ?? message.localId,
      );
    } else if (message.type == 'image' && mediaId != null) {
      core = ImageMessageBubble(
        conversationId: message.conversationId,
        serverId: mediaId,
        isMine: isMine,
        isDark: isDark,
        runStart: runStart,
        status: mediaStatus,
        createdAt: message.createdAt,
        senderName: senderName,
        localId: ownUpload ? message.localId : null,
      );
    } else if (message.type == 'video' && mediaId != null) {
      core = VideoMessageBubble(
        conversationId: message.conversationId,
        serverId: mediaId,
        isMine: isMine,
        isDark: isDark,
        runStart: runStart,
        status: mediaStatus,
        createdAt: message.createdAt,
        senderName: senderName,
        localId: ownUpload ? message.localId : null,
      );
    } else if (message.type == 'document' && mediaId != null) {
      core = DocumentMessageBubble(
        conversationId: message.conversationId,
        serverId: mediaId,
        isMine: isMine,
        isDark: isDark,
        runStart: runStart,
        status: mediaStatus,
        createdAt: message.createdAt,
        localId: ownUpload ? message.localId : null,
      );
    } else if (mediaId == null &&
        const {'image', 'video', 'voice', 'document'}.contains(message.type)) {
      // Optimistic upload in flight (serverId not stamped yet). Keep the
      // shape/type recognizable without changing the data layer.
      core = ExcludeSemantics(
        child: _OptimisticMediaPlaceholder(
          type: message.type,
          isMine: isMine,
          runStart: runStart,
          status: message.status,
        ),
      );
    } else if (message.type == 'sticker' &&
        !message.isDeletedForEveryone &&
        message.decryptState != 'key_missing' &&
        message.decryptState != 'failed') {
      core = StickerBubble(
        message: message,
        body: resolved,
        isMine: isMine,
        runStart: runStart,
      );
    } else if (emojiOnly) {
      core = _EmojiOnlyBubble(message: message, isMine: isMine);
    } else {
      core = _TextBubble(
        message: message,
        isMine: isMine,
        runStart: runStart,
        skeletonShell: resolved == null && !message.isDeletedForEveryone,
        highlightQuery: searchQuery,
        highlightCurrent: searchCurrent,
        url: url,
      );
    }

    // C9: in groups their bubbles leave a slot for the sender disc, which
    // sits beside the run's last bubble, bottom-aligned to the bubble.
    final grouped = isGroup && !isMine;
    final lead = grouped ? ChatBubbleGeometry.senderSlot : 0.0;
    Widget indent(Widget w) => grouped
        ? Padding(padding: EdgeInsets.only(left: lead), child: w)
        : w;
    final coreRow = grouped
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: ChatBubbleGeometry.nearMargin,
                ),
                child: SizedBox(
                  width: ChatBubbleGeometry.senderDisc,
                  child: runEnd
                      ? ExcludeSemantics(
                          child: AppAvatar(
                            radius: ChatBubbleGeometry.senderDisc / 2,
                            initials: initialsOf(senderName),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              Flexible(child: core),
            ],
          )
        : core;

    // B2: the time leaves the bubble for one line under the run's last.
    final showMeta = runEnd || ChatInfoMode.of(context);
    final metaStatus = album != null
        ? albumStatus([
            for (final m in album) mediaBubbleInputs(ref, m, isMine: isMine),
          ])
        : const {'image', 'video', 'voice', 'document'}.contains(message.type)
        ? mediaStatus
        : message.status;

    final bubble = _LiftWhileMenu(
      isMine: isMine,
      open: () => showMessageMenu(
        context: context,
        ref: ref,
        message: cover,
        album: album,
        isMine: isMine,
        senderName: senderName,
        onSelect: onSelect,
      ),
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // ── Group sender name ────────────────────────────────
          // C10: once per streak, 12 in from the bubble's edge, 4 above.
          if (grouped && streakStart)
            Padding(
              padding: EdgeInsets.only(
                left: lead + ChatBubbleGeometry.nearMargin + 12,
                bottom: 4,
              ),
              child: ExcludeSemantics(
                child: Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 13,
                    height: 18 / 13,
                    fontWeight: FontWeight.w600,
                    color: _colorForSender(
                      message.senderId,
                      Theme.of(context).brightness,
                    ),
                  ),
                ),
              ),
            ),

          // ── Reply quote (P7 / spec §3: DERIVED, never stored) ─────────
          // The presence test is the PARENT ID, not a preview string —
          // `messages.reply_preview` is dropped (schema v11). ReplyQuote
          // resolves the parent row and renders its text through
          // messageBodyProvider (placeholder while unresolved — never a
          // blank, never raw ciphertext).
          if (message.replyToId != null)
            GestureDetector(
              onTap: onReplyTap,
              child: Padding(
                padding: EdgeInsets.only(
                  left: isMine ? 0 : lead + ChatBubbleGeometry.nearMargin,
                  right: isMine ? ChatBubbleGeometry.nearMargin : 0,
                ),
                child: ReplyQuote(
                  // The quote shows WHO was replied to, not who sent THIS message.
                  // If I sent this message, I replied to the other user → show their name.
                  // If other user sent this message, they replied to me → show 'You'.
                  senderName: isMine ? senderName : 'You',
                  isMine: isMine,
                  // Local id while the reply is unsent, server id after the
                  // dual-truth stamp — ReplyQuote resolves BOTH.
                  replyToId: message.replyToId,
                  conversationId: message.conversationId,
                ),
              ),
            ),

          coreRow,

          // ── Reactions (C8: chips overlap the bubble's lower edge) ──
          if (cover.serverId != null)
            indent(
              Transform.translate(
                offset: const Offset(0, -8),
                child: ReactionBar(
                  messageServerId: cover.serverId!,
                  isMine: isMine,
                ),
              ),
            ),

          if (showMeta)
            indent(
              Padding(
                key: const ValueKey('chat-meta-line'),
                padding: ChatBubbleGeometry.margin(
                  isMine: isMine,
                ).copyWith(top: ChatBubbleGeometry.metaGap),
                child: ChatBubbleTimestamp(
                  isMine: isMine,
                  createdAt: album != null
                      ? album
                            .map((m) => m.createdAt)
                            .reduce((a, b) => a.isBefore(b) ? a : b)
                      : message.createdAt,
                  status: metaStatus,
                  starred: cover.isStarred,
                ),
              ),
            ),

          // ── Terminal-failure banner (spec: stuck message VISIBLE) ──
          // Keyed by message localId; Retry/Discard wire straight to the
          // real repo (Task 3 retryOp/discardOp — discard cascades).
          if (terminalOp != null)
            indent(
              TerminalFailureBanner(
                key: ValueKey('terminal-banner-${message.localId}'),
                isMine: isMine,
                errorClass: terminalOp.errorClass,
                onRetry: () => ref
                    .read(messageRepositoryProvider)
                    .retryOp(terminalOp.opId),
                onDiscard: () => ref
                    .read(messageRepositoryProvider)
                    .discardOp(terminalOp.opId),
              ),
            ),
        ],
      ),
    );

    // D4: the album's sideways scroll owns horizontal drags.
    Widget content = album != null
        ? bubble
        : SwipeToReply(
            isMine: isMine,
            onReply: onReply ?? () {},
            child: bubble,
          );

    // C1 / C2: 2 between bubbles of a run, 12 before a new run.
    content = Padding(
      padding: EdgeInsets.only(
        top: runStart
            ? ChatBubbleGeometry.newRunGap
            : ChatBubbleGeometry.runGap,
      ),
      child: content,
    );

    // C1: a selected row = full-row soft accent + the accent fill and ring.
    // Both always in the tree, so a toggle keeps the bubble's state.
    content = ColoredBox(
      color: selected ? context.t.accentSoft : Colors.transparent,
      child: DecoratedBox(
        decoration: selected
            ? BoxDecoration(
                border: Border.all(color: context.t.accent, width: 1.5),
                borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
              )
            : const BoxDecoration(),
        child: content,
      ),
    );

    final hasInteractiveChildren =
        terminalOp != null ||
        message.replyToId != null ||
        url != null ||
        cover.serverId != null ||
        album != null;
    // Always in the tree, so toggling selection keeps the bubble's state.
    content = IgnorePointer(
      ignoring: selecting,
      child: ExcludeSemantics(excluding: selecting, child: content),
    );
    return _messageRowSemantics(
      label: rowSemanticsLabel,
      preserveChildNodes: hasInteractiveChildren && !selecting,
      selected: selecting ? selected : null,
      onTap: selecting ? onSelect : null,
      child: content,
    );
  }
}

/// Per-type optimistic media shell. It deliberately stays presentation-only:
/// the real media widgets take over as soon as the server id is stamped.
/// F: the final size, a flat block, no shimmer next to a spinner.
/// Motion C6: a long-press lifts the bubble to 1.03 over motionFast while
/// its menu is open.
class _LiftWhileMenu extends StatefulWidget {
  const _LiftWhileMenu({
    required this.isMine,
    required this.open,
    required this.child,
  });

  final bool isMine;
  final Future<void> Function() open;
  final Widget child;

  @override
  State<_LiftWhileMenu> createState() => _LiftWhileMenuState();
}

class _LiftWhileMenuState extends State<_LiftWhileMenu> {
  bool _lifted = false;

  Future<void> _onLongPress() async {
    setState(() => _lifted = true);
    try {
      await widget.open();
    } finally {
      if (mounted) setState(() => _lifted = false);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: _onLongPress,
    child: AnimatedScale(
      scale: _lifted ? 1.03 : 1,
      duration: motionOf(context, WarmPopTokens.motionFast),
      curve: WarmPopTokens.curveEnter,
      alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: widget.child,
    ),
  );
}

class _OptimisticMediaPlaceholder extends StatelessWidget {
  const _OptimisticMediaPlaceholder({
    required this.type,
    required this.isMine,
    required this.runStart,
    required this.status,
  });

  final String type;
  final bool isMine;
  final bool runStart;
  final String status;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final failed = status == 'failed';
    final width = ChatBubbleGeometry.attachmentWidthOf(context);

    if (type == 'image' || type == 'video') {
      final video = type == 'video';
      return ChatBubbleFrame(
        isMine: isMine,
        runStart: runStart,
        background: t.surface2,
        border: const Border(),
        padding: EdgeInsets.zero,
        width: width,
        child: SizedBox(
          height: ChatBubbleGeometry.mediaHeight(width, video ? 16 / 9 : 4 / 3),
          child: Center(
            child: failed
                ? Text(kUploadNotSent, style: TextStyle(color: t.inkSoft))
                : Icon(
                    video ? Icons.videocam_outlined : Icons.photo_outlined,
                    size: 28,
                    color: t.inkFaint,
                  ),
          ),
        ),
      );
    }

    // A failed upload never gets a server id, so it stays here: say so
    // instead of spinning forever.
    final voice = type == 'voice';
    final Widget content;
    if (failed) {
      content = _FailedUploadRow(
        icon: voice ? Icons.mic_none_outlined : Icons.insert_drive_file_outlined,
        label: voice ? 'Voice note not sent' : 'Document not sent',
      );
    } else {
      content = Row(
        children: [
          SizedBox.square(
            dimension: ChatBubbleGeometry.leadingSize,
            child: Center(
              child: BusySpinner(size: 24, strokeWidth: 2, color: t.ink),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: voice
                ? SizedBox(
                    height: 28,
                    child: Opacity(
                      opacity: 0.3,
                      child: VoiceWaveform(
                        levels: generatedWaveLevels(type),
                        bars: kVoiceBubbleBars,
                        height: 28,
                        progress: 1,
                      ),
                    ),
                  )
                : Text(
                    'Uploading document…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.inkSoft, fontSize: 13),
                  ),
          ),
        ],
      );
    }
    return ChatBubbleFrame(
      isMine: isMine,
      runStart: runStart,
      padding: ChatBubbleGeometry.attachmentPadding,
      width: width,
      child: content,
    );
  }
}

/// Static row for an upload that failed; the time line's ⚠ carries the
/// state. Ink on the tint, never onAccent (E7).
class _FailedUploadRow extends StatelessWidget {
  const _FailedUploadRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        Container(
          width: ChatBubbleGeometry.leadingSize,
          height: ChatBubbleGeometry.leadingSize,
          decoration: BoxDecoration(
            color: t.ink.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
          ),
          child: Icon(icon, color: t.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: t.ink, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

// ── Terminal-failure banner (Task 4) ──────────────────────────────────────
//
// Spec §5.2: a `failedTerminal` op must be VISIBLE under its message —
// error-class text + Retry (re-queue) + Discard (cascade delete). Warm Pop
// token law: `t.error` text on `t.error` @8% bg, radius `radiusSm`,
// system fonts, no new colors (grep gate 11).

class TerminalFailureBanner extends StatelessWidget {
  const TerminalFailureBanner({
    super.key,
    required this.isMine,
    required this.errorClass,
    required this.onRetry,
    required this.onDiscard,
  });

  final bool isMine;
  final String? errorClass;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final err = context.t.error;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: ChatBubbleGeometry.margin(isMine: isMine),
        constraints: BoxConstraints(
          maxWidth: ChatBubbleGeometry.maxWidth(context),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: err.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // K3 C5: the title opens the sheet, which says why (the raw
            // class moved there).
            Semantics(
              button: true,
              // The spec's "Why it failed", after the status it replaces.
              label: 'Failed to send. Why it failed',
              excludeSemantics: true,
              child: InkWell(
                onTap: () => showFailedSendSheet(
                  context,
                  errorClass: errorClass,
                  onRetry: onRetry,
                  onDiscard: onDiscard,
                ),
                borderRadius: BorderRadius.circular(WarmPopTokens.radiusSm),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 36),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 15, color: err),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Failed to send',
                          style: TextStyle(
                            color: err,
                            fontSize: 13,
                            fontWeight: FontWeight.w600, // plan floor: ≥w600 12px
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 15, color: err),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: err,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Retry'),
                ),
                TextButton(
                  onPressed: onDiscard,
                  style: TextButton.styleFrom(
                    foregroundColor: err,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Discard'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// K3 decision 6: a terminal failure's error class in plain words.
String failedSendReason(String? errorClass) => switch (errorClass) {
  'bad_request' => 'The server turned this message down.',
  'forbidden' => "You can't send to this chat any more.",
  'dead_link' => "This chat isn't on the server any more.",
  'payload_too_large' => 'This message is too big to send.',
  'encrypt_failed' => "It couldn't be locked (encrypted) on this phone.",
  _ => 'Something went wrong while sending it.',
};

/// K3 C5: why a message failed for good. Retry and Discard close the sheet,
/// then call exactly what the banner's buttons call (V3).
Future<void> showFailedSendSheet(
  BuildContext context, {
  required String? errorClass,
  required VoidCallback onRetry,
  required VoidCallback onDiscard,
}) {
  final t = context.t;
  return showAppSheet<void>(
    context: context,
    builder: (sheet) {
      void close(VoidCallback then) {
        Navigator.of(sheet).pop();
        then();
      }

      return AppSheetChrome(
        title: 'Message not sent',
        children: [
          Row(
            children: [
              const Capy(
                view: CapyView.head,
                size: 48,
                mood: CapyMood.worried,
                flip: true,
                pettable: false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      failedSendReason(errorClass),
                      style: TextStyle(
                        fontSize: 15,
                        height: 22 / 15,
                        color: t.ink,
                      ),
                    ),
                    if (errorClass != null)
                      Text(
                        'Code: $errorClass',
                        style: TextStyle(fontSize: 12, color: t.inkSoft),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppButton(
            expanded: true,
            onPressed: () => close(onRetry),
            child: const Text('Retry'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => close(onDiscard),
            style: TextButton.styleFrom(
              foregroundColor: t.error,
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Discard'),
          ),
        ],
      );
    },
  );
}

// ── Emoji-only (no bubble, large font) ────────────────────────────────────

class _EmojiOnlyBubble extends StatelessWidget {
  const _EmojiOnlyBubble({required this.message, required this.isMine});
  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return ChatBubbleFrame(
      isMine: isMine,
      chrome: false,
      padding: EdgeInsets.zero,
      child: ExcludeSemantics(
        child: MessageBodyText(
          messageId: message.localId,
          styleContext: 'emoji',
          decryptState: message.decryptState,
          ciphertextLength: message.ciphertextLength,
        ),
      ),
    );
  }
}

// ── Standard text bubble ──────────────────────────────────────────────────

class _TextBubble extends StatelessWidget {
  const _TextBubble({
    required this.message,
    required this.isMine,
    required this.runStart,
    required this.skeletonShell,
    this.highlightQuery,
    this.highlightCurrent = false,
    this.url,
  });

  final Message message;
  final bool isMine;
  final bool runStart;
  final bool skeletonShell;
  final String? highlightQuery;
  final bool highlightCurrent;
  final String? url;

  @override
  Widget build(BuildContext context) {
    // F: while the text decrypts, the bubble itself is the placeholder in
    // its real shape (B1) and size; terminal decrypt states never are.
    final placeholder =
        skeletonShell &&
        message.decryptState != 'key_missing' &&
        message.decryptState != 'failed';
    final frame = ChatBubbleFrame(
      isMine: isMine,
      runStart: runStart,
      background: placeholder && !isMine ? context.t.surface2 : null,
      border: placeholder ? const Border() : null,
      child: Column(
        // B6: always start-aligned.
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.isDeletedForEveryone)
            ExcludeSemantics(
              child: Text(
                '🚫 Message deleted',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                  color: context.t.inkSoft,
                ),
              ),
            )
          else
            ExcludeSemantics(
              child: MessageBodyText(
                messageId: message.localId,
                styleContext: isMine ? 'bubble.mine' : 'bubble',
                decryptState: message.decryptState,
                ciphertextLength: message.ciphertextLength,
                skeletonShell: skeletonShell,
                highlightQuery: highlightQuery,
                highlightCurrent: highlightCurrent,
              ),
            ),

          // Link preview
          if (url != null && !message.isDeletedForEveryone && !placeholder)
            LinkPreviewCard(url: url!),
        ],
      ),
    );
    return placeholder ? SkeletonBreath(child: frame) : frame;
  }
}

// ── System / info bubble ───────────────────────────────────────────────────
//
// WhastApp-style narrative info row rendered for 'system' messages (group
// created, member added/removed, role change, etc). Always centered,
// always grey, no sender colour metadata, no bubbles, no long-press.

class _SystemMessageBubble extends StatelessWidget {
  const _SystemMessageBubble({
    required this.messageId,
    required this.decryptState,
    required this.ciphertextLength,
  });
  final String messageId;
  final String decryptState;
  final int ciphertextLength;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: context.t.surface2.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          // T9: system bodies ride the same placeholder law — cache-resident
          // local emits paint instantly; an unresolved id shows the keyed
          // placeholder inside the pill (never a blank narrative row).
          child: ExcludeSemantics(
            child: MessageBodyText(
              messageId: messageId,
              styleContext: 'system',
              decryptState: decryptState,
              ciphertextLength: ciphertextLength,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: context.t.ink.withValues(alpha: 0.55),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
