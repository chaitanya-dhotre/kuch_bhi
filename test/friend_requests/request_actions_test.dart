import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/entities/friend_request.dart';
import 'package:kuch_bhi/domain/entities/group_invite.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/friend_repository.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/friend_requests/providers/friend_request_provider.dart';
import 'package:kuch_bhi/features/friend_requests/screens/friend_requests_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/friend_repository_impl.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

User _user({String name = 'Mira Joshi', String username = 'mira_j'}) => User(
  id: username,
  displayName: name,
  username: username,
  email: '$username@example.com',
  friendCode: 'ABC123',
  createdAt: DateTime(2026, 10, 20),
);

FriendRequest _request() => FriendRequest(
  id: 'request-1',
  fromUser: _user(),
  toUser: _user(name: 'Me', username: 'me'),
  status: 'pending',
  createdAt: DateTime(2026, 10, 20),
);

GroupInvite _invite() => GroupInvite(
  id: 'invite-1',
  conversationId: 'conversation-1',
  conversationName: 'Weekend Trekkers',
  invitedBy: _user(name: 'Rohan', username: 'rohan'),
  status: 'pending',
  createdAt: DateTime(2026, 10, 19),
);

class _FriendRepo implements FriendRepository {
  int accepts = 0;
  int declines = 0;
  Object? acceptError;
  Object? declineError;

  @override
  Future<void> acceptRequest(String requestId) async {
    accepts++;
    if (acceptError != null) throw acceptError!;
  }

  @override
  Future<void> declineRequest(String requestId) async {
    declines++;
    if (declineError != null) throw declineError!;
  }

  @override
  Future<List<FriendRequest>> getIncomingRequests() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'FriendRepository.${invocation.memberName} not stubbed',
  );
}

class _MessageRepo implements MessageRepository {
  int accepts = 0;
  int declines = 0;
  Object? acceptError;
  Object? declineError;

  @override
  Future<void> acceptGroupInvite(String inviteId) async {
    accepts++;
    if (acceptError != null) throw acceptError!;
  }

  @override
  Future<void> declineGroupInvite(String inviteId) async {
    declines++;
    if (declineError != null) throw declineError!;
  }

  @override
  Future<List<GroupInvite>> getIncomingGroupInvites() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'MessageRepository.${invocation.memberName} not stubbed',
  );
}

class _ActionRequestsNotifier extends IncomingRequestsNotifier {
  _ActionRequestsNotifier({required this.row});

  final FriendRequest row;
  Future<void> Function(String id)? acceptCallback;
  Future<void> Function(String id)? declineCallback;

  @override
  Future<List<FriendRequest>> build() async => [row];

  @override
  Future<void> accept(String id) =>
      acceptCallback?.call(id) ?? super.accept(id);

  @override
  Future<void> decline(String id) =>
      declineCallback?.call(id) ?? super.decline(id);
}

class _EmptyInvitesNotifier extends IncomingGroupInvitesNotifier {
  @override
  Future<List<GroupInvite>> build() async => const [];
}

class _ActionInvitesNotifier extends IncomingGroupInvitesNotifier {
  _ActionInvitesNotifier({required this.row});

  final GroupInvite row;
  Future<void> Function(String id)? acceptCallback;
  Future<void> Function(String id)? declineCallback;

  @override
  Future<List<GroupInvite>> build() async => [row];

  @override
  Future<void> accept(String id) =>
      acceptCallback?.call(id) ?? super.accept(id);

  @override
  Future<void> decline(String id) =>
      declineCallback?.call(id) ?? super.decline(id);
}

