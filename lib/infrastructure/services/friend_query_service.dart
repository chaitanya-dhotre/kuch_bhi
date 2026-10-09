import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/pocketbase_client.dart';

/// Friendship SSE subscriptions.
///
/// Logic moved verbatim from `friends_provider.dart` (Task 10, guard 5:
/// structure move, no behavior edits).
class FriendQueryService {
  FriendQueryService(this._client);

  final PocketBaseClient _client;

  Future<void> subscribeToFriendChanges(
    void Function() onChange,
    void Function(void Function() callback) registerDispose,
  ) async {
    final pb = _client.pb;

    if (pb != null) {
      // Subscribe to friendship changes — fires when a request is accepted
      // on any device, keeping both sides in sync.
      await pb.collection('friendships').subscribe('*', (_) => onChange());

      // Also watch incoming friend requests so the list updates when
      // the current user accepts a request.
      await pb.collection('friend_requests').subscribe('*', (_) => onChange());

      // Clean up subscriptions when provider is disposed.
      registerDispose(() {
        pb.collection('friendships').unsubscribe();
        pb.collection('friend_requests').unsubscribe();
      });
    }
  }
}

final friendQueryServiceProvider = Provider<FriendQueryService>((ref) {
  return FriendQueryService(ref.watch(pocketbaseClientProvider));
});
