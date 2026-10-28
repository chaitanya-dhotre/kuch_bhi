import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../domain/entities/group_invite.dart';
import 'request_card.dart';

class GroupInviteCard extends StatelessWidget {
  const GroupInviteCard({
    super.key,
    required this.invite,
    required this.locked,
    required this.offline,
    required this.onAccept,
    required this.onDecline,
    this.busyAction,
  });

  final GroupInvite invite;
  final bool locked;
  final bool offline;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final RequestAction? busyAction;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final groupName = _groupName(invite.conversationName);
    final inviterName = invite.invitedBy.displayName.trim();
    final meta = inviterName.isEmpty
        ? 'You were invited to join'
        : '${_displayName(inviterName)} invited you to join';
    final semanticInviter = inviterName.isEmpty ? 'Someone' : inviterName;
    final semanticLabel = 'Group invite to $groupName, from $semanticInviter';
    final disabled = locked || offline;

    return Semantics(
      container: true,
      label: semanticLabel,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(WarmPopTokens.radiusMd),
            boxShadow: WarmPopTokens.cardShadow(t.shadow),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    ExcludeSemantics(
                      child: _GroupAvatar(initials: _initials(groupName)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            groupName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.ink,
                              fontSize: 16,
                              height: 1.375,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.inkSoft,
                              fontSize: 13,
                              height: 1.385,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Opacity(
                  opacity: offline ? .38 : 1,
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: 'Decline, $groupName',
                          child: AppButton(
                            onPressed: disabled ? null : onDecline,
                            variant: AppButtonVariant.secondary,
                            busy: busyAction == RequestAction.decline,
                            child: const Text('Decline'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: 'Accept, $groupName',
                          child: AppButton(
                            onPressed: disabled ? null : onAccept,
                            busy: busyAction == RequestAction.accept,
                            child: const Text('Accept'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (offline)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Available online',
                        style: TextStyle(fontSize: 12, color: t.inkFaint),
                      ),
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

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AppAvatar(initials: initials, radius: 26, accentSoft: true),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: t.accent,
              shape: BoxShape.circle,
              border: Border.all(color: t.surface, width: 2),
            ),
            child: Icon(Icons.group, size: 12, color: t.onAccent),
          ),
        ),
      ],
    );
  }
}

String _groupName(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Group' : trimmed;
}

String _displayName(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Someone' : trimmed;
}

String _initials(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
}
