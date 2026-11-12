/// Mascot §J5: sticker ids, the bubble, the picker and where a sticker shows.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/core/constants/app_strings.dart';
import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/message_body_text.dart';
import 'package:kuch_bhi/features/chat/widgets/message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/message_context_menu.dart';
import 'package:kuch_bhi/features/chat/widgets/pinned_message_banner.dart';
import 'package:kuch_bhi/features/chat/widgets/reply_quote.dart';
import 'package:kuch_bhi/features/starred_messages/screens/starred_messages_screen.dart';
import 'package:kuch_bhi/features/stickers/sticker_widgets.dart';
import 'package:kuch_bhi/features/stickers/stickers.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';

import '../core/sheet_harness.dart';

Message _sticker({
  String localId = 'st1',
  String? body,
  bool isStarred = false,
}) => Message(
  localId: localId,
  serverId: 'srv-$localId',
  conversationId: 'c1',
  senderId: 'u_peer',
  type: 'sticker',
  decryptedBody: body,
  status: 'sent',
  isStarred: isStarred,
  createdAt: DateTime(2026, 11, 11, 12, 41),
);

Image _imageOf(WidgetTester tester, String id) => tester
    .widgetList<Image>(find.byType(Image))
    .firstWhere((i) => (i.image as ResizeImage).imageProvider is AssetImage &&
        ((i.image as ResizeImage).imageProvider as AssetImage).assetName ==
            'assets/stickers/$id.webp');

Future<void> _pumpBubble(
  WidgetTester tester, {
  String? body,
  bool large = false,
}) async {
  if (body != null) bodyCache.put('st1', body);
  await pumpHost(
    tester,
    Scaffold(
      body: ListView(
        children: [MessageBubble(message: _sticker(), isMine: false)],
      ),
    ),
    large: large,
    overrides: [
      messageBodyProvider.overrideWith(
        (ref, id) => body ?? Completer<String?>().future,
      ),
      outboxStatusProvider.overrideWith((ref, c) => Stream.value(const [])),
    ],
  );
}

