import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../core/widgets/app_button.dart';
import '../../../domain/entities/friend_request.dart';

enum RequestAction { accept, decline }

class RequestCard extends StatelessWidget {
  const RequestCard({
    super.key,
    required this.request,
    required this.locked,
    required this.offline,
    required this.onAccept,
    required this.onDecline,
    this.busyAction,
  });

  final FriendRequest request;
  final bool locked;
  final bool offline;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final RequestAction? busyAction;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final name = _displayName(request.fromUser.displayName);
    final username = request.fromUser.username.trim();
    final meta = '@${username.isEmpty ? 'unknown' : username}';
    final semanticLabel = 'Friend request from $name, $meta';
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
                      child: AppAvatar(
                        initials: initialsOf(name),
                        url: request.fromUser.avatarUrl,
                        radius: 26,
                        accentSoft: true,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
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
                          label: 'Decline, $name',
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
                          label: 'Accept, $name',
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

String _displayName(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'Unknown' : trimmed;
}
