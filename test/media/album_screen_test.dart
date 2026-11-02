/// Albums 12.5 C17 / E2–E4c / F2: the collage screen — layout rects,
/// title + subtitle, tap → pager, long-press menu, selection bar, per-item
/// and multi-delete, semantics, 360×200%.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/widgets/app_sheet.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/chat/providers/album_provider.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/providers/upload_progress_provider.dart';
import 'package:kuch_bhi/features/chat/screens/album_screen.dart';
import 'package:kuch_bhi/features/media/album_layout.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';
import 'package:kuch_bhi/features/media/screens/media_viewer_screen.dart';
import 'package:kuch_bhi/features/settings/providers/font_provider.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

import '../core/sheet_harness.dart';
import 'viewer_harness.dart'
    show FakeMediaActions, inViewer;

final _at = DateTime(2026, 11, 1, 14, 30);

const _png1x1 = <int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0,
  1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68,
  65, 84, 8, 215, 99, 248, 207, 192, 0, 0, 0, 3, 0, 1, 166, 56, 198, 10, 0,
  0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
];

String _id(int i) => 'm$i';
String _srv(int i) => 's$i';

Message _row(int i, {String sender = 'u_me'}) => Message(
      localId: _id(i),
      serverId: _srv(i),
      conversationId: 'c1',
      senderId: sender,
      type: 'image',
      status: 'read',
      createdAt: _at.add(Duration(minutes: i)),
      albumId: 'alb0',
      albumIndex: i,
    );

class AlbumRepo implements MessageRepository {
  final deleted = <String>[];
  final deletedEveryone = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<void> deleteMessage(String localId, {bool forEveryone = false}) async {
    (forEveryone ? deletedEveryone : deleted).add(localId);
  }
}

class AlbumCtx {
  AlbumCtx({required this.rows, required this.ctrl, required this.repo});
  final List<Message> rows;
  final StreamController<List<Message>> ctrl;
  final AlbumRepo repo;

  void emit(List<Message> rows) {
    ctrl.add(List.of(rows));
  }
}

