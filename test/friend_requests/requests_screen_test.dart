import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/domain/entities/friend_request.dart';
import 'package:kuch_bhi/domain/entities/group_invite.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/features/friend_requests/providers/friend_request_provider.dart';
import 'package:kuch_bhi/features/friend_requests/screens/friend_requests_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';

User _user({String name = 'Mira Joshi', String username = 'mira_j'}) => User(
  id: username,
  displayName: name,
  username: username,
  email: '$username@example.com',
  friendCode: 'ABC123',
  createdAt: DateTime(2026, 10, 20),
);

FriendRequest _request({String id = 'request-1', String name = 'Mira Joshi'}) =>
    FriendRequest(
      id: id,
      fromUser: _user(name: name),
      toUser: _user(name: 'Me', username: 'me'),
      status: 'pending',
      createdAt: DateTime(2026, 10, 20),
    );

GroupInvite _invite({
  String id = 'invite-1',
  String group = 'Weekend Trekkers',
  String inviter = 'Rohan',
}) => GroupInvite(
  id: id,
  conversationId: 'conversation-$id',
  conversationName: group,
  invitedBy: _user(name: inviter, username: 'inviter'),
  status: 'pending',
  createdAt: DateTime(2026, 10, 19),
);

class _RequestsNotifier extends IncomingRequestsNotifier {
  _RequestsNotifier({this.rows = const [], this.error, this.pending});

  final List<FriendRequest> rows;
  final Object? error;
  final Future<List<FriendRequest>>? pending;

  @override
  Future<List<FriendRequest>> build() async {
    if (pending != null) return pending!;
    if (error != null) throw error!;
    return rows;
  }
}

class _InvitesNotifier extends IncomingGroupInvitesNotifier {
  _InvitesNotifier({this.rows = const [], this.error, this.pending});

  final List<GroupInvite> rows;
  final Object? error;
  final Future<List<GroupInvite>>? pending;

  @override
  Future<List<GroupInvite>> build() async {
    if (pending != null) return pending!;
    if (error != null) throw error!;
    return rows;
  }
}

class _RefreshingRequestsNotifier extends IncomingRequestsNotifier {
  _RefreshingRequestsNotifier(this.rows, this.refreshResult);

  final List<FriendRequest> rows;
  final Future<List<FriendRequest>> refreshResult;
  var buildCount = 0;

  @override
  Future<List<FriendRequest>> build() {
    buildCount++;
    return buildCount == 1 ? Future.value(rows) : refreshResult;
  }
}

Widget _host({
  List<FriendRequest> requests = const [],
  List<GroupInvite> invites = const [],
  Object? requestsError,
  Object? invitesError,
  Future<List<FriendRequest>>? requestsPending,
  Future<List<GroupInvite>>? invitesPending,
  bool online = true,
}) => ProviderScope(
  overrides: [
    incomingRequestsProvider.overrideWith(
      () => _RequestsNotifier(
        rows: requests,
        error: requestsError,
        pending: requestsPending,
      ),
    ),
    incomingGroupInvitesProvider.overrideWith(
      () => _InvitesNotifier(
        rows: invites,
        error: invitesError,
        pending: invitesPending,
      ),
    ),
    isOnlineProvider.overrideWith((ref) => Stream.value(online)),
  ],
  child: MaterialApp(theme: warmPopLight(), home: const FriendRequestsScreen()),
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(child);
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('first load uses three card skeletons and no lone spinner', (
    tester,
  ) async {
    final requests = Completer<List<FriendRequest>>();
    final invites = Completer<List<GroupInvite>>();
    await _pump(
      tester,
      _host(requestsPending: requests.future, invitesPending: invites.future),
    );

    expect(find.byType(Skeleton), findsNWidgets(15));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    requests.complete(const []);
    invites.complete(const []);
  });

  testWidgets(
    'partial invite failure preserves friend cards and retry banner',
    (tester) async {
      await _pump(
        tester,
        _host(
          requests: [_request()],
          invitesError: StateError('invite backend unavailable'),
        ),
      );

      expect(find.text('Mira Joshi'), findsOneWidget);
      expect(find.text("Some requests didn't load."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining(r'$e'), findsNothing);
    },
  );

  testWidgets('full error uses stable copy and hides exception text', (
    tester,
  ) async {
    await _pump(
      tester,
      _host(
        requestsError: StateError('secret backend payload'),
        invitesError: StateError('secret invite payload'),
      ),
    );

    expect(find.text("Couldn't load requests."), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining(r'$e'), findsNothing);
  });

  testWidgets('empty state waits for both settled sources and carries CTA', (
    tester,
  ) async {
    await _pump(tester, _host());

    expect(find.text('No pending requests'), findsOneWidget);
    expect(
      find.text('Friend requests and group invites will show up here.'),
      findsOneWidget,
    );
    expect(find.text('Add a Friend'), findsOneWidget);
  });

  testWidgets('friends data plus invites loading never flashes empty state', (
    tester,
  ) async {
    final invites = Completer<List<GroupInvite>>();
    await _pump(
      tester,
      _host(requests: [_request()], invitesPending: invites.future),
    );

    expect(find.text('Mira Joshi'), findsOneWidget);
    expect(find.text('No pending requests'), findsNothing);
    expect(find.byType(Skeleton), findsWidgets);

    invites.complete(const []);
  });

  testWidgets('refresh keeps prior cards while the source refetches', (
    tester,
  ) async {
    final refresh = Completer<List<FriendRequest>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          incomingRequestsProvider.overrideWith(
            () => _RefreshingRequestsNotifier([_request()], refresh.future),
          ),
          incomingGroupInvitesProvider.overrideWith(_InvitesNotifier.new),
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
    expect(find.text('Mira Joshi'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(FriendRequestsScreen)),
      listen: false,
    );
    container.invalidate(incomingRequestsProvider);
    await tester.pump();

    expect(find.text('Mira Joshi'), findsOneWidget);
    expect(find.byType(Skeleton), findsNothing);

    refresh.complete([_request()]);
    await tester.pump();
  });

  testWidgets('friends empty plus invite data renders only invite section', (
    tester,
  ) async {
    await _pump(tester, _host(invites: [_invite()]));

    expect(find.text('Group invites'), findsOneWidget);
    expect(find.text('Weekend Trekkers'), findsOneWidget);
    expect(find.text('No pending requests'), findsNothing);
  });

  testWidgets('zero invites hides the group section header', (tester) async {
    await _pump(tester, _host(requests: [_request()]));

    expect(find.text('Mira Joshi'), findsOneWidget);
    expect(find.text('Group invites'), findsNothing);
  });

  testWidgets('offline strip dims each card once and disables actions', (
    tester,
  ) async {
    await _pump(
      tester,
      _host(requests: [_request()], invites: [_invite()], online: false),
    );

    expect(
      find.text("You're offline — actions are available when you're back."),
      findsOneWidget,
    );
    expect(find.text('Available online'), findsNWidgets(2));
    expect(find.byType(Opacity), findsNWidgets(2));
    expect(
      tester
          .widget<OutlinedButton>(find.byType(OutlinedButton).first)
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNull,
    );
  });

  testWidgets('hostile names use safe fallbacks and group glyph', (
    tester,
  ) async {
    await _pump(
      tester,
      _host(
        requests: [_request(name: '')],
        invites: [_invite(group: '', inviter: '')],
      ),
    );

    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Group'), findsOneWidget);
    expect(find.text('You were invited to join'), findsOneWidget);
    expect(find.byIcon(Icons.group), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
