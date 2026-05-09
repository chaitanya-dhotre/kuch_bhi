import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/pocketbase_client.dart';
import '../../../domain/entities/friend_request.dart';
import '../../../domain/entities/user.dart';
import '../../../infrastructure/repositories/friend_repository_impl.dart';

/// Watches incoming friend requests with proper subscription lifecycle.
class IncomingRequestsNotifier
    extends AsyncNotifier<List<FriendRequest>> {
  @override
  Future<List<FriendRequest>> build() async {
    final pb = ref.read(pocketbaseClientProvider).pb;

    if (pb != null) {
      await pb.collection('friend_requests').subscribe('*', (_) => _refresh());
      ref.onDispose(() => pb.collection('friend_requests').unsubscribe());
    }

    return ref.read(friendRepositoryProvider).getIncomingRequests();
  }

  Future<void> _refresh() async {
    state = AsyncData(
      await ref.read(friendRepositoryProvider).getIncomingRequests(),
    );
  }
}

final incomingRequestsProvider =
    AsyncNotifierProvider<IncomingRequestsNotifier, List<FriendRequest>>(
  IncomingRequestsNotifier.new,
);

/// Badge count for the home screen icon.
final pendingRequestCountProvider = Provider<int>((ref) {
  return ref.watch(incomingRequestsProvider).when(
        data: (list) => list.length,
        loading: () => 0,
        error: (_, __) => 0,
      );
});

// ── Add Friend State ───────────────────────────────────────────────────────

class AddFriendState {
  const AddFriendState({
    this.foundUser,
    this.isSearching = false,
    this.searchError,
    this.requestSent = false,
    this.isSendingRequest = false,
  });

  final User? foundUser;
  final bool isSearching;
  final String? searchError;
  final bool requestSent;
  final bool isSendingRequest;

  AddFriendState copyWith({
    User? foundUser,
    bool? isSearching,
    String? searchError,
    bool? requestSent,
    bool? isSendingRequest,
    bool clearUser = false,
    bool clearError = false,
  }) =>
      AddFriendState(
        foundUser:        clearUser  ? null : foundUser  ?? this.foundUser,
        isSearching:      isSearching      ?? this.isSearching,
        searchError:      clearError ? null : searchError ?? this.searchError,
        requestSent:      requestSent      ?? this.requestSent,
        isSendingRequest: isSendingRequest ?? this.isSendingRequest,
      );
}

class AddFriendNotifier extends Notifier<AddFriendState> {
  @override
  AddFriendState build() => const AddFriendState();

  Future<void> searchByCode(String code) async {
    if (code.trim().length != 6) {
      state = state.copyWith(
        clearUser: true,
        clearError: true,
        searchError: 'Friend code must be exactly 6 characters.',
      );
      return;
    }

    state = state.copyWith(isSearching: true, clearUser: true, clearError: true);

    try {
      final user = await ref
          .read(friendRepositoryProvider)
          .findUserByCode(code.trim().toUpperCase());

      state = user == null
          ? state.copyWith(isSearching: false, searchError: 'No user found.')
          : state.copyWith(isSearching: false, foundUser: user);
    } catch (e) {
      state = state.copyWith(
        isSearching: false,
        searchError: 'Search failed. Check your connection.',
      );
    }
  }

  Future<void> sendRequest() async {
    final user = state.foundUser;
    if (user == null) return;

    state = state.copyWith(isSendingRequest: true);

    try {
      await ref.read(friendRepositoryProvider).sendRequest(user.id);
      state = state.copyWith(isSendingRequest: false, requestSent: true);
    } catch (e) {
      debugPrint('Send request error: $e');
      state = state.copyWith(
        isSendingRequest: false,
        searchError: 'Failed to send request: $e',
      );
    }
  }

  void reset() => state = const AddFriendState();
}

final addFriendProvider =
    NotifierProvider<AddFriendNotifier, AddFriendState>(AddFriendNotifier.new);
