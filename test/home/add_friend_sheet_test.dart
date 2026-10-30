import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/widgets/app_button.dart';
import 'package:kuch_bhi/core/widgets/app_toast.dart';
import 'package:kuch_bhi/domain/entities/friend_request.dart';
import 'package:kuch_bhi/domain/entities/friendship.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/friend_repository.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/home/providers/friends_provider.dart';
import 'package:kuch_bhi/features/home/screens/add_friend_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/friend_repository_impl.dart';

import '../core/sheet_harness.dart';

User _user(String id, String name, String username) => User(
      id: id,
      displayName: name,
      username: username,
      email: '$username@example.com',
      friendCode: 'MIRA42',
      createdAt: DateTime(2026, 1, 1),
    );

final _mira = _user('u_mira', 'Mira Joshi', 'mira');
final _me = _user('u_me', 'Chai', 'chai');

class _Friends extends FriendshipsNotifier {
  _Friends(this.friends);
  final List<Friendship> friends;

  @override
  Future<List<Friendship>> build() async => friends;
}

class _Repo implements FriendRepository {
  _Repo({this.found, this.search, this.send});

  final User? found;
  final Future<User?> Function()? search;
  final Future<FriendRequest> Function()? send;
  var sent = 0;

  @override
  Future<User?> findUserByCode(String code) => search?.call() ?? Future.value(found);

