/// P4 (user ruling 2, visible half): the long-press menu renders unwired
/// actions DISABLED with the "Available online" hint when offline — never a
/// silent no-op. Star / delete-for-me / reply / copy stay enabled.
///
/// Wires the real [_ContextSheet] (via [showMessageMenu]) against:
/// - FakeMessageRepository (any repo call on a gated action would either
///   record or throw — the disabled path must reach neither)
/// - isOnlineProvider → Stream.value(false|true)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/widgets/message_context_menu.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

Message _msg({bool isMine = true, String? decryptedBody = 'hello'}) => Message(
  localId: 'loc1',
  serverId: 'srv1',
  conversationId: 'g1',
  senderId: isMine ? 'u_test' : 'u_other',
  type: 'text',
  decryptedBody: decryptedBody,
  status: 'sent',
  createdAt: DateTime.utc(2026, 1, 1),
);

class _MenuLauncher extends ConsumerWidget {
  const _MenuLauncher({this.message});

  final Message? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: ElevatedButton(
        key: const Key('open-menu'),
        onPressed: () => showMessageMenu(
          context: context,
          ref: ref,
          message: message ?? _msg(),
          isMine: true,
          senderName: 'Ada',
          onSelect: () {},
        ),
        child: const Text('open'),
      ),
    ),
  );
}

Future<void> _openMenu(
  WidgetTester tester, {
  required bool online,
  Size size = const Size(1080, 2400),
  Message? message,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        messageRepositoryProvider.overrideWithValue(FakeMessageRepository()),
        isOnlineProvider.overrideWith((ref) => Stream<bool>.value(online)),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: _MenuLauncher(message: message),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-menu')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('offline menu: pin + delete-for-everyone disabled with hint; '
      'reactions greyed; star/delete-for-me/reply/copy enabled', (
    tester,
  ) async {
    await _openMenu(tester, online: false);

    // Pin / delete-for-everyone: present, disabled, hint visible.
    final pinTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Pin'), matching: find.byType(ListTile)),
    );
    expect(
      pinTile.enabled,
      isFalse,
      reason: 'pin is unwired offline — tile must be disabled',
    );
    expect(pinTile.onTap, isNull);
    expect(pinTile.trailing, isA<Text>());
    expect((pinTile.trailing as Text).data, 'Available online');
    expect(
      find.text('Available online'),
      findsWidgets,
      reason: 'disabled tiles carry the hint',
    );

    final delAllTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Delete for everyone'),
        matching: find.byType(ListTile),
      ),
    );
    expect(
      delAllTile.enabled,
      isFalse,
      reason: 'delete-for-everyone is server-first — disabled offline',
    );

    // Star / delete-for-me / reply stay enabled (durable local paths).
    for (final label in ['Star', 'Delete for me', 'Reply']) {
      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
      );
      expect(tile.enabled, isTrue, reason: '$label has a local path offline');
      expect(tile.onTap, isNotNull);
    }

    final selectTile = tester.widget<ListTile>(
      find.byKey(const Key('message-menu-select')),
    );
    expect(selectTile.title, isA<Text>());
    expect((selectTile.title as Text).data, 'Select');
    expect(selectTile.onTap, isNotNull);

    expect(find.byKey(const Key('message-menu-preview')), findsOneWidget);
    expect(
      find.byKey(const Key('message-menu-preview-sender')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('message-menu-preview-body')), findsOneWidget);

    // Reaction row greyed (opacity < 1) — network-only.
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('👍'), matching: find.byType(Opacity)),
    );
    expect(
      opacity.opacity,
      lessThan(1.0),
      reason: 'reaction row visibly disabled offline',
    );
    expect(
      find.text('Available online'),
      findsWidgets,
      reason: 'reaction row carries the same offline hint',
    );
  });

  testWidgets('online menu: pin + delete-for-everyone enabled, hint gone', (
    tester,
  ) async {
    await _openMenu(tester, online: true);

    final pinTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Pin'), matching: find.byType(ListTile)),
    );
    expect(pinTile.enabled, isTrue);
    expect(pinTile.onTap, isNotNull);
    expect(pinTile.trailing, isNull);
    expect(find.text('Available online'), findsNothing);
  });

  testWidgets(
    'copy follows the live body cache, not legacy message plaintext',
    (tester) async {
      addTearDown(bodyCache.clear);
      bodyCache.put('loc1', 'cached body');

      await _openMenu(tester, online: true, message: _msg(decryptedBody: null));

      expect(find.text('Copy'), findsOneWidget);
      expect(find.byKey(const Key('message-menu-copy')), findsOneWidget);
    },
  );

  testWidgets(
    'offline disabled action is not wrapped in a second opacity layer',
    (tester) async {
      await _openMenu(tester, online: false);

      final pin = find.byKey(const Key('message-menu-pin'));
      expect(
        find.ancestor(of: pin, matching: find.byType(Opacity)),
        findsNothing,
      );
    },
  );

  testWidgets('message context menu is scroll-safe at phone heights', (
    tester,
  ) async {
    for (final size in [const Size(393, 873), const Size(360, 720)]) {
      await _openMenu(tester, online: true, size: size);

      expect(find.byKey(const Key('message-context-menu')), findsOneWidget);
      expect(tester.takeException(), isNull);

      final scroll = find.byType(SingleChildScrollView).last;
      await tester.drag(scroll, const Offset(0, -400));
      await tester.pump();
      expect(find.text('Delete for everyone'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
  });
}
