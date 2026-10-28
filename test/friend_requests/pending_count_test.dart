import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/domain/entities/friend_request.dart';
import 'package:kuch_bhi/domain/entities/group_invite.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/features/friend_requests/providers/friend_request_provider.dart';

class _RequestsValueNotifier extends IncomingRequestsNotifier {
  _RequestsValueNotifier(this.value);

  final Future<List<FriendRequest>> value;

  @override
  Future<List<FriendRequest>> build() => value;
}

class _InvitesValueNotifier extends IncomingGroupInvitesNotifier {
  _InvitesValueNotifier(this.value);

  final Future<List<GroupInvite>> value;

  @override
  Future<List<GroupInvite>> build() => value;
}

void main() {
  test('pending count sums settled friend and invite data', () async {
    final container = ProviderContainer(
      overrides: [
        incomingRequestsProvider.overrideWith(
          () => _RequestsValueNotifier(Future.value(List.filled(3, _row()))),
        ),
        incomingGroupInvitesProvider.overrideWith(
          () => _InvitesValueNotifier(Future.value(List.filled(2, _invite()))),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(incomingRequestsProvider.future);
    await container.read(incomingGroupInvitesProvider.future);
    expect(container.read(pendingRequestCountProvider), 5);
  });

  test('pending count collapses loading and errors to zero', () async {
    final requests = Completer<List<FriendRequest>>();
    final invites = Completer<List<GroupInvite>>();
    final loadingContainer = ProviderContainer(
      overrides: [
        incomingRequestsProvider.overrideWith(
          () => _RequestsValueNotifier(requests.future),
        ),
        incomingGroupInvitesProvider.overrideWith(
          () => _InvitesValueNotifier(invites.future),
        ),
      ],
    );
    addTearDown(loadingContainer.dispose);

    expect(loadingContainer.read(pendingRequestCountProvider), 0);

    final errorContainer = ProviderContainer(
      overrides: [
        incomingRequestsProvider.overrideWith(
          () => _RequestsValueNotifier(Future.error(StateError('request'))),
        ),
        incomingGroupInvitesProvider.overrideWith(
          () => _InvitesValueNotifier(Future.error(StateError('invite'))),
        ),
      ],
    );
    addTearDown(errorContainer.dispose);

    await expectLater(
      errorContainer.read(incomingRequestsProvider.future),
      throwsStateError,
    );
    await expectLater(
      errorContainer.read(incomingGroupInvitesProvider.future),
      throwsStateError,
    );
    expect(errorContainer.read(pendingRequestCountProvider), 0);
  });
}

FriendRequest _row() => FriendRequest(
  id: 'r',
  fromUser: _user(),
  toUser: _user(),
  status: 'pending',
  createdAt: DateTime(2026, 10, 20),
);

GroupInvite _invite() => GroupInvite(
  id: 'i',
  conversationId: 'c',
  conversationName: 'Group',
  invitedBy: _user(),
  status: 'pending',
  createdAt: DateTime(2026, 10, 20),
);

User _user() => User(
  id: 'u',
  displayName: 'User',
  username: 'user',
  email: 'user@example.com',
  friendCode: 'ABC123',
  createdAt: DateTime(2026, 10, 20),
);
