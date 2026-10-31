import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/friend_requests/providers/friend_request_provider.dart';

/// Bug wave 2 §7.1: copyWith's clearError used to beat the new message, so a
/// short code showed nothing at all.
void main() {
  test('a code that is not 6 characters says so', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(addFriendProvider.notifier).searchByCode('AB12');
    final state = container.read(addFriendProvider);
    expect(state.searchError, 'Friend code must be exactly 6 characters.');
    expect(state.foundUser, isNull);
    expect(state.isSearching, isFalse);
  });
}