void main() {
  group('notifier mutations', () {
    test(
      'friend accept and decline call repositories and propagate failures',
      () async {
        final repo = _FriendRepo();
        // The notifier methods are exercised through a live provider override so
        // ref.invalidate targets are available without constructing PocketBase.
        final actionContainer = ProviderContainer(
          overrides: [
            friendRepositoryProvider.overrideWithValue(repo),
            incomingRequestsProvider.overrideWith(_TestRequestsNotifier.new),
          ],
        );
        addTearDown(actionContainer.dispose);

        await actionContainer
            .read(incomingRequestsProvider.notifier)
            .accept('r1');
        await actionContainer
            .read(incomingRequestsProvider.notifier)
            .decline('r2');
        expect(repo.accepts, 1);
        expect(repo.declines, 1);

        repo.acceptError = StateError('accept failed');
        await expectLater(
          actionContainer.read(incomingRequestsProvider.notifier).accept('r3'),
          throwsStateError,
        );
      },
    );

    test(
      'group accept and decline call repositories and propagate failures',
      () async {
        final repo = _MessageRepo();
        final container = ProviderContainer(
          overrides: [
            messageRepositoryProvider.overrideWithValue(repo),
            incomingGroupInvitesProvider.overrideWith(_TestInvitesNotifier.new),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(incomingGroupInvitesProvider.notifier)
            .accept('invite-1');
        await container
            .read(incomingGroupInvitesProvider.notifier)
            .decline('invite-2');
        expect(repo.accepts, 1);
        expect(repo.declines, 1);

        repo.declineError = StateError('decline failed');
        await expectLater(
          container
              .read(incomingGroupInvitesProvider.notifier)
              .decline('invite-3'),
          throwsStateError,
        );
      },
    );
  });

  testWidgets('second accept tap is ignored while the first action is busy', (
    tester,
  ) async {
    final pending = Completer<void>();
    late _ActionRequestsNotifier notifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomingRequestsProvider.overrideWith(() {
            notifier = _ActionRequestsNotifier(row: _request())
              ..acceptCallback = (_) => pending.future;
            return notifier;
          }),
          incomingGroupInvitesProvider.overrideWith(_EmptyInvitesNotifier.new),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const FriendRequestsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.byType(FilledButton).first);
    expect(notifier, isNotNull);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete();
    await tester.pump();
    await tester.pump();
    // Calm-rest D2: the card leaves over motionExit.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Mira Joshi'), findsNothing);
  });

  testWidgets('a handled row is announced to the live region', (tester) async {
    // K3 / I3: the removal is announced ("{name} removed"). The
    // announcement goes through SemanticsService, whose platform channel is
    // captured by the test binding.
    final announcements = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/accessibility',
      (message) async {
        // The accessibility channel is a BasicMessageChannel with the
        // standard codec — the payload arrives encoded.
        final codec = const StandardMessageCodec();
        final decoded = message is ByteData
            ? codec.decodeMessage(message)
            : message;
        final args = (decoded as Map?) ?? {};
        if (args['type'] == 'announce') {
          final data = (args['data'] as Map?) ?? {};
          announcements.add('${data['message']}');
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/accessibility',
        null,
      );
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomingRequestsProvider.overrideWith(
            () =>
                _ActionRequestsNotifier(row: _request())
                  ..acceptCallback = (_) async {},
          ),
          incomingGroupInvitesProvider.overrideWith(_EmptyInvitesNotifier.new),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const FriendRequestsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    await tester.pump();

    expect(
      announcements.any((a) => a.contains('Mira Joshi') && a.contains('removed')),
      isTrue,
      reason: 'the removal must be announced as "{name} removed"; got '
          '$announcements',
    );
  });

  testWidgets('an empty displayName renders the fallback initial without '
      'crashing', (tester) async {
    // C2 regression: the card used to take `displayName.substring(0, 1)`,
    // which throws a RangeError on an empty name.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomingRequestsProvider.overrideWith(
            () => _ActionRequestsNotifier(
              row: FriendRequest(
                id: 'request-empty',
                fromUser: _user(name: ''),
                toUser: _user(name: 'Me', username: 'me'),
                status: 'pending',
                createdAt: DateTime(2026, 10, 20),
              ),
            ),
          ),
          incomingGroupInvitesProvider.overrideWith(_EmptyInvitesNotifier.new),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const FriendRequestsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // No crash, and the fallback name is shown.
    expect(tester.takeException(), isNull);
    expect(find.text('Unknown'), findsOneWidget);
  });

  testWidgets('failed action shows stable error toast and unlocks the card', (
    tester,
  ) async {
    late _ActionRequestsNotifier notifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomingRequestsProvider.overrideWith(() {
            notifier = _ActionRequestsNotifier(row: _request())
              ..acceptCallback = (_) async => throw StateError('secret');
            return notifier;
          }),
          incomingGroupInvitesProvider.overrideWith(_EmptyInvitesNotifier.new),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const FriendRequestsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't update. Try again."), findsOneWidget);
    expect(find.text('secret'), findsNothing);
    expect(find.text('Mira Joshi'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('friend accept exits with success toast', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomingRequestsProvider.overrideWith(
            () =>
                _ActionRequestsNotifier(row: _request())
                  ..acceptCallback = (_) async {},
          ),
          incomingGroupInvitesProvider.overrideWith(_EmptyInvitesNotifier.new),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const FriendRequestsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    await tester.pump();

    expect(find.text('Friend added'), findsOneWidget);
    // Calm-rest D2: the card leaves over motionExit.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Mira Joshi'), findsNothing);
  });

  testWidgets('group invite accept exits with joined toast', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomingRequestsProvider.overrideWith(_TestRequestsNotifier.new),
          incomingGroupInvitesProvider.overrideWith(
            () =>
                _ActionInvitesNotifier(row: _invite())
                  ..acceptCallback = (_) async {},
          ),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const FriendRequestsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    await tester.pump();

    expect(find.text('Joined Weekend Trekkers'), findsOneWidget);
    // Calm-rest D2: the card leaves over motionExit.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Weekend Trekkers'), findsNothing);
  });

  testWidgets('friend decline failure uses the stable error toast', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomingRequestsProvider.overrideWith(() {
            return _ActionRequestsNotifier(row: _request())
              ..declineCallback = (_) async => throw StateError('secret');
          }),
          incomingGroupInvitesProvider.overrideWith(_EmptyInvitesNotifier.new),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const FriendRequestsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(OutlinedButton).first);
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't update. Try again."), findsOneWidget);
    expect(find.text('secret'), findsNothing);
    expect(find.text('Mira Joshi'), findsOneWidget);
  });

  testWidgets('group decline failure uses the stable error toast', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomingRequestsProvider.overrideWith(_TestRequestsNotifier.new),
          incomingGroupInvitesProvider.overrideWith(() {
            return _ActionInvitesNotifier(row: _invite())
              ..declineCallback = (_) async => throw StateError('secret');
          }),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          theme: warmPopLight(),
          home: const FriendRequestsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byType(OutlinedButton).first);
    await tester.pump();
    await tester.pump();

    expect(find.text("Couldn't update. Try again."), findsOneWidget);
    expect(find.text('secret'), findsNothing);
    expect(find.text('Weekend Trekkers'), findsOneWidget);
  });
}

class _TestRequestsNotifier extends IncomingRequestsNotifier {
  @override
  Future<List<FriendRequest>> build() async => const [];
}

class _TestInvitesNotifier extends IncomingGroupInvitesNotifier {
  @override
  Future<List<GroupInvite>> build() async => const [];
}
