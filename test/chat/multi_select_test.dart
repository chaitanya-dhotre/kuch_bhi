/// 12.8 multi-select (docs/design/pages/multi-select.md A–H): the chat's
/// selection stays open at 0, a tap toggles on the whole row with every
/// inner tap off, a long-press while selecting toggles and drags a range
/// (with autoscroll), and the shared bar copies, stars and deletes.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/decrypt/body_cache.dart';
import 'package:kuch_bhi/core/widgets/app_sheet.dart';
import 'package:kuch_bhi/domain/entities/conversation.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/domain/entities/user.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/providers/upload_progress_provider.dart';
import 'package:kuch_bhi/features/chat/screens/album_screen.dart';
import 'package:kuch_bhi/features/chat/screens/chat_screen.dart';
import 'package:kuch_bhi/features/chat/widgets/album_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/image_message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/reaction_bar.dart';
import 'package:kuch_bhi/features/chat/widgets/reply_quote.dart';
import 'package:kuch_bhi/features/chat/widgets/selection_bar.dart';
import 'package:kuch_bhi/features/chat/widgets/swipe_to_reply.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';
import 'package:kuch_bhi/features/media/screens/media_viewer_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';
import 'package:kuch_bhi/services/presence_service.dart';

import '../core/sheet_harness.dart';

const _me = 'u_me';
const _them = 'u_asha';

Message _text(
  String id,
  DateTime at, {
  bool mine = false,
  String? serverId,
  bool starred = false,
  bool tombstone = false,
  String? replyTo,
  String type = 'text',
}) =>
    Message(
      localId: id,
      serverId: serverId ?? 's_$id',
      conversationId: 'c1',
      senderId: mine ? _me : _them,
      type: type,
      status: 'read',
      createdAt: at,
      isStarred: starred,
      isDeletedForEveryone: tombstone,
      replyToId: replyTo,
    );

Message _media(String id, DateTime at, {String? album, int? index}) =>
    Message(
      localId: id,
      serverId: 's_$id',
      mediaId: 's_$id',
      conversationId: 'c1',
      senderId: _me,
      type: 'image',
      status: 'read',
      createdAt: at,
      albumId: album,
      albumIndex: index,
    );

DateTime _d1(int m) => DateTime(2026, 10, 1, 10, m);
DateTime _d2(int m) => DateTime(2026, 10, 2, 10, m);

/// one, two (day 1) · date separator · three, a system row, five … eight.
List<Message> _base() => [
      _text('eight', _d2(5)),
      _text('seven', _d2(4), mine: true),
      _text('six', _d2(3)),
      _text('five', _d2(2), mine: true),
      _text('sys', _d2(1), type: 'system'),
      _text('three', _d2(0)),
      _text('two', _d1(1), mine: true),
      _text('one', _d1(0)),
    ];

class _Pres implements PresenceService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _Repo implements MessageRepository {
  _Repo(this.rows, {this.conv, this.members = const []}) {
    ctrl.add(rows);
  }

  List<Message> rows;
  final Conversation? conv;
  final List<User> members;
  final ctrl = StreamController<List<Message>>();
  final deleted = <String>[];
  final deletedEveryone = <String>[];
  final starCalls = <(List<String>, bool)>[];
  var reactionCalls = 0;
  var loadMoreCalls = 0;
  var fetchCalls = 0;