void main() {
  setUp(bodyCache.clear);

  group('ids', () {
    test('stickerIdOf reads only the exact wire body', () {
      expect(stickerIdOf('Sticker: hi'), 'hi');
      expect(stickerIdOf('Sticker: on-my-way'), 'on-my-way');
      for (final bad in ['Sticker: Hi', 'Sticker: hi!', 'hi', 'Sticker:',
          'Sticker: ', 'Sticker: -hi', 'Sticker: hi-', 'Sticker: a--b']) {
        expect(stickerIdOf(bad), isNull, reason: bad);
      }
      expect(stickerBody('chill'), 'Sticker: chill');
    });

    test('assets/stickers/ holds exactly the kStickers ids', () {
      final files = Directory('assets/stickers')
          .listSync()
          .map((f) => f.uri.pathSegments.last)
          .toSet();
      expect(files, {for (final s in kStickers) '${s.id}.webp'});
      expect(kStickers.map((s) => s.id).toSet().length, kStickers.length);
    });

    test('chat list label', () {
      expect(conversationPreviewLabel('sticker'), kPreviewStickerLabel);
      expect(kPreviewStickerLabel, '🍊 Sticker');
      expect(kTextLikeTypes, {'text', 'sticker'});
    });
  });

  group('bubble', () {
    testWidgets('a sticker shows its image at 128 with no bubble fill and '
        'reads "Sticker, Hi"', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpBubble(tester, body: 'Sticker: hi');
      expect(tester.getSize(find.byType(StickerImage)), const Size(128, 128));
      final image = _imageOf(tester, 'hi');
      expect((image.image as ResizeImage).width, 128 * 3,
          reason: 'decoded at the shown size (test dpr 3)');
      expect(find.text('Sticker: hi'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'^Sticker, Hi\. From ')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('undecrypted: an empty 128 box, no image', (tester) async {
      await _pumpBubble(tester);
      expect(find.byType(StickerImage), findsNothing);
      expect(
        tester.getSize(find.byWidgetPredicate(
            (w) => w is SizedBox && w.width == 128 && w.height == 128)),
        const Size(128, 128),
      );
    });

    testWidgets('unknown id from a newer app: the update line', (tester) async {
      await _pumpBubble(tester, body: 'Sticker: party');
      expect(find.text('Sticker'), findsOneWidget);
      expect(find.text('Update Kuch Bhi to see it'), findsOneWidget);
      expect(find.byType(StickerImage), findsNothing);
    });

    testWidgets('360×640 at 200% text: no overflow', (tester) async {
      await _pumpBubble(tester, body: 'Sticker: on-my-way', large: true);
      expect(tester.takeException(), isNull);
    });
  });

  group('picker', () {
    Future<List<String>> openSheet(WidgetTester tester, {bool large = false})
        async {
      final sent = <String>[];
      await pumpHost(
        tester,
        SheetLauncher((context, ref) => showStickerSheet(
              context,
              onSend: (s) async => sent.add(s.id),
            )),
        large: large,
      );
      await tapOpen(tester);
      return sent;
    }

    testWidgets('10 labelled tiles; a tap sends once and closes the sheet',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final sent = await openSheet(tester);
      expect(find.text('Stickers'), findsOneWidget);
      expect(find.byType(StickerImage), findsNWidgets(10));
      for (final s in kStickers) {
        expect(find.bySemanticsLabel('Send sticker: ${s.label}'),
            findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('sticker-tile-hi')));
      await tester.tap(find.byKey(const ValueKey('sticker-tile-hi')),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(sent, ['hi']);
      expect(find.text('Stickers'), findsNothing, reason: 'sheet closed');
      semantics.dispose();
    });

    testWidgets('360×640 at 200% text: the sheet fits', (tester) async {
      await openSheet(tester, large: true);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('sticker-tile-celebrate')),
          findsOneWidget);
    });
  });

  group('where a sticker shows', () {
    testWidgets('long-press menu: no Copy', (tester) async {
      bodyCache.put('st1', 'Sticker: hi');
      await pumpHost(
        tester,
        SheetLauncher((context, ref) => showMessageMenu(
              context: context,
              ref: ref,
              message: _sticker(body: 'Sticker: hi'),
              isMine: true,
              senderName: 'You',
            )),
        overrides: [
          messageRepositoryProvider
              .overrideWithValue(FakeMessageRepository()),
          messageBodyProvider.overrideWith((ref, id) async => 'Sticker: hi'),
          isOnlineProvider.overrideWith((ref) => Stream.value(true)),
        ],
      );
      await tapOpen(tester);
      expect(find.text('Star'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      expect(find.text(kPreviewStickerLabel), findsOneWidget);
    });

    testWidgets('reply quote: thumbnail + "Sticker"', (tester) async {
      bodyCache.put('st1', 'Sticker: love');
      final db = AppDatabase.test();
      addTearDown(db.close);
      await pumpHost(
        tester,
        Scaffold(
          body: ReplyQuote.fromMessage(
            _sticker(body: 'Sticker: love'),
            'Asha',
            compact: true,
          ),
        ),
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          messageBodyProvider.overrideWith((ref, id) async => 'Sticker: love'),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Sticker'), findsOneWidget);
      expect(tester.getSize(find.byType(StickerImage)), const Size(32, 32));
    });

    testWidgets('pinned banner: thumbnail + "Sticker"', (tester) async {
      await pumpHost(
        tester,
        const Scaffold(body: PinnedMessageBanner(conversationId: 'c1')),
        overrides: [
          pinnedMessagesProvider('c1').overrideWith(
              (ref) => Stream.value([_sticker(body: 'Sticker: thanks')])),
          messageBodyProvider.overrideWith(
              (ref, id) async => 'Sticker: thanks'),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text('Sticker'), findsOneWidget);
      expect(tester.getSize(find.byType(StickerImage)), const Size(24, 24));
    });

    testWidgets('starred list: thumbnail + "Sticker"', (tester) async {
      final db = AppDatabase.test();
      addTearDown(db.close);
      final repo = _StarredRepo([_sticker(body: 'Sticker: chill',
          isStarred: true)]);
      await pumpHost(
        tester,
        StarredMessagesScreen(conversationId: 'c1', onJump: (_) {}),
        overrides: [
          messageRepositoryProvider.overrideWithValue(repo),
          messageBodyProvider.overrideWith((ref, id) async => 'Sticker: chill'),
          currentUserIdProvider.overrideWith((ref) async => 'u_me'),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.text('Sticker'), findsOneWidget);
      expect(tester.getSize(find.byType(StickerImage)), const Size(48, 48));
    });
  });
}

class _StarredRepo extends FakeMessageRepository {
  _StarredRepo(this.starred);
  final List<Message> starred;

  @override
  Future<List<Message>> getStarredMessages(String conversationId) async =>
      starred;
}
