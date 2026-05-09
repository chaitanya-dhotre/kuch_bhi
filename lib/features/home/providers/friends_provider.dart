import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../core/network/pocketbase_client.dart';
import '../../../domain/entities/friendship.dart';
import '../../../infrastructure/repositories/friend_repository_impl.dart';

class FriendshipsNotifier extends AsyncNotifier<List<Friendship>> {
  @override
  Future<List<Friendship>> build() async {
    final pb = ref.read(pocketbaseClientProvider).pb;

    if (pb != null) {
      // Subscribe to friendship changes — fires when a request is accepted
      // on any device, keeping both sides in sync.
      await pb.collection('friendships').subscribe('*', (_) => refresh());

      // Also watch incoming friend requests so the list updates when
      // the current user accepts a request.
      await pb.collection('friend_requests').subscribe('*', (_) => refresh());

      // Clean up subscriptions when provider is disposed.
      ref.onDispose(() {
        pb.collection('friendships').unsubscribe();
        pb.collection('friend_requests').unsubscribe();
      });
    }

    return ref.read(friendRepositoryProvider).getFriendships();
  }

  /// Call this to manually refresh — e.g. pull-to-refresh.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(
      await ref.read(friendRepositoryProvider).getFriendships(),
    );
  }
}

final friendshipsProvider =
    AsyncNotifierProvider<FriendshipsNotifier, List<Friendship>>(
  FriendshipsNotifier.new,
);