  void emit(List<Message> next) {
    rows = next;
    ctrl.add(next);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();

  @override
  Stream<List<Message>> watchMessages(String conversationId) => ctrl.stream;

  @override
  Stream<Conversation?> watchConversation(String conversationId) =>
      Stream.value(conv);

  @override
  Stream<List<User>> watchGroupMembers(String conversationId) =>
      Stream.value(members);

  @override
  Future<bool> hasUsableKey(String conversationId) async => true;

  @override
  Future<int> countUndecryptable(String conversationId) async => 0;

  @override
  Stream<List<Message>> watchPinnedMessages(String conversationId) =>
      Stream.value(const []);

  @override
  Future<void> deleteMessage(String localId, {bool forEveryone = false}) async {
    (forEveryone ? deletedEveryone : deleted).add(localId);
  }

  @override
  Future<void> setStarred(List<String> localIds, bool starred) async =>
      starCalls.add((localIds, starred));

  @override
  Future<void> addReaction(String messageServerId, String emoji) async =>
      reactionCalls++;

  @override
  Future<void> removeReaction(String reactionId) async => reactionCalls++;

  @override
  Future<void> loadMoreMessages(String conversationId, int offset) async =>
      loadMoreCalls++;

  @override
  Future<void> fetchAndCacheSingleMessage(
    String messageId,
    String conversationId,
  ) async =>
      fetchCalls++;
}

late File _file;

/// Pushes the chat over a launcher so back can pop it.
Future<_Repo> _pumpChat(
  WidgetTester tester, {
  List<Message>? rows,
  bool online = true,
  Stream<bool>? onlineStream,
  Conversation? conv,
  List<User> members = const [],
  Map<String, List<ReactionGroup>> reactions = const {},
  Size size = const Size(800, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final chat = conv ?? const Conversation(id: 'c1', type: 'direct');
  final repo = _Repo(rows ?? _base(), conv: chat, members: members);
  // The body of a text row is its local id.
  for (final m in repo.rows) {
    if (m.type == 'text' || m.type == 'system') bodyCache.put(m.localId, m.localId);
  }
  addTearDown(repo.ctrl.close);
  await pumpHost(
    tester,
    SheetLauncher(
      (context, ref) => Navigator.of(context).push<void>(
        // Reduced motion: the composer's mic pulse never settles otherwise.
        MaterialPageRoute<void>(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: ChatScreen(conversation: chat),
          ),
        ),
      ),
    ),
    overrides: [
      messageRepositoryProvider.overrideWithValue(repo),
      presenceServiceProvider.overrideWithValue(_Pres()),
      currentUserIdProvider.overrideWith((ref) async => _me),
      isOnlineProvider.overrideWith(
        (ref) => onlineStream ?? Stream.value(online),
      ),
      // The body of a text row is its local id.
      messageBodyProvider.overrideWith((ref, id) async => id),
      outboxStatusProvider.overrideWith((ref, c) => Stream.value(const [])),
      reactionsProvider.overrideWith(
        (ref, id) => Stream.value(reactions[id] ?? const []),
      ),
      mediaFileProvider.overrideWith(
        (ref, r) async => LocalMediaFile(file: _file, width: 300, height: 400),
      ),
      mediaFullLocalProvider.overrideWith((ref, r) => Stream.value(_file)),
      mediaBlobStatusProvider.overrideWith(
        (ref, r) async => MediaBlobStatus.other,
      ),
      uploadPendingProvider.overrideWith((ref, id) => Stream.value(false)),
      uploadProgressProvider.overrideWith((ref, id) => Stream.value(null)),
    ],
  );
  await tapOpen(tester);
  // Past the chat's 1.5 s mark-read debounce.
  await tester.pump(const Duration(seconds: 2));
  return repo;
}

Offset _at(WidgetTester tester, String text) =>
    tester.getCenter(find.text(text).first);

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tapAt(_at(tester, text));
  await tester.pump();
}

/// Long-press [text] → the menu → Select.
Future<void> _select(WidgetTester tester, String text) async {
  await tester.longPressAt(_at(tester, text));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('message-menu-select')));
  await tester.pumpAndSettle();
}

/// Long-press and keep holding (B2).
Future<TestGesture> _hold(WidgetTester tester, Offset at) async {
  final g = await tester.startGesture(at);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  return g;
}

IconButton _button(WidgetTester tester, String tooltip) => tester.widget(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );

/// The single photo (album tiles are image bubbles too).
final _photo = find.byWidgetPredicate(
  (w) => w is ImageMessageBubble && w.serverId == 's_img',
);

