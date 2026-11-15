import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/decrypt/body_cache.dart';
import '../../../core/utils/app_haptic.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_dialog.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../message_offline_policy.dart';
import '../providers/chat_provider.dart';
import '../providers/message_body_provider.dart';
import '../chat_run_grouping.dart' show albumLabel;
import '../../../core/theme/tokens.dart';
import 'message_body_text.dart';
import 'reaction_picker.dart';

/// The chat's multi-select delete: one confirm naming the count, in the
/// single "Delete for me" wording, then [delete] per message. False =
/// cancelled, nothing deleted.
Future<bool> confirmAndDeleteForMe(
  BuildContext context,
  List<String> localIds,
  Future<void> Function(String localId) delete,
) async {
  final one = localIds.length == 1;
  final ok = await showConfirmDialog(
    context: context,
    title: one ? 'Delete message?' : 'Delete ${localIds.length} messages?',
    body: one
        ? 'This message will be deleted for you only.'
        : 'These messages will be deleted for you only.',
    confirmLabel: 'Delete',
    confirmIcon: Icons.delete_outline,
    destructive: true,
  );
  if (!ok) return false;
  for (final id in localIds) {
    await delete(id);
  }
  return true;
}

/// A row displayed by [showConversationMenu].
///
/// [callback] is the canonical callback name. [onTap] is accepted as a
/// convenience alias for call sites that build actions alongside [ListTile]
/// widgets. Exactly one callback must be supplied.
class ConversationMenuAction {
  const ConversationMenuAction({
    required this.label,
    required this.icon,
    VoidCallback? callback,
    VoidCallback? onTap,
    this.trailing,
    this.enabled = true,
    this.destructive = false,
    String? semanticsLabel,
    String? semantics,
  }) : assert(
         callback != null || onTap != null,
         'ConversationMenuAction requires callback or onTap',
       ),
       _callback = callback ?? onTap,
       semanticsLabel = semanticsLabel ?? semantics;

  final String label;
  final IconData icon;
  final VoidCallback? _callback;
  VoidCallback get callback => _callback!;
  VoidCallback get onTap => callback;
  final String? trailing;
  final bool enabled;

  /// Registry C4b: an error ICON with an INK label (error-coloured text
  /// fails 4.5:1 on light surfaces — foundation C4).
  final bool destructive;
  final String? semanticsLabel;

  /// Alias for callers that prefer the shorter semantics property name.
  String? get semantics => semanticsLabel;

  VoidCallback get invoke => callback;
}

Future<void> showMessageMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Message message,
  required bool isMine,
  required String senderName,
  List<Message>? album,
  VoidCallback? onSelect,
}) {
  appHaptic(HapticsType.medium);
  return showAppSheet<void>(
    context: context,
    useRootNavigator: true,
    exit: WarmPopTokens.motionFast, // C6: the menu leaves in 150 ms
    builder: (_) => _ContextSheet(
      message: message,
      album: album,
      isMine: isMine,
      senderName: senderName,
      onSelect: onSelect,
      parentRef: ref,
    ),
  );
}

/// Motion C6: quick-reaction [index] follows the one before it by 30 ms
/// (six at most), scaling up from 0.6 as it fades in with the sheet.
class _Stagger extends StatelessWidget {
  const _Stagger({
    required this.index,
    required this.route,
    required this.child,
  });

  final int index;
  final Animation<double> route;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 30 ms of the sheet's 250 ms enter per step; each runs 150 ms.
    final start = (index.clamp(0, 5) * 30) / 250;
    final curve = Interval(
      start,
      math.min(1, start + 150 / 250),
      curve: WarmPopTokens.curveEnter,
    );
    // Transitions, not Opacity: at rest nothing extra is in the tree.
    final v = route.drive(CurveTween(curve: curve));
    return FadeTransition(
      opacity: v,
      child: ScaleTransition(
        scale: v.drive(Tween(begin: 0.6, end: 1.0)),
        child: child,
      ),
    );
  }
}

/// Registry C4a — the shared action sheet.
///
/// Owns presentation and action dispatch only: navigation and provider
/// mutations stay in the supplied action callbacks. [showConversationMenu]
/// (Home long-press) is a thin caller of this, so both surfaces share ONE
/// chrome.
///
/// The optional key parameters exist so existing call sites (and their
/// tests) keep addressing the same widgets; they default to generic keys.
/// [haptic] is for long-press openers; a button-opened sheet passes false.
void showActionSheet({
  required BuildContext context,
  Widget? header,
  required List<ConversationMenuAction> actions,
  Key? sheetKey,
  Key? handleKey,
  Key? previewKey,
  bool haptic = true,
}) {
  if (haptic) appHaptic(HapticsType.medium);
  showAppSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _ActionSheet(
      sheetKey: sheetKey ?? const Key('action-sheet'),
      handleKey: handleKey ?? const Key('action-sheet-handle'),
      previewKey: previewKey,
      header: header,
      actions: actions,
    ),
  );
}

