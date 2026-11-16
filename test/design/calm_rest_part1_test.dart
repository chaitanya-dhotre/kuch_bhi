// Calm-rest spec, part 1 test gates 1–6 (gate 7 = the widened L8 gate in
// test/core/motion_tokens_test.dart).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/core/widgets/app_avatar.dart';
import 'package:kuch_bhi/core/widgets/app_button.dart';
import 'package:kuch_bhi/core/widgets/busy_spinner.dart';
import 'package:kuch_bhi/core/widgets/chat_tile.dart';
import 'package:kuch_bhi/core/widgets/skeleton.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/friendship.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/features/auth/providers/auth_provider.dart';
import 'package:kuch_bhi/features/friend_requests/providers/friend_request_provider.dart';
import 'package:kuch_bhi/features/home/providers/conversations_provider.dart';
import 'package:kuch_bhi/features/home/providers/friends_provider.dart';
import 'package:kuch_bhi/features/home/screens/home_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/encryption_service.dart';

import '../fakes/fake_message_repository.dart';

final _themes = {
  'light': warmPopLight(),
  'dark': warmPopDark(),
  'amoled': warmPopDark(amoled: true),
};

ColorTokens _tokens(ThemeData theme) => theme.extension<ColorTokens>()!;

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Widget _host(ThemeData theme, Widget child, {bool reduced = false}) =>
    MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: Center(child: child)),
      ),
    );

/// Every colour a widget paints directly: text, icon, box fill and border.
Iterable<Color> _paints(Widget w) sync* {
  if (w is Text && w.style?.color != null) yield w.style!.color!;
  if (w is Icon && w.color != null) yield w.color!;
  if (w is Material && w.color != null) yield w.color!;
  if (w is Container && w.decoration is BoxDecoration) {
    final d = w.decoration! as BoxDecoration;
    if (d.color != null) yield d.color!;
    final b = d.border;
    if (b is Border) yield b.top.color;
  }
}

class _Enc implements EncryptionService {
  @override
  Future<bool> hasLocalPrivateKey() async => true;
  @override
  Future<BackupKind?> tryGetBackupKind(String userId) async =>
      BackupKind.current;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Auth extends AuthNotifier {
  @override
  Future<AuthState> build() async => AuthAuthenticated(
    User(
      id: 'u_test',
      displayName: 'Test',
      username: 'test',
      email: 'test@example.com',
      friendCode: 'FRIEND1',
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  );
}

class _NoFriends extends FriendshipsNotifier {
  @override
  Future<List<Friendship>> build() async => const [];
}

Future<void> _home(
  WidgetTester tester,
  Stream<List<Conversation>> conversations, {
  bool reduced = false,
}) async {
  final db = AppDatabase.test();
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        encryptionServiceProvider.overrideWithValue(_Enc()),
        authProvider.overrideWith(_Auth.new),
        appDatabaseProvider.overrideWithValue(db),
        messageRepositoryProvider.overrideWithValue(FakeMessageRepository()),
        friendshipsProvider.overrideWith(_NoFriends.new),
        pendingRequestCountProvider.overrideWithValue(0),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        conversationsProvider.overrideWith((ref) => conversations),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(411, 860),
            disableAnimations: reduced,
          ),
          child: const HomeScreen(),
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Drops Home so its Drift streams close inside the test's clock.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 10));
}

final _groups = [
  for (var i = 0; i < 30; i++)
    Conversation(id: 'g$i', type: 'group', name: 'Group $i', unreadCount: 2),
];

void main() {
  group('gate 1: avatar placeholder (A2)', () {
    for (final e in _themes.entries) {
      testWidgets('${e.key}: surface2 fill, 1 dp line ring', (tester) async {
        final t = _tokens(e.value);
        await tester.pumpWidget(_host(e.value, const AppAvatar(initials: 'A')));
        final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
        expect(avatar.backgroundColor, t.surface2);
        expect(tester.widget<Text>(find.text('A')).style!.color, t.inkSoft);
        final ring = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.byType(CircleAvatar),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final border = (ring.decoration as BoxDecoration).border! as Border;
        expect(border.top.color, t.line);
        expect(border.top.width, 1);
      });
    }

    test('no caller passes accentSoft to an avatar', () {
      final hits = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => f.readAsStringSync().contains('accentSoft: true'))
          .map((f) => f.path);
      expect(hits, isEmpty);
    });
  });

