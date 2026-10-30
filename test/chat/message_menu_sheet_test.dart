import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/widgets/message_body_text.dart';
import 'package:kuch_bhi/features/chat/widgets/message_context_menu.dart';
import 'package:kuch_bhi/features/chat/widgets/reaction_picker.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import '../core/sheet_harness.dart';

class _Repo extends FakeMessageRepository {
  final deleted = <String>[];

  @override
  Future<void> deleteMessage(String localId, {bool forEveryone = false}) async =>
      deleted.add(localId);
}

final _message = Message(
  localId: 'loc1',
  serverId: 'srv1',
  conversationId: 'c1',
  senderId: 'u_me',
  type: 'text',
  decryptedBody: 'hello',
  status: 'sent',
  createdAt: DateTime.utc(2026, 1, 1),
);

Future<_Repo> _openMenu(
  WidgetTester tester, {
  bool large = false,
  String? fontFamily,
  bool online = true,
  Message? message,
  bool isMine = true,
}) async {
  final repo = _Repo();
  await pumpHost(
    tester,
    SheetLauncher((context, ref) => showMessageMenu(
          context: context,
          ref: ref,
          message: message ?? _message,
          isMine: isMine,
          senderName: 'Ada Lovelace',
          onSelect: () {},
        )),
    overrides: [
      messageRepositoryProvider.overrideWithValue(repo),
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
    ],
    large: large,
    fontFamily: fontFamily,
  );
  await tapOpen(tester);
  return repo;
}

void main() {
  testWidgets('preview names my own message "You", theirs by name',
      (tester) async {
    await _openMenu(tester);
    final sender = find.byKey(const Key('message-menu-preview-sender'));
    expect(tester.widget<Text>(sender).data, 'You');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await _openMenu(tester, isMine: false);
    expect(tester.widget<Text>(sender).data, 'Ada Lovelace');
  });

  testWidgets('a media message previews as its type label, never a skeleton',
      (tester) async {
    await _openMenu(tester,
        message: Message(
          localId: 'loc2',
          serverId: 'srv2',
          conversationId: 'c1',
          senderId: 'u_me',
          type: 'image',
          status: 'sent',
          createdAt: DateTime.utc(2026, 1, 1),
        ));
    final body = find.byKey(const Key('message-menu-preview-body'));
    expect(tester.widget<Text>(body).data, '📷 Photo');
    expect(find.byType(MessageBodyText), findsNothing);
  });

  testWidgets('delete rows: error icon, ink label', (tester) async {
    await _openMenu(tester);
    final t = tokens(tester);
    for (final (icon, label) in [
      (Icons.delete_outline, 'Delete for me'),
      (Icons.delete_forever_outlined, 'Delete for everyone'),
    ]) {
      expect(tester.widget<Icon>(find.byIcon(icon)).color, t.error);
      expect(paintedColor(tester, find.text(label)), t.ink);
    }
    expectNoTextIn(tester, [t.error, t.accent, t.success],
        find.byKey(const Key('message-context-menu')));
  });

  testWidgets('Copy shows the R5 toast "Copied"', (tester) async {
    addTearDown(bodyCache.clear);
    bodyCache.put('loc1', 'hello');
    await _openMenu(tester);
    final t = tokens(tester);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Copied'), findsOneWidget);
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, t.surface, reason: 'R5, not a raw SnackBar');
    expect(bar.duration, const Duration(seconds: 3));
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });

  testWidgets('Delete for me asks with R20; Cancel keeps the message',
      (tester) async {
    final repo = await _openMenu(tester);
    await tester.tap(find.text('Delete for me'));
    await tester.pumpAndSettle();
    expect(find.text('Delete message?'), findsOneWidget);
    expect(find.text('This message will be deleted for you only.'),
        findsOneWidget);
    final t = tokens(tester);
    expect(
      tester
          .widget<Icon>(find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byIcon(Icons.delete_outline)))
          .color,
      t.error,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);
    expect(find.byKey(const Key('message-context-menu')), findsOneWidget);

    await tester.tap(find.text('Delete for me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(repo.deleted, ['loc1']);
  });

  testWidgets('quick row = decision 11 set + ＋ (More reactions), 48 circles',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _openMenu(tester);
    for (final emoji in kQuickReactions) {
      final key = ValueKey('message-menu-reaction-$emoji');
      expect(find.byKey(key), findsOneWidget);
      expect(tester.getSize(find.byKey(key)), const Size(48, 48));
    }
    expect(find.byKey(const Key('message-menu-reaction-👎')), findsNothing);
    final add = find.byKey(const Key('message-menu-reaction-add'));
    expect(tester.getSize(add), const Size(48, 48));
    expect(tester.getSemantics(add),
        isSemantics(
            label: 'More reactions', isButton: true, hasTapAction: true));
    semantics.dispose();
  });

  for (final font in largeTextFonts) {
    for (final online in [true, false]) {
      testWidgets(
          '360×200% (${font ?? 'system'}, ${online ? 'online' : 'offline'}): '
          'no overflow, rows reachable', (tester) async {
        await _openMenu(tester,
            large: true, fontFamily: font, online: online);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('Delete for everyone'), 200,
            scrollable: find.byType(Scrollable).last);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