/// Opens the reusable conversation action sheet used by Home long-presses.
///
/// The sheet intentionally owns only shared presentation and action dispatch.
/// Navigation and provider mutations stay in the supplied action callbacks.
void showConversationMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Conversation conversation,
  required Object preview,
  required List<ConversationMenuAction> actions,
}) {
  final name = conversation.displayName;
  showActionSheet(
    context: context,
    sheetKey: const Key('conversation-context-menu'),
    handleKey: const Key('conversation-menu-handle'),
    previewKey: const Key('conversation-menu-preview'),
    header: _previewRow(
      context,
      avatar: AppAvatar(
        url: conversation.avatarUrl,
        initials: initialsOf(name),
        radius: 20,
        accentSoft: true,
      ),
      avatarKey: const Key('conversation-menu-preview-avatar'),
      name: name,
      nameKey: const Key('conversation-menu-preview-name'),
      preview: _conversationPreview(context, preview),
    ),
    actions: actions,
  );
}

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({
    required this.sheetKey,
    required this.handleKey,
    required this.previewKey,
    required this.header,
    required this.actions,
  });

  final Key sheetKey;
  final Key handleKey;
  final Key? previewKey;
  final Widget? header;
  final List<ConversationMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final h = header;
    return AppSheetChrome(
      key: sheetKey,
      handleKey: handleKey,
      // F2: the divider comes with the header; none without one.
      header: h == null || previewKey == null
          ? h
          : KeyedSubtree(key: previewKey, child: h),
      children: [
        for (var i = 0; i < actions.length; i++)
          _conversationActionTile(context, actions[i], i),
      ],
    );
  }

  Widget _conversationActionTile(
    BuildContext context,
    ConversationMenuAction action,
    int index,
  ) {
    return SheetActionRow(
      key: ValueKey('conversation-menu-action-$index'),
      icon: action.icon,
      // Registry C4b: destructive rows get an error icon and an INK label.
      destructive: action.destructive,
      label: action.label,
      onTap: () {
        Navigator.of(context).pop();
        action.invoke();
      },
      trailing: action.trailing,
      enabled: action.enabled,
      semanticsLabel: action.semanticsLabel,
    );
  }
}