Future<AlbumCtx> pumpAlbum(
  WidgetTester tester, {
  List<Message> rows = const [],
  bool online = true,
  bool large = false,
  Size viewport = const Size(800, 600),
  int initialIndex = 0,
  String senderName = 'Asha Menon',
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final file = File(
      '${Directory.systemTemp.path}/album_screen_${DateTime.now().microsecondsSinceEpoch}.png')
    ..writeAsBytesSync(_png1x1);
  addTearDown(() {
    if (file.existsSync()) file.deleteSync();
  });

  // Distinct aspects per item so the rects are exercised, not degenerate.
  const sizes = {
    's0': (400, 200), 's1': (100, 200), 's2': (200, 200),
    's3': (300, 300), 's4': (200, 400), 's5': (400, 100),
    's6': (150, 150), 's7': (300, 150), 's8': (100, 300),
    's9': (200, 400), 's10': (400, 200), 's11': (250, 250),
    's12': (180, 180), 's13': (300, 200), 's14': (120, 240),
    's15': (400, 200), 's16': (200, 200), 's17': (300, 100),
    's18': (150, 300), 's19': (400, 200),
  };
  final ctrl = StreamController<List<Message>>();
  addTearDown(ctrl.close);
  ctrl.add(List.of(rows));
  final repo = AlbumRepo();

  await pumpHost(
    tester,
    Scaffold(
      body: Center(
        child: Builder(
          builder: (buttonContext) => TextButton(
            onPressed: () => Navigator.of(buttonContext).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AlbumScreen(
                  conversationId: 'c1',
                  albumId: 'alb0',
                  senderName: senderName,
                  timestamp: _at,
                  initialIndex: initialIndex,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
    overrides: [
      albumRowsProvider.overrideWith((ref, key) => ctrl.stream),
      currentUserIdProvider.overrideWith((ref) async => 'u_me'),
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
      messageRepositoryProvider.overrideWithValue(repo),
      mediaFileProvider.overrideWith((ref, r) async {
        final (w, h) = sizes[r.serverId] ?? (300, 400);
        return LocalMediaFile(file: file, width: w, height: h);
      }),
      mediaFullLocalProvider.overrideWith((ref, r) => Stream.value(file)),
      mediaBlobStatusProvider.overrideWith((ref, r) async =>
          MediaBlobStatus.other),
      mediaActionsProvider.overrideWithValue(FakeMediaActions()),
      fontFamilyProvider.overrideWith((ref) => Stream.value(AppFont.system)),
      uploadPendingProvider.overrideWith((ref, id) => Stream.value(false)),
      uploadProgressProvider.overrideWith((ref, id) => Stream.value(null)),
    ],
    large: large,
  );
  await tester.tap(find.text('open'));
  await tester.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
  return AlbumCtx(rows: rows, ctrl: ctrl, repo: repo);
}

/// The collage ListView is scrolled to the default viewport only; bring a
/// tile fully into view, then tap its centre.
Future<void> tapTile(WidgetTester tester, int i) async {
  final finder = find.byKey(ValueKey(_id(i)));
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder);
  await tester.pump();
}

Future<void> longPressTile(WidgetTester tester, int i) async {
  final finder = find.byKey(ValueKey(_id(i)));
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.longPress(finder);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  List<Message> five() => [for (var i = 0; i < 5; i++) _row(i)];

  Future<void> select(
    WidgetTester tester,
    List<int> select, {
    bool closeSheet = true,
  }) async {
    await longPressTile(tester, select.first);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    for (final i in select.skip(1)) {
      await tapTile(tester, i);
    }
  }

  testWidgets('tiles sit exactly on albumLayout rects, subtitle from counts',
      (tester) async {
    final ctx = await pumpAlbum(
      tester,
      rows: [for (var i = 0; i < 5; i++) _row(i, sender: 'u_other')],
      viewport: const Size(400, 1200),
    );
    final sizeOf = {
      's0': (400, 200), 's1': (100, 200), 's2': (200, 200),
      's3': (300, 300), 's4': (200, 400),
    };
    final aspects = [
      for (final s in ['s0', 's1', 's2', 's3', 's4'])
        sizeOf[s]!.$1 / sizeOf[s]!.$2,
    ];
    const contentWidth = 400.0;
    const contentOffset = 100.0;
    const contentTop = 78.0;
    final expected = albumLayout(aspects, contentWidth);
    expect(ctx.rows, hasLength(5));
    for (var i = 0; i < 5; i++) {
      final got = tester.getRect(find.byKey(ValueKey(_id(i))));
      expect(got.left, closeTo(expected[i].left + contentOffset, .1), reason: 'm$i left');
      expect(got.top, closeTo(expected[i].top + contentTop, .1), reason: 'm$i top');
      expect(got.width, closeTo(expected[i].width, .1), reason: 'm$i width');
      expect(got.height, closeTo(expected[i].height, .1), reason: 'm$i height');
      // The photo covers its rect (cropped), never letterboxed inside it.
      final photo = find.descendant(
        of: find.byKey(ValueKey(_id(i))),
        matching: find.byType(Hero),
      );
      expect(tester.getRect(photo), got, reason: 'm$i photo fills');
    }
    expect(find.text('Asha Menon'), findsOneWidget);
    expect(find.text('5 photos · 14:30'), findsOneWidget);
  });

  testWidgets('tap a tile → the pager opens at that index', (tester) async {
    await pumpAlbum(tester, rows: five());
    await tapTile(tester, 2);
    await tester.pumpAndSettle();
    expect(find.byType(MediaViewerScreen), findsOneWidget);
    expect(find.text('3 of 5'), findsOneWidget);
    expect(inViewer(find.byType(Hero)), findsOneWidget);
  });

  testWidgets('long-press → Reply / Select / Delete for me / Delete for '
      'everyone; offline dims the everyone row', (tester) async {
    await pumpAlbum(tester, rows: five(), online: false);
    await longPressTile(tester, 0);
    for (final label in ['Reply', 'Select', 'Delete for me', 'Delete for everyone']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    final everyone = tester.widget<SheetActionRow>(
      find.widgetWithText(SheetActionRow, 'Delete for everyone'),
    );
    expect(everyone.enabled, isFalse);
    expect(find.text('Available online'), findsOneWidget);
  });

  testWidgets('long-press on a row → delete just that row after one confirm',
      (tester) async {
    final ctx = await pumpAlbum(tester, rows: five());
    await longPressTile(tester, 0);
    await tester.tap(find.widgetWithText(SheetActionRow, 'Delete for me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(ctx.repo.deleted, [_id(0)]);
  });

  testWidgets('selection: 1 → 3 selected; a tap never opens the viewer; '
      'another tap deselects', (tester) async {
    await pumpAlbum(tester, rows: five());
    await select(tester, [0, 1, 2]);
    expect(find.text('3 selected'), findsOneWidget);
    expect(find.byType(MediaViewerScreen), findsNothing);
    await tapTile(tester, 1);
    expect(find.text('2 selected'), findsOneWidget);
    await tapTile(tester, 2);
    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('E4a: in selection a long-press toggles; E4b: one selected '
      'uses the single copy', (tester) async {
    final ctx = await pumpAlbum(tester, rows: five());
    await select(tester, [0]);
    await longPressTile(tester, 1);
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Reply'), findsNothing, reason: 'no item menu');
    await longPressTile(tester, 1);
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete selected messages'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SheetActionRow, 'Delete for everyone'));
    await tester.pumpAndSettle();
    expect(find.text('Delete message?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(ctx.repo.deletedEveryone, [_id(0)]);
    expect(find.text('0 selected'), findsNothing, reason: 'selection ended');
  });

  testWidgets('0 selected → delete disabled; back exits selection before pop',
      (tester) async {
    await pumpAlbum(tester, rows: five());
    await longPressTile(tester, 0);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tapTile(tester, 0); // deselect → 0 selected
    expect(find.text('0 selected'), findsOneWidget);
    final delete = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Delete selected messages'),
        matching: find.byType(IconButton),
      ),
    );
    expect(delete.onPressed, isNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(find.text('0 selected'), findsNothing, reason: 'selection exited');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsNothing, reason: 'now it pops');
  });

  testWidgets('all own → choice sheet with both deletes; confirm deletes the '
      'selected rows exactly and ends selection', (tester) async {
    final ctx = await pumpAlbum(tester, rows: five());
    await select(tester, [0, 1, 3]);
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Delete selected messages'));
    await tester.pumpAndSettle();
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Delete for everyone'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(SheetActionRow, 'Delete for me'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete 3 messages?'), findsOneWidget);
    expect(find.text('These messages will be deleted for you only.'),
        findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(ctx.repo.deleted, [_id(0), _id(1), _id(3)]);
    expect(ctx.repo.deletedEveryone, isEmpty);
    expect(find.text('3 selected'), findsNothing, reason: 'selection ended');
  });

  testWidgets("their album → straight to the my-side confirm, no choice",
      (tester) async {
    final ctx = await pumpAlbum(tester, rows: [
      for (var i = 0; i < 3; i++) _row(i, sender: 'u_other'),
    ]);
    await select(tester, [0, 1, 2]);
    await tester.tap(find.byTooltip('Delete selected messages'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 3 messages?'), findsOneWidget);
    expect(find.text('Delete for everyone'), findsNothing);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(ctx.repo.deleted, [_id(0), _id(1), _id(2)]);
  });

  testWidgets('a deleted row leaves; one left → the collage pops',
      (tester) async {
    final ctx = await pumpAlbum(tester, rows: five());
    expect(find.text('5 photos · 14:30'), findsOneWidget);

    ctx.emit(five().sublist(0, 4));
    await tester.pump();
    await tester.pump();
    expect(find.byType(AlbumScreen), findsOneWidget);
    expect(find.text('4 photos · 14:30'), findsOneWidget);

    ctx.emit([five()[4]]);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(AlbumScreen), findsNothing, reason: 'E1: one left');
  });

  testWidgets('semantics: tiles are Photo N of M, selected / not selected',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAlbum(tester, rows: five());
    // E4c: selected / not selected is said in selection mode only.
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^Photo 1 of 5')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('selected')), findsNothing);
    await longPressTile(tester, 2);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Photo 3 of 5, selected')),
        findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Photo 1 of 5, not selected')),
        findsOneWidget);
    handle.dispose();
  });

  testWidgets('20 items at 360×200%: the collage and the selection bar fit',
      (tester) async {
    final rows = [for (var i = 0; i < 20; i++) _row(i)];
    await pumpAlbum(
      tester,
      rows: rows,
      large: true,
      viewport: const Size(360, 640),
    );
    expect(tester.takeException(), isNull);

    // Select every tile — the bar must read 20 selected and stay on screen.
    final handle = tester.ensureSemantics();
    await longPressTile(tester, 0);
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    for (var i = 1; i < 20; i++) {
      await tapTile(tester, i);
    }
    expect(find.text('20 selected'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Photo 20 of 20, selected')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
