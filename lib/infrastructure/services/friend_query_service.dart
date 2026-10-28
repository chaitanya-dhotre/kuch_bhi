import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/pocketbase_client.dart';
import '../../core/network/realtime_subscribe.dart';

/// Friendship SSE subscriptions.
///
/// Logic moved verbatim from `friends_provider.dart` (Task 10, guard 5:
/// structure move, no behavior edits).
class FriendQueryService {
  FriendQueryService(this._client);

  final PocketBaseClient _client;

  Future<void> subscribeToFriendChanges(
    void Function() onChange,
    void Function(void Function() callback) registerDispose, {
    bool Function()? isAbandoned,
  }) async {
    final pb = _client.pb;

    // Subscribe to friendship changes — fires when a request is accepted
    // on any device, keeping both sides in sync.
    //
    // R1 fix: the helper removes ONLY its own listener, never the topic-less
    // `collection.unsubscribe()` — that form maps to
    // realtime.unsubscribeByPrefix, which removes EVERY listener on
    // `friend_requests/*`, including the Requests page's own notifier
    // listener (and vice-versa): one page's dispose silently killed the
    // other side's live updates.
    //
    // The helper also bounds the handshake: PocketBase's SSE client retries
    // forever, so an offline cold start would hang this await.
    await subscribeWithTimeout(
      pb,
      'friendships',
      onChange,
      registerDispose,
      isAbandoned: isAbandoned,
    );

    // Also watch incoming friend requests so the list updates when
    // the current user accepts a request.
    await subscribeWithTimeout(
      pb,
      'friend_requests',
      onChange,
      registerDispose,
      isAbandoned: isAbandoned,
    );
  }
}

final friendQueryServiceProvider = Provider<FriendQueryService>((ref) {
  return FriendQueryService(ref.watch(pocketbaseClientProvider));
});
