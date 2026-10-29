import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/decrypt/body_cache.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/entities/message.dart';
import '../../../infrastructure/offline/connectivity_signal.dart';
import '../../../infrastructure/repositories/message_repository_impl.dart';
import '../message_offline_policy.dart';
import '../providers/chat_provider.dart';
import '../providers/message_body_provider.dart';
import '../../../core/theme/tokens.dart';
import 'message_body_text.dart';

// Extended emoji set — horizontally scrollable
const _reactionEmojis = [
  '👍',
  '👎',
  '❤️',
  '🔥',
  '😂',
  '😮',
  '😢',
  '🙏',
  '🎉',
  '💯',
  '😍',
  '🤔',
  '😡',
  '👏',
  '🤣',
  '😊',
  '💪',
  '🫡',
  '✅',
  '❌',
  '⭐',
  '💎',
  '🚀',
  '😴',
  '🥹',
  '🫶',
  '😎',
  '🤯',
  '🥳',
  '👀',
  '💀',
  '🫠',
];

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

void showMessageMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Message message,
  required bool isMine,
  required String senderName,
  VoidCallback? onSelect,
}) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(WarmPopTokens.radiusLg),
      ),
    ),
    builder: (_) => _ContextSheet(
      message: message,
      isMine: isMine,
      senderName: senderName,
      onSelect: onSelect,
      parentRef: ref,
    ),
  );
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
void showActionSheet({
  required BuildContext context,
  Widget? header,
  required List<ConversationMenuAction> actions,
  Key? sheetKey,
  Key? handleKey,
  Key? previewKey,
}) {
  HapticFeedback.mediumImpact();
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(WarmPopTokens.radiusLg),
      ),
    ),
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
        initials: _initialsFor(name),
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
    return _ContextSheetChrome(
      key: sheetKey,
      handleKey: handleKey,
      previewKey: previewKey,
      header: header ?? const SizedBox.shrink(),
      children: [
        if (actions.isNotEmpty) const Divider(height: 20),
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
    final trailing = action.trailing == null
        ? null
        : Text(
            action.trailing!,
            style: TextStyle(
              fontSize: 12,
              color: action.enabled ? context.t.inkSoft : null,
            ),
          );
    return _menuActionTile(
      key: ValueKey('conversation-menu-action-$index'),
      icon: action.icon,
      // Registry C4b: destructive rows get an error icon and an INK label.
      iconColor: action.destructive ? context.t.error : null,
      labelColor: action.destructive ? context.t.ink : null,
      label: action.label,
      onTap: () {
        Navigator.of(context).pop();
        action.invoke();
      },
      trailing: trailing,
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
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 20,
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

class _ContextSheetChrome extends StatelessWidget {
  const _ContextSheetChrome({
    super.key,
    required this.handleKey,
    required this.header,
    required this.children,
    this.previewKey,
  });

  final Key handleKey;
  final Key? previewKey;
  final Widget header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final headerWidget =
        previewKey == null ? header : KeyedSubtree(key: previewKey, child: header);
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = (mediaQuery.size.height - mediaQuery.viewInsets.bottom)
        .clamp(0.0, mediaQuery.size.height)
        .toDouble();
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            mediaQuery.viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  key: handleKey,
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              headerWidget,
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

Widget _menuActionTile({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  Key? key,
  Widget? trailing,
  Color? color,
  Color? iconColor,
  Color? labelColor,
  bool enabled = true,
  String? semanticsLabel,
}) {
  final tile = ListTile(
    key: key,
    leading: Icon(icon, color: enabled ? (iconColor ?? color) : null),
    title: Text(
      label,
      style: TextStyle(
        color: enabled ? (labelColor ?? color) : null,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
    ),
    trailing: trailing,
    onTap: enabled ? onTap : null,
    enabled: enabled,
    dense: true,
    contentPadding: EdgeInsets.zero,
  );
  final styledTile = tile;
  if (semanticsLabel == null) return styledTile;
  return Semantics(
    label: semanticsLabel,
    button: true,
    enabled: enabled,
    child: styledTile,
  );
}

Widget _conversationPreview(BuildContext context, Object preview) {
  if (preview is Widget) return preview;
  return Text(
    preview.toString(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontSize: 13, color: context.t.inkSoft),
  );
}

String _initialsFor(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
}

class _ContextSheet extends ConsumerWidget {
  const _ContextSheet({
    required this.message,
    required this.isMine,
    required this.senderName,
    required this.parentRef,
    this.onSelect,
  });

  final Message message;
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
    // delete-for-everyone, react) render disabled with a hint offline —
    // never a silent no-op. Loading/error → online (fail-safe: controls
    // stay enabled when the signal is unknown).
    final isOnline = ref.watch(isOnlineProvider).value ?? true;

    return _ContextSheetChrome(
      key: const Key('message-context-menu'),
      handleKey: const Key('message-menu-handle'),
      previewKey: const Key('message-menu-preview'),
      header: _previewRow(
        context,
        avatar: AppAvatar(
          initials: _initialsFor(senderName),
          radius: 20,
          accentSoft: true,
        ),
        name: senderName,
        nameKey: const Key('message-menu-preview-sender'),
        preview: ClipRect(
          child: MessageBodyText(
            key: const Key('message-menu-preview-body'),
            messageId: message.localId,
            styleContext: 'preview',
            decryptState: message.decryptState,
            ciphertextLength: message.ciphertextLength,
            style: TextStyle(fontSize: 13, color: context.t.inkSoft),
          ),
        ),
      ),
      children: [
        // Scrollable reaction row — disabled offline (P4: reactions are
        // network-only; a tap must never look like it worked).
        Builder(
          builder: (context) {
            final reactionsEnabled = isMessageActionEnabled(
              MessageAction.react,
              isOnline: isOnline,
            );
            return Column(
              children: [
                SizedBox(
                  height: 52,
                  child: IgnorePointer(
                    ignoring: !reactionsEnabled,
                    child: Opacity(
                      opacity: reactionsEnabled ? 1 : 0.38,
                      child: ListView.separated(
                        key: const Key('message-menu-reaction-row'),
                        scrollDirection: Axis.horizontal,
                        itemCount: _reactionEmojis.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          if (i == _reactionEmojis.length) {
                            return _reactionPickerButton(
                              context,
                              onTap: () => _showReactionPicker(context, ref),
                            );
                          }
                          final emoji = _reactionEmojis[i];
                          return GestureDetector(
                            key: ValueKey('message-menu-reaction-$emoji'),
                            onTap: () async {
                              if (message.serverId != null) {
                                await repo.addReaction(
                                  message.serverId!,
                                  emoji,
                                );
                              }
                              if (context.mounted) _afterAction(context);
                            },
                            child: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 22),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                if (!reactionsEnabled)
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(kOfflineActionHint),
                  ),
              ],
            );
          },
        ),

        const Divider(height: 20),

        // Actions
        _tile(Icons.reply_rounded, 'Reply', () {
          parentRef.read(replyProvider.notifier).state = message;
          Navigator.of(context).pop();
        }, key: const Key('message-menu-reply')),

        if (onSelect != null)
          _tile(Icons.checklist_rounded, 'Select', () {
            onSelect!.call();
            Navigator.of(context).pop();
          }, key: const Key('message-menu-select')),

        if (body.isNotEmpty)
          _tile(Icons.copy_outlined, 'Copy', () {
            Clipboard.setData(ClipboardData(text: body));
            _afterAction(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied'),
                duration: Duration(seconds: 1),
              ),
            );
          }, key: const Key('message-menu-copy')),

        _tile(
          message.isStarred ? Icons.star : Icons.star_outline,
          message.isStarred ? 'Unstar' : 'Star',
          () async {
            await repo.toggleStar(message.localId);
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(e.message)));
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
            final confirmed = await _confirmDelete(
              context,
              'This message will be deleted for you only.',
            );
            if (!confirmed) return;
            await repo.deleteMessage(message.localId);
            if (context.mounted) _afterAction(context);
          },
          color: context.t.error,
          key: const Key('message-menu-delete-me'),
        ),

        if (isMine && message.serverId != null)
          _tile(
            Icons.delete_forever_outlined,
            'Delete for everyone',
            () async {
              final confirmed = await _confirmDelete(
                context,
                'This message will be deleted for everyone in this chat.',
              );
              if (!confirmed) return;
              await repo.deleteMessage(message.localId, forEveryone: true);
              if (context.mounted) _afterAction(context);
            },
            color: context.t.error,
            // P4: delete-for-everyone is server-first; offline the local
            // mark is reverted by the next fetch. Disable + hint.
            enabled: isMessageActionEnabled(
              MessageAction.deleteForEveryone,
              isOnline: isOnline,
            ),
            key: const Key('message-menu-delete-all'),
          ),
      ],
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message?'),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _reactionPickerButton(
    BuildContext context, {
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: const Key('message-menu-reaction-add'),
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: context.t.surface,
          border: Border.all(color: context.t.line),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text('＋', style: TextStyle(color: context.t.inkSoft)),
        ),
      ),
    );
  }

  Future<void> _showReactionPicker(BuildContext context, WidgetRef ref) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(WarmPopTokens.radiusLg),
        ),
      ),
      showDragHandle: true,
      builder: (pickerContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(pickerContext).height * 0.9,
          ),
          child: GridView.count(
            key: const Key('message-menu-reaction-picker'),
            crossAxisCount: 6,
            padding: const EdgeInsets.all(16),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final emoji in _reactionEmojis)
                InkResponse(
                  key: ValueKey('message-menu-picker-$emoji'),
                  onTap: () => Navigator.of(pickerContext).pop(emoji),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
    Color? color,
    bool enabled = true,
  }) {
    return _menuActionTile(
      key: key,
      // P4 defined-offline: disabled tiles show the hint instead of a
      // silent no-op (user ruling 2).
      icon: icon,
      label: label,
      onTap: onTap,
      trailing: enabled ? null : const Text(kOfflineActionHint),
      color: color,
      enabled: enabled,
    );
  }
}
