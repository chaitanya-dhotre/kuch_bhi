import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/friendship.dart';
import '../../../infrastructure/services/friend_query_service.dart';
import '../../../infrastructure/repositories/friend_repository_impl.dart';

class FriendshipsNotifier extends AsyncNotifier<List<Friendship>> {
  @override
  Future<List<Friendship>> build() async {
    final queries = ref.read(friendQueryServiceProvider);

    await queries.subscribeToFriendChanges(refresh, ref.onDispose);

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