  test('gate 2: AMOLED surface2 differs from surface, initials pass 4.5:1', () {
    final t = _tokens(warmPopDark(amoled: true));
    expect(t.surface2, isNot(t.surface));
    expect(t.surface2, WarmPopTokens.bgDark);
    for (final theme in _themes.values) {
      final c = _tokens(theme);
      expect(_contrast(c.inkSoft, c.surface2), greaterThanOrEqualTo(4.5));
    }
  });

  group('gate 3: AppButton (A3)', () {
    for (final e in {'light': warmPopLight(), 'dark': warmPopDark()}.entries) {
      testWidgets('${e.key}: tonal = bubbleMine fill, ink label', (
        tester,
      ) async {
        final t = _tokens(e.value);
        await tester.pumpWidget(
          _host(
            e.value,
            AppButton(
              onPressed: () {},
              variant: AppButtonVariant.tonal,
              child: const Text('Accept'),
            ),
          ),
        );
        final style = tester
            .widget<FilledButton>(find.byType(FilledButton))
            .style!;
        expect(style.backgroundColor!.resolve({}), t.bubbleMine);
        expect(style.foregroundColor!.resolve({}), t.ink);
      });
    }

    for (final v in AppButtonVariant.values) {
      testWidgets('${v.name}: label w600, busy ring is a BusySpinner', (
        tester,
      ) async {
        await tester.pumpWidget(
          _host(
            warmPopLight(),
            AppButton(onPressed: () {}, variant: v, child: const Text('Go')),
          ),
        );
        final button = tester.widget<ButtonStyleButton>(
          find.byWidgetPredicate((w) => w is ButtonStyleButton),
        );
        expect(
          button.style!.textStyle!.resolve({})!.fontWeight,
          FontWeight.w600,
        );

        await tester.pumpWidget(
          _host(
            warmPopLight(),
            AppButton(
              onPressed: () {},
              variant: v,
              busy: true,
              child: const Text('Go'),
            ),
          ),
        );
        final spinner = tester.widget<BusySpinner>(find.byType(BusySpinner));
        final t = ColorTokens.light;
        expect(
          spinner.color,
          v == AppButtonVariant.primary ? t.onAccent : t.ink,
        );
      });
    }
  });

  testWidgets('gate 4: an unread Home row paints accent once (the badge)', (
    tester,
  ) async {
    for (final theme in _themes.values) {
      final t = _tokens(theme);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _host(
          theme,
          const SizedBox(
            width: 380,
            child: ChatTile(
              title: 'Ada',
              subtitle: 'hi',
              time: '12:00',
              unreadCount: 3,
              isGroup: true,
            ),
          ),
        ),
      );
      final accent = tester.allWidgets
          .expand(_paints)
          .where((c) => c == t.accent || c == t.accentText);
      expect(accent.length, 1);
      final time = tester.widget<Text>(find.text('12:00'));
      expect(time.style!.color, t.ink);
      expect(time.style!.fontWeight, FontWeight.w600);
    }
  });

  group('gate 5: the new-chat button hides on scroll (B2)', () {
    for (final reduced in [false, true]) {
      testWidgets(reduced ? 'reduced motion' : 'animated', (tester) async {
        await _home(tester, Stream.value(_groups), reduced: reduced);
        double opacity() => tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.byType(FloatingActionButton),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity;
        Duration duration() => tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.byType(FloatingActionButton),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .duration;
        expect(opacity(), 1);

        await tester.drag(find.byType(ListView), const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(opacity(), 0);
        expect(duration(), reduced ? Duration.zero : WarmPopTokens.motionPress);

        await tester.drag(find.byType(ListView), const Offset(0, 100));
        await tester.pumpAndSettle();
        expect(opacity(), 1);
        expect(duration(), reduced ? Duration.zero : WarmPopTokens.motionFast);
        await _unmount(tester);
      });
    }

    testWidgets('the list keeps 88 dp under its last row', (tester) async {
      await _home(tester, Stream.value(_groups));
      final list = tester.widget<ListView>(find.byType(ListView));
      expect((list.padding! as EdgeInsets).bottom, 88);
      await _unmount(tester);
    });
  });

  testWidgets('gate 6: Home placeholders breathe on one clock', (tester) async {
    final before = SkeletonGroup.debugLiveControllers;
    final pending = StreamController<List<Conversation>>();
    addTearDown(pending.close);
    await _home(tester, pending.stream);
    expect(find.byType(Skeleton), findsWidgets);
    expect(SkeletonGroup.debugLiveControllers - before, 1);
    for (final s in tester.widgetList<Skeleton>(find.byType(Skeleton))) {
      expect(s.duration, kSkeletonBreath);
    }
    await _unmount(tester);
  });
}
