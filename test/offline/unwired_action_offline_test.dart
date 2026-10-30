/// P4 (user ruling 2): unwired message actions must have a DEFINED offline
/// behavior — never a silent no-op that looks like it worked.
///
/// Contract (pure policy, pinned here):
/// - Network-only / server-truth-clobbered actions: pin, delete-for-everyone,
///   react → DISABLED offline with the hint [kOfflineActionHint].
/// - Durable-local actions: star (P4 ruling 1), delete-for-me, reply, copy
///   → stay ENABLED offline.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/chat/message_offline_policy.dart';

void main() {
  test('network-required set: pin, deleteForEveryone — nothing else',
      () {
    expect(messageActionRequiresOnline(MessageAction.pin), isTrue,
        reason: 'pin writes local but fetch/SSE clobbers from server truth — '
            'offline it looks applied then silently reverts');
    expect(messageActionRequiresOnline(MessageAction.deleteForEveryone), isTrue,
        reason: 'delete-for-everyone is server-first; offline the local tombstone '
            'is reverted by the next fetch');
    expect(messageActionRequiresOnline(MessageAction.react), isFalse,
        reason: 'reactions are offline-first (user, 2026-10-30): Drift row '
            '+ outbox op, server reads keep queued ops');

    expect(messageActionRequiresOnline(MessageAction.star), isFalse,
        reason: 'star writes is_starred locally first (P4 ruling 1) — fetch '
            'preserves the local flag');
    expect(messageActionRequiresOnline(MessageAction.deleteForMe), isFalse,
        reason: 'delete-for-me writes a local tombstone preserved by fetch');
    expect(messageActionRequiresOnline(MessageAction.reply), isFalse);
    expect(messageActionRequiresOnline(MessageAction.copy), isFalse);
  });

  test('offline gating: unwired actions disabled, durable-local actions enabled',
      () {
    for (final a in [
      MessageAction.pin,
      MessageAction.deleteForEveryone,
    ]) {
      expect(isMessageActionEnabled(a, isOnline: false), isFalse,
          reason: '$a must be disabled offline (defined behavior)');
      expect(isMessageActionEnabled(a, isOnline: true), isTrue,
          reason: '$a must be enabled online');
    }
    for (final a in [
      MessageAction.react,
      MessageAction.star,
      MessageAction.deleteForMe,
      MessageAction.reply,
      MessageAction.copy,
    ]) {
      expect(isMessageActionEnabled(a, isOnline: false), isTrue,
          reason: '$a has a durable local path — must stay usable offline');
    }
  });

  test('offline hint is the user-visible contract string', () {
    expect(kOfflineActionHint, 'Available online');
  });
}
