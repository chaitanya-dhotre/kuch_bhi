import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/services/fcm_service.dart';

void main() {
  test('notification text covers every type, privacy mode, and fallback', () {
    final full = <String, Map<String, String>>{
      'new_message': {'sender_name': 'Ada', 'preview': 'Photo'},
      'friend_request': {'from_user_name': 'Ada'},
      'group_invite': {'inviter_name': 'Ada', 'conversation_name': 'Friends'},
    };
    const hidden = {
      'new_message': ('Kuch Bhi', 'New message'),
      'friend_request': ('Kuch Bhi', 'New friend request'),
      'group_invite': ('Kuch Bhi', 'New group invite'),
    };
    const visible = {
      'new_message': ('Ada', 'Photo'),
      'friend_request': ('Friend request', 'Ada wants to connect'),
      'group_invite': ('Group invite', 'Ada invited you to Friends'),
    };
    const fallback = {
      'new_message': ('New message', 'Sent you a message'),
      'friend_request': ('Friend request', 'You have a new friend request'),
      'group_invite': ('Group invite', 'You were invited to a group'),
    };

    for (final type in full.keys) {
      expect(
        FcmService.notificationText(
          type: type,
          data: const {},
          hideNames: true,
        ),
        hidden[type],
        reason: '$type hidden with empty data',
      );
      expect(
        FcmService.notificationText(
          type: type,
          data: full[type]!,
          hideNames: false,
        ),
        visible[type],
        reason: '$type visible with names',
      );
      expect(
        FcmService.notificationText(
          type: type,
          data: const {},
          hideNames: false,
        ),
        fallback[type],
        reason: '$type visible fallback',
      );
    }
  });
}