/// The avatar + name + preview row shared by the conversation and message
/// sheets (keys preserved so existing tests keep addressing them).
Widget _previewRow(
  BuildContext context, {
  required Widget avatar,
  Key? avatarKey,
  required String name,
  required Key nameKey,
  required Widget preview,
}) {
  final avatarWidget =
      avatarKey == null ? avatar : KeyedSubtree(key: avatarKey, child: avatar);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      avatarWidget,
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              key: nameKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.t.ink,
                fontSize: 15,
                height: 22 / 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            // A minimum, not a fixed height: 200% text must not clip (B4).
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: preview,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _conversationPreview(BuildContext context, Object preview) {
  if (preview is Widget) return preview;
  return Text(
    preview.toString(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: 13, height: 18 / 13, color: context.t.inkSoft),
  );
}

class _ContextSheet extends ConsumerWidget {
  const _ContextSheet({
    required this.message,
    required this.isMine,
    required this.senderName,
    required this.parentRef,
    this.album,
    this.onSelect,
  });

  final Message message;

  /// 12.5 F1: an album's rows in order; [message] is its cover. Null for a
  /// single message.
  final List<Message>? album;
  final bool isMine;
  final String senderName;
  final WidgetRef parentRef;
  final VoidCallback? onSelect;

  void _afterAction(BuildContext context) {
    Navigator.of(context).pop();
    // Invalidate pinned cache so UI refreshes immediately
    // Reactions are now reactive via StreamProvider, no manual invalidation needed
    parentRef.invalidate(pinnedMessagesProvider(message.conversationId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(messageRepositoryProvider);
    final body =
        bodyCache.get(message.localId) ??
        ref.watch(messageBodyProvider(message.localId)).valueOrNull ??
        '';
    // P4 (user ruling 2): defined-offline gating. Unwired actions (pin,
    // delete-for-everyone) render disabled with a hint offline —
    // never a silent no-op. Loading/error → online (fail-safe: controls
    // stay enabled when the signal is unknown).
    final isOnline = ref.watch(isOnlineProvider).value ?? true;

    final name = isMine ? 'You' : senderName;
    final previewStyle =
        TextStyle(fontSize: 13, height: 18 / 13, color: context.t.inkSoft);
    // 12.5 F1: an album's actions split between its cover (react, reply,
    // pin) and every row (star, delete, cancel the unsent ones).
    final rows = album ?? const <Message>[];
    final isAlbum = album != null && album!.length > 1;
    final albumPreview = isAlbum ? albumLabel(rows) : null;
    final allStarred = isAlbum && rows.every((m) => m.isStarred);
    final canDeleteEveryone =
        isAlbum ? isMine && rows.any((m) => m.serverId != null)
            : isMine && message.serverId != null;
    final unsent = isAlbum && isMine
        ? rows
              .where((m) => !const {'sent', 'delivered', 'read'}.contains(m.status))
              .toList()
        : const <Message>[];

    // C6: the menu grows from the bubble's side at 0.95 with the sheet.
    final route = ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    return AnimatedBuilder(
      animation: route,
      builder: (context, child) => Transform.scale(
        scale: 0.95 + 0.05 * WarmPopTokens.curveEnter.transform(route.value),
        alignment: isMine ? Alignment.bottomRight : Alignment.bottomLeft,
        child: child,
      ),
      child: AppSheetChrome(
      key: const Key('message-context-menu'),
      handleKey: const Key('message-menu-handle'),
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyedSubtree(
            key: const Key('message-menu-preview'),
            child: _previewRow(
              context,
              avatar: AppAvatar(
                initials: initialsOf(name),
                radius: 20,
                accentSoft: true,
              ),
              name: name,
              nameKey: const Key('message-menu-preview-sender'),
              // Media has no text body: its placeholder would load forever.
              preview: message.type == 'text'
                  ? ClipRect(
                      child: MessageBodyText(
                        key: const Key('message-menu-preview-body'),
                        messageId: message.localId,
                        styleContext: 'preview',
                        decryptState: message.decryptState,
                        ciphertextLength: message.ciphertextLength,
                        style: previewStyle,
                      ),
                    )
                  : Text(
                      albumPreview ?? conversationPreviewLabel(message.type),
                      key: const Key('message-menu-preview-body'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: previewStyle,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          // Quick reactions (decision 11). Offline-first: a tap is queued.
          Wrap(
            key: const Key('message-menu-reaction-row'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, emoji) in kQuickReactions.indexed)
                _Stagger(
                  index: i,
                  route: route,
                  child: _reactionCircle(
                  context,
                  key: ValueKey('message-menu-reaction-$emoji'),
                  label: emoji,
                  onTap: () async {
                    if (message.serverId != null) {
                      await repo.addReaction(
                        message.serverId!,
                        emoji,
                      );
                    }
                    if (context.mounted) _afterAction(context);
                  },
                  child: Text(
                    emoji,
                    textScaler: TextScaler.noScaling,
                    style: const TextStyle(fontSize: 22),
                  ),
                ),
                ),
              _reactionPickerButton(
                context,
                onTap: () => _showReactionPicker(context, ref),
              ),
            ],
          ),
        ],
      ),
      children: [
        // Actions
        _tile(Icons.reply_rounded, 'Reply', () {
          parentRef
              .read(replyProvider(message.conversationId).notifier)
              .state = message;
          Navigator.of(context).pop();
        }, key: const Key('message-menu-reply')),

        if (onSelect != null)
          _tile(Icons.checklist_rounded, 'Select', () {
            onSelect!.call();
            Navigator.of(context).pop();
          }, key: const Key('message-menu-select')),

        // J2.4.1: a sticker's body is its wire id, not text to copy.
        if (!isAlbum && body.isNotEmpty && message.type != 'sticker')
          _tile(Icons.copy_outlined, 'Copy', () {
            Clipboard.setData(ClipboardData(text: body));
            _afterAction(context);
            showToast(context, 'Copied');
          }, key: const Key('message-menu-copy')),

        _tile(
          allStarred ? Icons.star : Icons.star_outline,
          allStarred ? 'Unstar' : 'Star',
          () async {
            if (isAlbum) {
              // 12.8 decision 12: paced server writes, not 20 at once.
              await repo.setStarred([
                for (final row in rows)
                  if (allStarred || !row.isStarred) row.localId,
              ], !allStarred);
            } else {
              await repo.toggleStar(message.localId);
            }
            if (context.mounted) _afterAction(context);
          },
          key: const Key('message-menu-star'),
        ),

        _tile(
          message.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          message.isPinned ? 'Unpin' : 'Pin',
          () async {
            try {
              await repo.togglePin(
                message.localId,
                message.conversationId,
                !message.isPinned,
              );
              if (context.mounted) _afterAction(context);
            } on StateError catch (e) {
              if (context.mounted) {
                Navigator.of(context).pop();
                showToast(context, e.message, error: true);
              }
            }
          },
          // P4: pin reverts from server truth on next fetch — offline it
          // would look applied then silently disappear. Disable + hint.
          enabled: isMessageActionEnabled(
            MessageAction.pin,
            isOnline: isOnline,
          ),
          key: const Key('message-menu-pin'),
        ),

        _tile(
          Icons.delete_outline,
          'Delete for me',
          () async {
            if (isAlbum) {
              final ok = await confirmAndDeleteForMe(
                context,
                [for (final row in rows) row.localId],
                (id) => repo.deleteMessage(id),
              );
              if (!ok) return;
            } else {
              final confirmed = await _confirmDelete(
                context,
                'This message will be deleted for you only.',
              );
              if (!confirmed) return;
              await repo.deleteMessage(message.localId);
            }
            if (context.mounted) _afterAction(context);
          },
          destructive: true,
          key: const Key('message-menu-delete-me'),
        ),

        if (canDeleteEveryone)
          _tile(
            Icons.delete_forever_outlined,
            'Delete for everyone',
            () async {
              if (isAlbum) {
                final ok = await showConfirmDialog(
                  context: context,
                  title: 'Delete ${rows.length} messages?',
                  body:
                      'These messages will be deleted for everyone in this chat.',
                  confirmLabel: 'Delete',
                  confirmIcon: Icons.delete_outline,
                  destructive: true,
                );
                if (!ok) return;
                for (final row in rows) {
                  await repo.deleteMessage(row.localId, forEveryone: true);
                }
              } else {
                final confirmed = await _confirmDelete(
                  context,
                  'This message will be deleted for everyone in this chat.',
                );
                if (!confirmed) return;
                await repo.deleteMessage(
                  message.localId,
                  forEveryone: true,
                );
              }
              if (context.mounted) _afterAction(context);
            },
            destructive: true,
            // P4: delete-for-everyone is server-first; offline the local
            // mark is reverted by the next fetch. Disable + hint.
            enabled: isMessageActionEnabled(
              MessageAction.deleteForEveryone,
              isOnline: isOnline,
            ),
            key: const Key('message-menu-delete-all'),
          ),

        // 12.5 B9/F1: while any own item is unsent, the rest can be
        // cancelled in one go; already-sent items stay.
        if (unsent.isNotEmpty)
          _tile(
            Icons.cancel_outlined,
            'Cancel sending',
            () async {
              for (final row in unsent) {
                await repo.cancelMediaUpload(row.localId);
              }
              if (context.mounted) {
                Navigator.of(context).pop();
                showToast(context, 'Upload cancelled');
              }
            },
            key: const Key('message-menu-cancel-sending'),
          ),
      ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String body) {
    return showConfirmDialog(
      context: context,
      title: 'Delete message?',
      body: body,
      confirmLabel: 'Delete',
      confirmIcon: Icons.delete_outline,
      destructive: true,
    );
  }

  /// A 48 reaction circle (the tap floor), a button named by [label].
  Widget _reactionCircle(
    BuildContext context, {
    required Key key,
    required String label,
    required VoidCallback onTap,
    required Widget child,
    bool outlined = false,
  }) {
    final t = context.t;
    return Semantics(
      button: true,
      label: label,
      // excludeSemantics drops the child's tap; give it back here.
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: outlined ? t.surface : t.surface2,
            border: outlined ? Border.all(color: t.line) : null,
            shape: BoxShape.circle,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _reactionPickerButton(
    BuildContext context, {
    required VoidCallback onTap,
  }) {
    return _reactionCircle(
      context,
      key: const Key('message-menu-reaction-add'),
      label: 'More reactions',
      outlined: true,
      onTap: onTap,
      child: Icon(Icons.add, size: 22, color: context.t.inkSoft),
    );
  }

  Future<void> _showReactionPicker(BuildContext context, WidgetRef ref) async {
    final selected = await showReactionPicker(context);
    if (selected == null || message.serverId == null) return;
    await ref
        .read(messageRepositoryProvider)
        .addReaction(message.serverId!, selected);
    if (context.mounted) _afterAction(context);
  }

  Widget _tile(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Key? key,
    bool destructive = false,
    bool enabled = true,
  }) {
    return SheetActionRow(
      key: key,
      // P4 defined-offline: disabled tiles show the hint instead of a
      // silent no-op (user ruling 2).
      icon: icon,
      label: label,
      onTap: onTap,
      trailing: enabled ? null : kOfflineActionHint,
      destructive: destructive,
      enabled: enabled,
    );
  }
}
