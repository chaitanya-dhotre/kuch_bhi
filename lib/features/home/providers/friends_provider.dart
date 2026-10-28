import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/friendship.dart';
import '../../../infrastructure/services/friend_query_service.dart';
import '../../../infrastructure/repositories/friend_repository_impl.dart';

class FriendshipsNotifier extends AsyncNotifier<List<Friendship>> {
  /// Bumped on every build.
  ///
  /// Riverpod REUSES a notifier instance across `invalidateSelf`, so a plain
  /// `bool _disposed` would stay `true` after the first rebuild — and the
  /// subscribe helper would then drop a listener that belongs to a LIVE
  /// provider. A generation counter gives each build its own identity.
  int _generation = 0;

  @override
  Future<List<Friendship>> build() async {
    final generation = ++_generation;
    final queries = ref.read(friendQueryServiceProvider);

    // The realtime subscribe is NOT awaited before the data load: the
    // handshake is bounded, but awaiting it would hold the home screen's
    // skeleton for the whole timeout on a cold start with no network.
    unawaited(
      queries.subscribeToFriendChanges(
        refresh,
        ref.onDispose,
        isAbandoned: () => generation != _generation,
      ),
    );

    // The fetch is bounded too: PocketBase's HTTP client has no request
    // timeout, so a blackholed socket would hold the home skeleton forever.
    return ref
        .read(friendRepositoryProvider)
        .getFriendships()
        .timeout(_friendshipsFetchTimeout);
  }

  /// Call this to manually refresh — e.g. pull-to-refresh.
  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      state = AsyncData(
        await ref
            .read(friendRepositoryProvider)
            .getFriendships()
            .timeout(_friendshipsFetchTimeout),
      );
    } catch (_) {
      // A failed refresh keeps the previous list; the home screen shows its
      // own error state for a failed BUILD.
      state = AsyncError(
        _FriendshipsFetchFailed(),
        StackTrace.current,
      );
    }
  }
}

/// How long the friendships fetch may take before the home screen gives up.
///
/// PocketBase's HTTP client has NO request timeout — a blackholed socket
/// (the "wifi up but no internet" case) never completes, so the home screen
/// would sit on its skeleton indefinitely.
const _friendshipsFetchTimeout = Duration(seconds: 8);

/// Marker for a failed friendships fetch (no user-facing text — the home
/// screen renders its own error state).
class _FriendshipsFetchFailed implements Exception {
  const _FriendshipsFetchFailed();

  @override
  String toString() => 'Friendships fetch failed';
}

final friendshipsProvider =
    AsyncNotifierProvider<FriendshipsNotifier, List<Friendship>>(
  FriendshipsNotifier.new,
);