bool _ignored(WidgetTester tester, Finder inner) => find
    .ancestor(
      of: inner,
      matching: find.byWidgetPredicate((w) => w is IgnorePointer && w.ignoring),
    )
    .evaluate()
    .isNotEmpty;

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('multi_select');
    _file = File('${dir.path}/t.jpg')..writeAsBytesSync([0, 1, 2]);
  });
  setUp(bodyCache.clear);
  tearDown(bodyCache.clear);

  group('entering, toggling, leaving', () {
    testWidgets('Select → 1 selected, keyboard down; taps toggle; 0 stays '
        'open with every action disabled', (tester) async {
      await _pumpChat(tester);
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await _select(tester, 'eight');
      expect(find.text('1 selected'), findsOneWidget);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isFalse, reason: 'A1: keyboard down');

      await _tap(tester, 'six');
      expect(find.text('2 selected'), findsOneWidget);
      await _tap(tester, 'six');
      expect(find.text('1 selected'), findsOneWidget);
      await _tap(tester, 'eight');
      expect(find.text('0 selected'), findsOneWidget,
          reason: 'A2: selection stays open at 0');
      for (final tip in [
        'Copy selected messages',
        'Star selected messages',
        'Delete selected messages',
      ]) {
        expect(_button(tester, tip).onPressed, isNull, reason: tip);
      }
    });

    testWidgets('✕ exits; back exits first, then pops the chat',
        (tester) async {
      await _pumpChat(tester);
      await _select(tester, 'eight');
      await tester.tap(find.byTooltip('Exit selection'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsNothing);

      await _select(tester, 'eight');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('1 selected'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing, reason: 'now it pops');
    });

    testWidgets('a tap beside the bubble toggles; long-press while selecting '
        'opens no menu; date and system rows never select', (tester) async {
      await _pumpChat(tester);
      await _select(tester, 'eight');

      // 'two' is mine (right-aligned): the empty left side of its row.
      await tester.tapAt(Offset(20, _at(tester, 'two').dy));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget, reason: 'B1 whole row');

      await tester.longPressAt(_at(tester, 'six'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message-context-menu')), findsNothing);
      expect(find.text('3 selected'), findsOneWidget, reason: 'B2 toggles');

      await _tap(tester, 'sys');
      expect(find.text('3 selected'), findsOneWidget, reason: 'B5 system');
      await tester.tapAt(tester.getCenter(find.textContaining('Oct').first));
      await tester.pump();
      expect(find.text('3 selected'), findsOneWidget, reason: 'B5 date');
    });

    testWidgets('inner taps are off while selecting; no reply on a sideways '
        'drag', (tester) async {
      final rows = [
        _text('reply', _d2(9), replyTo: 's_one'),
        _media('a1', _d2(8), album: 'alb', index: 1),
        _media('a0', _d2(7), album: 'alb', index: 0),
        _media('img', _d2(6)),
        ..._base(),
      ];
      final repo = await _pumpChat(
        tester,
        rows: rows,
        size: const Size(800, 2200),
        reactions: {
          's_three': const [
            ReactionGroup(emoji: '👍', count: 1, isMine: false),
          ],
        },
      );
      await _select(tester, 'eight');

      for (final inner in [
        find.byType(ReplyQuote),
        find.byType(AlbumBubble),
        find.byType(ImageMessageBubble),
        find.byType(ReactionBar),
        find.byType(SwipeToReply),
      ]) {
        expect(_ignored(tester, inner), isTrue, reason: '$inner');
      }

      await tester.tapAt(tester.getCenter(_photo));
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerScreen), findsNothing);
      await tester.tapAt(tester.getCenter(find.byType(AlbumBubble)));
      await tester.pumpAndSettle();
      expect(find.byType(AlbumScreen), findsNothing);
      await tester.tapAt(tester.getCenter(find.byType(ReplyQuote)));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(
        find.byKey(const ValueKey('reaction-chip-s_three-👍')),
      ));
      await tester.pumpAndSettle();
      expect(repo.reactionCalls, 0, reason: 'no reaction toggled');
      // eight + img + album (2 rows) + reply + three; each tap toggled.
      expect(find.text('6 selected'), findsOneWidget);

      await tester.dragFrom(_at(tester, 'five'), const Offset(-150, 0));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatScreen)),
      );
      expect(container.read(replyProvider('c1')), isNull);
    });
  });

  group('drag range', () {
    testWidgets('long-press two, slide to six → two…six; back to three → '
        'two, three; system and date rows skipped', (tester) async {
      await _pumpChat(tester);
      await _select(tester, 'eight');

      final g = await _hold(tester, _at(tester, 'two'));
      expect(find.text('2 selected'), findsOneWidget);
      await g.moveTo(_at(tester, 'six'));
      await tester.pump();
      // eight + two, three, five, six (sys skipped).
      expect(find.text('5 selected'), findsOneWidget);
      await g.moveTo(_at(tester, 'three'));
      await tester.pump();
      expect(find.text('3 selected'), findsOneWidget);
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
    });

    testWidgets('a range that starts on a selected row deselects',
        (tester) async {
      await _pumpChat(tester);
      await _select(tester, 'eight');
      await _tap(tester, 'six');
      await _tap(tester, 'two');
      expect(find.text('3 selected'), findsOneWidget);

      final g = await _hold(tester, _at(tester, 'six'));
      await g.moveTo(_at(tester, 'eight'));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget, reason: 'only two');
    });

    testWidgets('an album inside the range selects all its rows',
        (tester) async {
      await _pumpChat(tester, rows: [
        _text('top', _d2(9)),
        _media('a2', _d2(8), album: 'alb', index: 2),
        _media('a1', _d2(7), album: 'alb', index: 1),
        _media('a0', _d2(6), album: 'alb', index: 0),
        _text('bottom', _d2(5)),
      ]);
      await _select(tester, 'top');
      await _tap(tester, 'top'); // 0 selected
      final g = await _hold(tester, _at(tester, 'bottom'));
      await g.moveTo(_at(tester, 'top'));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(find.text('5 selected'), findsOneWidget);
    });

    testWidgets('a finger in the top band autoscrolls and the range grows; '
        'older history loads', (tester) async {
      final rows = [
        for (var i = 59; i >= 0; i--)
          _text('m$i', DateTime(2026, 10, 2, 9).add(Duration(minutes: i))),
      ];
      final repo = await _pumpChat(tester, rows: rows, size: const Size(800, 700));
      await _select(tester, 'm59');
      final g = await _hold(tester, _at(tester, 'm58'));
      expect(find.text('2 selected'), findsOneWidget);

      final list = find.byType(ListView);
      final top = tester.getTopLeft(list).dy;
      final position =
          tester.state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
          ).position;
      expect(position.pixels, 0);
      await g.moveTo(Offset(400, top + 8));
      for (var i = 0; i < 250; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(position.pixels, greaterThan(0), reason: 'B4 scrolled');
      final count = int.parse(
        tester
            .widget<Text>(find.textContaining(' selected'))
            .data!
            .split(' ')
            .first,
      );
      expect(count, greaterThan(10), reason: 'the range followed');
      expect(repo.loadMoreCalls, greaterThan(0), reason: 'older history');
      await g.up();
      await tester.pumpAndSettle();
    });
  });

  group('actions', () {
    late String? clip;
    setUp(() => clip = null);

    void mockClipboard(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clip = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
    }

    testWidgets('Copy 2 texts + 1 photo → oldest first, blank line; toast '
        'says some were skipped; selection ends', (tester) async {
      mockClipboard(tester);
      await _pumpChat(tester, rows: [_media('img', _d2(9)), ..._base()]);
      await _select(tester, 'six');
      await _tap(tester, 'two');
      await tester.tapAt(tester.getCenter(_photo));
      await tester.pump();
      expect(find.text('3 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Copy selected messages'));
      await tester.pump();
      expect(clip, 'two\n\nsix');
      expect(find.text('Copied 2 of 3. Only text is copied.'), findsOneWidget);
      expect(find.text('3 selected'), findsNothing);
    });

    testWidgets('Copy one text → exactly its body, Copied', (tester) async {
      mockClipboard(tester);
      await _pumpChat(tester);
      await _select(tester, 'six');
      await tester.tap(find.byTooltip('Copy selected messages'));
      await tester.pump();
      expect(clip, 'six');
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('Copy several texts → Copied N messages', (tester) async {
      mockClipboard(tester);
      await _pumpChat(tester);
      await _select(tester, 'six');
      await _tap(tester, 'one');
      await _tap(tester, 'eight');
      await tester.tap(find.byTooltip('Copy selected messages'));
      await tester.pump();
      expect(clip, 'one\n\nsix\n\neight');
      expect(find.text('Copied 3 messages'), findsOneWidget);
    });

    testWidgets('only media selected → Copy disabled', (tester) async {
      await _pumpChat(tester, rows: [_media('img', _d2(9)), ..._base()]);
      await _select(tester, 'six');
      await _tap(tester, 'six');
      await tester.tapAt(tester.getCenter(_photo));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(_button(tester, 'Copy selected messages').onPressed, isNull);
    });

    testWidgets('Star with 1 of 3 starred → stars the other 2', (tester) async {
      final rows = _base()
        ..[0] = _text('eight', _d2(5), starred: true);
      final repo = await _pumpChat(tester, rows: rows);
      await _select(tester, 'eight');
      await _tap(tester, 'six');
      await _tap(tester, 'two');
      await tester.tap(find.byTooltip('Star selected messages'));
      await tester.pump();
      expect(repo.starCalls, hasLength(1));
      expect(repo.starCalls.single.$1, ['two', 'six']);
      expect(repo.starCalls.single.$2, isTrue);
      expect(find.text('Starred 2 messages'), findsOneWidget);
      expect(find.text('3 selected'), findsNothing);
    });

    testWidgets('all starred → Unstar unstars every one', (tester) async {
      final rows = [
        for (final m in _base())
          m.localId == 'six' || m.localId == 'eight'
              ? _text(m.localId, m.createdAt, starred: true)
              : m,
      ];
      final repo = await _pumpChat(tester, rows: rows);
      await _select(tester, 'eight');
      await _tap(tester, 'six');
      await tester.tap(find.byTooltip('Unstar selected messages'));
      await tester.pump();
      expect(repo.starCalls.single.$1, ['six', 'eight']);
      expect(repo.starCalls.single.$2, isFalse);
      expect(find.text('Unstarred 2 messages'), findsOneWidget);
    });

    testWidgets('all own online → two-row sheet; for everyone per D5',
        (tester) async {
      final rows = [
        _text('tomb', _d2(9), mine: true, tombstone: true),
        _text('unsent', _d2(8), mine: true, serverId: null)
            .copyWithNoServer(),
        _text('sent', _d2(7), mine: true),
        ..._base(),
      ];
      final repo = await _pumpChat(tester, rows: rows);
      await _select(tester, 'sent');
      await _tap(tester, 'unsent');
      await tester.tapAt(
        tester.getCenter(find.textContaining('Message deleted')),
      );
      await tester.pump();
      expect(find.text('3 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete selected messages'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SheetActionRow, 'Delete for me'),
          findsOneWidget);
      await tester.tap(
        find.widgetWithText(SheetActionRow, 'Delete for everyone'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Delete 3 messages?'), findsOneWidget);
      expect(
        find.text('These messages will be deleted for everyone in this chat.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo.deletedEveryone, ['sent']);
      expect(repo.deleted.toSet(), {'unsent', 'tomb'});
      expect(find.text('3 selected'), findsNothing);
    });

    testWidgets('offline → Delete for everyone dimmed, Available online',
        (tester) async {
      await _pumpChat(tester, online: false);
      await _select(tester, 'seven');
      await tester.tap(find.byTooltip('Delete selected messages'));
      await tester.pumpAndSettle();
      final row = tester.widget<SheetActionRow>(
        find.widgetWithText(SheetActionRow, 'Delete for everyone'),
      );
      expect(row.enabled, isFalse);
      expect(find.text('Available online'), findsOneWidget);
    });

    testWidgets('the sheet follows the connection live; going offline at '
        'the confirm deletes nothing', (tester) async {
      final net = StreamController<bool>.broadcast();
      addTearDown(net.close);
      final repo = await _pumpChat(tester, onlineStream: net.stream);
      net.add(true);
      await tester.pump();
      await _select(tester, 'seven');
      await tester.tap(find.byTooltip('Delete selected messages'));
      await tester.pumpAndSettle();
      SheetActionRow everyone() => tester.widget<SheetActionRow>(
            find.widgetWithText(SheetActionRow, 'Delete for everyone'),
          );
      expect(everyone().enabled, isTrue);
      net.add(false);
      await tester.pump();
      await tester.pump();
      expect(everyone().enabled, isFalse, reason: 'dims while open');
      expect(find.text('Available online'), findsOneWidget);
      net.add(true);
      await tester.pump();
      expect(everyone().enabled, isTrue, reason: 'wakes while open');

      await tester.tap(
        find.widgetWithText(SheetActionRow, 'Delete for everyone'),
      );
      await tester.pumpAndSettle();
      net.add(false);
      await tester.pump();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo.deletedEveryone, isEmpty);
      expect(repo.deleted, isEmpty);
      expect(find.text('Available online'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget, reason: 'kept');
    });

    testWidgets('one of theirs → straight to Delete 2 messages? for me',
        (tester) async {
      final repo = await _pumpChat(tester);
      await _select(tester, 'seven');
      await _tap(tester, 'six');
      await tester.tap(find.byTooltip('Delete selected messages'));
      await tester.pumpAndSettle();
      expect(find.text('Delete for everyone'), findsNothing);
      expect(find.text('Delete 2 messages?'), findsOneWidget);
      expect(find.text('These messages will be deleted for you only.'),
          findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['six', 'seven']);
    });

    testWidgets('a group you left → delete for me only', (tester) async {
      final rows = [
        for (final m in _base())
          if (m.senderId == _me) m,
      ];
      final repo = await _pumpChat(
        tester,
        rows: rows,
        conv: const Conversation(id: 'c1', type: 'group', name: 'G'),
        members: [
          User(
            id: _me,
            displayName: 'Me',
            username: 'me',
            email: 'me@x.test',
            friendCode: 'AAAAAA',
            createdAt: DateTime(2026),
            groupRole: 'left',
          ),
        ],
      );
      await _select(tester, 'seven');
      await _tap(tester, 'five');
      await tester.tap(find.byTooltip('Delete selected messages'));
      await tester.pumpAndSettle();
      expect(find.text('Delete for everyone'), findsNothing);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['five', 'seven']);
      expect(repo.deletedEveryone, isEmpty);
    });

    testWidgets('cancel keeps the selection', (tester) async {
      final repo = await _pumpChat(tester);
      await _select(tester, 'six');
      await tester.tap(find.byTooltip('Delete selected messages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(repo.deleted, isEmpty);
    });

    testWidgets('a selected row that leaves the list is skipped (D7, F6)',
        (tester) async {
      final repo = await _pumpChat(tester);
      await _select(tester, 'six');
      await _tap(tester, 'eight');
      expect(find.text('2 selected'), findsOneWidget);
      repo.emit([for (final m in _base()) if (m.localId != 'eight') m]);
      await tester.pump();
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget, reason: 'count drops');
      await tester.tap(find.byTooltip('Delete selected messages'));
      await tester.pumpAndSettle();
      expect(find.text('Delete message?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(repo.deleted, ['six']);
    });
  });

  group('semantics and large text', () {
    testWidgets('rows read selected / not selected; the count is a live '
        'region; disabled buttons are not enabled', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpChat(tester);
      await _select(tester, 'eight');

      final on = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'\. eight\. .*, selected$')),
      );
      expect(on, isSemantics(isSelected: true, hasSelectedState: true));
      expect(on.hintOverrides?.onTapHint, 'Deselect');
      final off = tester.getSemantics(
        find.bySemanticsLabel(RegExp(r'\. six\. .*, not selected$')),
      );
      expect(off, isSemantics(isSelected: false, hasSelectedState: true));
      expect(off.hintOverrides?.onTapHint, 'Select');
      expect(find.bySemanticsLabel('six'), findsNothing,
          reason: 'G1: inner nodes hidden while selecting');

      expect(tester.getSemantics(find.text('1 selected')),
          isSemantics(isLiveRegion: true));

      await _tap(tester, 'eight');
      expect(
        tester.getSemantics(find.byTooltip('Delete selected messages')),
        isSemantics(hasEnabledState: true, isEnabled: false),
      );
      handle.dispose();
    });

    for (final font in largeTextFonts) {
      testWidgets('360dp × 200% (${font ?? 'system'}): 120 selected + three '
          'icons fit one line', (tester) async {
        await pumpHost(
          tester,
          Scaffold(
            body: SelectionBar(
              count: 120,
              onExit: () {},
              onCopy: () {},
              canCopy: true,
              onStar: () {},
              canStar: true,
              onDelete: () {},
            ),
          ),
          large: true,
          fontFamily: font,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('120 selected'), findsOneWidget);
        final bar = tester.getRect(find.byType(SelectionBar));
        expect(bar.height, 56);
        for (final tip in [
          'Copy selected messages',
          'Star selected messages',
          'Delete selected messages',
        ]) {
          expect(tester.getRect(find.byTooltip(tip)).right,
              lessThanOrEqualTo(360));
        }
      });
    }
  });
}

extension on Message {
  /// The same row with no server id (an own unsent send).
  Message copyWithNoServer() => Message(
        localId: localId,
        conversationId: conversationId,
        senderId: senderId,
        type: type,
        status: 'pending',
        createdAt: createdAt,
      );
}
