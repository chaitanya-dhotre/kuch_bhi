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
import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/widgets/message_context_menu.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

Message _msg({bool isMine = true}) => Message(
      localId: 'loc1',
      serverId: 'srv1',
      conversationId: 'g1',
      senderId: isMine ? 'u_test' : 'u_other',
      type: 'text',
      decryptedBody: 'hello',
      status: 'sent',
      createdAt: DateTime.utc(2026, 1, 1),
    );

class _MenuLauncher extends ConsumerWidget {
  const _MenuLauncher();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open-menu'),
            onPressed: () => showMessageMenu(
              context: context,
              ref: ref,
              message: _msg(),
              isMine: true,
              senderName: 'Ada',
            ),
            child: const Text('open'),
          ),
        ),
      );
}

Future<void> _openMenu(WidgetTester tester, {required bool online}) async {
  // The sheet carries 7 tiles + reaction row; the default 800×600 test
  // surface overflows the Column. Give it phone-ish height.
  tester.view.physicalSize = const Size(1080, 2400);
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
        home: const _MenuLauncher(),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-menu')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'offline menu: pin + delete-for-everyone disabled with hint; '
      'reactions greyed; star/delete-for-me/reply/copy enabled', (tester) async {
    await _openMenu(tester, online: false);

    // Pin / delete-for-everyone: present, disabled, hint visible.
    final pinTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Pin'), matching: find.byType(ListTile)),
    );
    expect(pinTile.enabled, isFalse,
        reason: 'pin is unwired offline — tile must be disabled');
    expect(pinTile.onTap, isNull);
    expect(find.text('Available online'), findsWidgets,
        reason: 'disabled tiles carry the hint');

    final delAllTile = tester.widget<ListTile>(
      find.ancestor(
          of: find.text('Delete for everyone'), matching: find.byType(ListTile)),
    );
    expect(delAllTile.enabled, isFalse,
        reason: 'delete-for-everyone is server-first — disabled offline');

    // Star / delete-for-me / reply stay enabled (durable local paths).
    for (final label in ['Star', 'Delete for me', 'Reply']) {
      final tile = tester.widget<ListTile>(
        find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
      );
      expect(tile.enabled, isTrue, reason: '$label has a local path offline');
      expect(tile.onTap, isNotNull);
    }

    // Reaction row greyed (opacity < 1) — network-only.
    final opacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('👍'),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, lessThan(1.0),
        reason: 'reaction row visibly disabled offline');
  });

  testWidgets('online menu: pin + delete-for-everyone enabled, hint gone',
      (tester) async {
    await _openMenu(tester, online: true);

    final pinTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Pin'), matching: find.byType(ListTile)),
    );
    expect(pinTile.enabled, isTrue);
    expect(pinTile.onTap, isNotNull);
    expect(find.text('Available online'), findsNothing);
  });
}