  @override
  Future<FriendRequest> sendRequest(String toUserId) async {
    sent++;
    if (send != null) return send!();
    return FriendRequest(
      id: 'fr1',
      fromUser: _me,
      toUser: found!,
      status: 'pending',
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _open(
  WidgetTester tester,
  _Repo repo, {
  Stream<bool>? online,
  List<Friendship> friends = const [],
  bool large = false,
  String? fontFamily,
}) async {
  await pumpHost(
    tester,
    SheetLauncher(showAddFriendSheet),
    overrides: [
      friendRepositoryProvider.overrideWithValue(repo),
      isOnlineProvider.overrideWith((ref) => online ?? Stream.value(true)),
      currentUserIdProvider.overrideWith((ref) async => 'u_me'),
      friendshipsProvider.overrideWith(() => _Friends(friends)),
    ],
    large: large,
    fontFamily: fontFamily,
  );
  await tapOpen(tester);
}

final _field = find.byType(TextField);
final _search = find.byKey(const Key('add-friend-search'));
final _sheet = find.byType(BottomSheet);

Future<void> _searchFor(WidgetTester tester, String code) async {
  await tester.enterText(_field, code);
  await tester.tap(_search);
  await tester.pump();
  await tester.pump();
}

void _expectNoColouredText(WidgetTester tester) {
  final t = tokens(tester);
  expectNoTextIn(tester, [t.accent, t.error, t.success], _sheet);
}

void main() {
  testWidgets('switching to Scan QR drops the keyboard', (tester) async {
    await _open(tester, _Repo());
    await tester.tap(_field);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.text('Scan QR'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('a QR tab toast shows above the sheet, not under it',
      (tester) async {
    await _open(tester, _Repo());
    await tester.tap(find.text('Scan QR'));
    await tester.pumpAndSettle();
    final gallery = find.byKey(const Key('add-friend-gallery'));
    showToast(tester.element(gallery), 'No QR code in that photo.',
        error: true);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: _sheet, matching: find.byType(SnackBar)),
      findsOneWidget,
      reason: "the root Scaffold's SnackBar is painted under the sheet",
    );
    expect(find.text('No QR code in that photo.'), findsOneWidget);
    // The overlay lets taps through to the gallery button.
    expect(tester.hitTestOnBinding(tester.getCenter(gallery)).path.any(
            (e) => e.target is RenderBox &&
                (e.target as RenderBox) ==
                    tester.renderObject(gallery)),
        isTrue);
  });

  testWidgets('title "Add a friend" is a header; tabs are sentence case',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _open(tester, _Repo());
    expect(tester.getSemantics(find.text('Add a friend')),
        isSemantics(isHeader: true));
    expect(find.text('Friend code'), findsWidgets);
    expect(find.text('Scan QR'), findsOneWidget);
    expect(tester.getSemantics(_search),
        isSemantics(
            label: 'Search',
            isButton: true,
            isEnabled: true,
            hasTapAction: true));
    _expectNoColouredText(tester);
    semantics.dispose();
  });

  testWidgets('search → found card + R3 primary; send → sent + Done pops',
      (tester) async {
    final repo = _Repo(found: _mira);
    await _open(tester, repo);
    await _searchFor(tester, 'mira42');
    await tester.pumpAndSettle();

    expect(find.text('Mira Joshi'), findsOneWidget);
    expect(find.text('@mira'), findsOneWidget);
    final send = find.ancestor(
        of: find.text('Send friend request'), matching: find.byType(AppButton));
    expect(tester.widget<AppButton>(send).variant, AppButtonVariant.primary);
    _expectNoColouredText(tester);

    await tester.tap(find.text('Send friend request'));
    await tester.pumpAndSettle();
    expect(repo.sent, 1);
    expect(find.text('Request sent to Mira Joshi.'), findsOneWidget);
    expect(find.text("They'll show up in your chats once they accept."),
        findsOneWidget);
    _expectNoColouredText(tester);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(_sheet, findsNothing);
  });

  testWidgets('send throws → fixed copy, no exception text', (tester) async {
    final repo = _Repo(
        found: _mira, send: () async => throw Exception('secret-boom'));
    await _open(tester, repo);
    await _searchFor(tester, 'MIRA42');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send friend request'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't send the request. Try again."), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining(r'$'), findsNothing);
    _expectNoColouredText(tester);
  });

  testWidgets('send never answers → the send copy after 8s', (tester) async {
    final repo = _Repo(
        found: _mira, send: () => Completer<FriendRequest>().future);
    await _open(tester, repo);
    await _searchFor(tester, 'MIRA42');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send friend request'));
    await tester.pump(const Duration(seconds: 7));
    expect(find.text("Couldn't send the request. Try again."), findsNothing);
    await tester.pump(const Duration(seconds: 1, milliseconds: 100));
    await tester.pump();
    expect(find.text("Couldn't send the request. Try again."), findsOneWidget);
  });

  testWidgets('search never answers → the search copy after 8s',
      (tester) async {
    final repo = _Repo(search: () => Completer<User?>().future);
    await _open(tester, repo);
    await _searchFor(tester, 'MIRA42');
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Search failed. Check your connection.'), findsNothing);
    await tester.pump(const Duration(seconds: 1, milliseconds: 100));
    await tester.pump();
    expect(find.text('Search failed. Check your connection.'), findsOneWidget);
  });

  testWidgets('offline: search + send dimmed once, one hint, field types',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final online = StreamController<bool>();
    addTearDown(online.close);
    online.add(true);
    final repo = _Repo(found: _mira);
    await _open(tester, repo, online: online.stream);
    await _searchFor(tester, 'MIRA42');
    await tester.pumpAndSettle();

    online.add(false);
    await tester.pump();
    await tester.pump();

    final searchDim =
        find.ancestor(of: _search, matching: find.byType(Opacity));
    expect(tester.widget<Opacity>(searchDim.first).opacity, 0.38);
    expect(tester.getSemantics(_search),
        isSemantics(
            label: 'Search', isEnabled: false, hasTapAction: false));
    final send = find.ancestor(
        of: find.text('Send friend request'), matching: find.byType(AppButton));
    expect(tester.widget<AppButton>(send).onPressed, isNull);
    expect(
        tester
            .widget<Opacity>(
                find.ancestor(of: send, matching: find.byType(Opacity)).first)
            .opacity,
        0.38);
    expect(find.descendant(of: _sheet, matching: find.text('Available online')),
        findsOneWidget);

    await tester.enterText(_field, 'ZZZZ99');
    await tester.pump();
    expect(find.text('ZZZZ99'), findsOneWidget, reason: 'the field still types');
    await tester.tap(_search, warnIfMissed: false);
    await tester.pump();
    expect(find.text('Mira Joshi'), findsOneWidget,
        reason: 'no search started offline');
    semantics.dispose();
  });

  testWidgets("decision 3: your own code / an existing friend → no button",
      (tester) async {
    await _open(tester, _Repo(found: _me));
    await _searchFor(tester, 'CHAI01');
    await tester.pumpAndSettle();
    expect(find.text("That's your code."), findsOneWidget);
    expect(find.text('Send friend request'), findsNothing);
  });

  testWidgets('decision 3: an existing friend → "You\'re already friends."',
      (tester) async {
    await _open(tester, _Repo(found: _mira), friends: [
      Friendship(id: 'f1', friend: _mira, createdAt: DateTime(2026, 1, 1)),
    ]);
    await _searchFor(tester, 'MIRA42');
    await tester.pumpAndSettle();
    expect(find.text("You're already friends."), findsOneWidget);
    expect(find.text('Send friend request'), findsNothing);
  });

  for (final font in largeTextFonts) {
    testWidgets('360×200% (${font ?? 'system'}): empty, found, sent',
        (tester) async {
      final repo = _Repo(found: _mira);
      await _open(tester, repo, large: true, fontFamily: font);
      expect(tester.takeException(), isNull, reason: 'empty');
      await _searchFor(tester, 'MIRA42');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'found');
      await tester.scrollUntilVisible(find.text('Send friend request'), 100,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('Send friend request'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'sent');
      expect(find.text('Done'), findsOneWidget);
    });
  }
}
