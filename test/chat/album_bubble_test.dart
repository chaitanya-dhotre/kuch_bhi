/// Albums 12.5 D1–D7 (C16): sideways tiles, fixed pills, one earliest
/// expiry badge, per-tile states from the single bubbles, no reply swipe,
/// reactions on the cover, semantics, 360dp at 200% text.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/theme/tokens.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/outbox_status_provider.dart';
import 'package:kuch_bhi/features/chat/providers/upload_progress_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/album_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/expiry_badge.dart';
import 'package:kuch_bhi/features/chat/widgets/media_upload_disc.dart';
import 'package:kuch_bhi/features/chat/widgets/message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/reaction_bar.dart';
import 'package:kuch_bhi/features/chat/widgets/swipe_to_reply.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

import '../core/sheet_harness.dart';

final _at = DateTime(2026, 11, 1, 12, 41);

Message _row(int i, {String type = 'image', String sender = 'u_asha'}) =>
    Message(
      localId: 'mvxalbum00000$i'.padRight(15, '0').substring(0, 15),
      serverId: 'srvalbum000000$i'.substring(0, 15),
      conversationId: 'c1',
      senderId: sender,
      type: type,
      status: 'read',
      createdAt: _at.add(Duration(seconds: i)),
      albumId: 'srvalbum0000000',
      albumIndex: i,
    );

class _Repo implements MessageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

late File _file;

List<Override> _overrides({
  Map<String, (int, int)> sizes = const {},
  Map<String, DateTime> expiry = const {},
}) => [
  mediaFileProvider.overrideWith((ref, r) async {
    final s = sizes[r.serverId] ?? (300, 400);
    return LocalMediaFile(
      file: _file,
      width: s.$1,
      height: s.$2,
      durationSeconds: 14,
      expiresAt: expiry[r.serverId],
    );
  }),
  mediaFullLocalProvider.overrideWith((ref, r) => Stream.value(_file)),
  mediaBlobStatusProvider.overrideWith((ref, r) async => MediaBlobStatus.other),
  isOnlineProvider.overrideWith((ref) => Stream.value(true)),
  uploadPendingProvider.overrideWith((ref, id) => Stream.value(false)),
  uploadProgressProvider.overrideWith((ref, id) => Stream.value(null)),
  messageBodyProvider.overrideWith((ref, id) async => null),
  outboxStatusProvider.overrideWith((ref, c) => Stream.value(const [])),
  reactionsProvider.overrideWith((ref, id) => Stream.value(const [])),
  messageRepositoryProvider.overrideWithValue(_Repo()),
];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  List<Override>? overrides,
  bool large = false,
  String? fontFamily,
}) async {
  await pumpHost(
    tester,
    Scaffold(body: Center(child: child)),
    overrides: overrides ?? _overrides(),
    large: large,
    fontFamily: fontFamily,
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('album_bubble');
    _file = File('${dir.path}/t.jpg')..writeAsBytesSync([0, 1, 2]);
  });

  for (final n in [2, 20]) {
    // Chat calm A5: width A2 (340 at the 800 dp test view), tiles fill
    // 0.72 × width less the 4 dp padding top and bottom.
    testWidgets('$n items: A5 tiles, the next tile peeks', (tester) async {
      await _pump(
        tester,
        AlbumBubble(rows: [for (var i = 0; i < n; i++) _row(i)], isMine: false),
      );
      final list = tester.getRect(find.byType(ListView));
      final width = ChatBubbleGeometry.attachmentWidth(800);
      final tileHeight = ChatBubbleGeometry.albumTileHeight(width) - 8;
      expect(list.width, width);
      final tiles = find.descendant(
        of: find.byType(ListView),
        matching: find.byType(ClipRRect),
      );
      final first = tester.getRect(tiles.first);
      expect(first.height, closeTo(tileHeight, 0.01));
      expect(first.width, closeTo(tileHeight * 3 / 4, 0.01));
      final second = tester.getRect(tiles.at(1));
      expect(second.left, lessThan(list.right - 40 + 1),
          reason: 'at least 40dp of the next tile shows');
      expect(find.text('$n'), findsOneWidget, reason: 'count pill');
      // B2: the time is on the line under the run, not in the album.
      expect(find.byType(ChatBubbleTimestamp), findsNothing);
    });
  }

  testWidgets('tile width clamps to [100, bubble − 40]', (tester) async {
    await _pump(
      tester,
      AlbumBubble(rows: [_row(0), _row(1)], isMine: false),
      overrides: _overrides(sizes: {
        _row(0).serverId!: (1920, 1080),
        _row(1).serverId!: (100, 1000),
      }),
    );
    final tiles = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(ClipRRect),
    );
    expect(tester.getRect(tiles.at(0)).width,
        ChatBubbleGeometry.attachmentWidth(800) - 40);
    expect(tester.getRect(tiles.at(1)).width, 100);
  });

  testWidgets('a photo whose shape differs from its tile still covers the '
      'whole tile (device bug: letterboxed tiles)', (tester) async {
    await _pump(
      tester,
      AlbumBubble(rows: [_row(0), _row(1)], isMine: false),
      overrides: _overrides(sizes: {
        _row(0).serverId!: (1920, 1080), // clamped to bubble − 40 wide
        _row(1).serverId!: (100, 1000), // clamped to 100 wide
      }),
    );
    final tiles = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(ClipRRect),
    );
    for (var i = 0; i < 2; i++) {
      final photo = find.descendant(of: tiles.at(i), matching: find.byType(Hero));
      expect(tester.getRect(photo), tester.getRect(tiles.at(i)), reason: 'tile $i');
    }
  });

  testWidgets('one expiry badge, the earliest, bottom-left', (tester) async {
    final soon = DateTime.now().add(const Duration(days: 2, hours: 1));
    final later = DateTime.now().add(const Duration(days: 20));
    await _pump(
      tester,
      AlbumBubble(rows: [_row(0), _row(1), _row(2)], isMine: false),
      overrides: _overrides(expiry: {
        _row(0).serverId!: later,
        _row(1).serverId!: soon,
        _row(2).serverId!: later,
      }),
    );
    expect(find.byType(ExpiryBadge), findsOneWidget);
    expect(
      tester.widget<ExpiryBadge>(find.byType(ExpiryBadge)).label,
      compactExpiryLabel(soon),
    );
    expect(tester.widget<ExpiryBadge>(find.byType(ExpiryBadge)).bottomLeft,
        isTrue);
  });

  testWidgets('tap a tile → onOpen(index); never the single viewer',
      (tester) async {
    final opened = <int>[];
    await _pump(
      tester,
      AlbumBubble(
        rows: [_row(0), _row(1, type: 'video')],
        isMine: false,
        onOpen: opened.add,
      ),
    );
    final tiles = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(ClipRRect),
    );
    // Tile 1 peeks: tap its visible edge.
    await tester.tapAt(tester.getRect(tiles.at(1)).centerLeft + const Offset(20, 0));
    await tester.tap(tiles.at(0));
    await tester.pump();
    expect(opened, [1, 0]);
    expect(find.byType(Hero), findsWidgets);
    expect(
      tester.widget<HeroMode>(find.byType(HeroMode)).enabled,
      isFalse,
      reason: 'D8: no flight into the collage',
    );
  });

  testWidgets('an own unsent tile shows its cancel disc; the ticks are a '
      'clock until every item is sent', (tester) async {
    final rows = [
      _row(0, sender: 'me'),
      Message(
        localId: 'mvxalbum0000001',
        conversationId: 'c1',
        senderId: 'me',
        type: 'image',
        status: 'pending',
        createdAt: _at,
        albumId: 'mvxalbum0000000',
        albumIndex: 1,
      ),
    ];
    await _pump(
      tester,
      AlbumBubble(rows: rows, isMine: true),
      overrides: [
        ..._overrides(),
        uploadPendingProvider.overrideWith(
          (ref, id) => Stream.value(id == 'mvxalbum0000001'),
        ),
      ],
    );
    expect(find.byType(MediaUploadDisc), findsOneWidget);
    // B2: the run's time line reads the album's ticks from albumStatus.
    expect(
      albumStatus([
        (mediaId: 'a', uploadLocalId: null, status: 'read'),
        (mediaId: 'b', uploadLocalId: 'b', status: 'pending'),
      ]),
      'pending',
    );
    expect(
      albumStatus([
        (mediaId: 'a', uploadLocalId: null, status: 'read'),
        (mediaId: 'b', uploadLocalId: null, status: 'delivered'),
      ]),
      'delivered',
    );
  });

  testWidgets('tile semantics: "Photo 1 of 3" / "Video 2 of 3" + its length',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      AlbumBubble(
        rows: [_row(0), _row(1, type: 'video'), _row(2)],
        isMine: false,
      ),
    );
    expect(find.bySemanticsLabel('Photo 1 of 3'), findsOneWidget);
    // The length chip's own text joins the tile's label.
    expect(find.bySemanticsLabel('Video 2 of 3\n0:14'), findsOneWidget);
    handle.dispose();
  });

  test('albumTileLabel appends the tile state', () {
    expect(
      albumTileLabel(index: 1, count: 5, video: false, sending: true),
      'Photo 2 of 5, sending',
    );
    expect(
      albumTileLabel(index: 0, count: 5, video: false, failed: true),
      'Photo 1 of 5, not sent',
    );
  });

  testWidgets('in MessageBubble: no SwipeToReply, reactions keyed by the '
      'cover, album row semantics', (tester) async {
    final handle = tester.ensureSemantics();
    final rows = [
      _row(0),
      _row(1),
      _row(2),
      _row(3, type: 'video'),
      _row(4, type: 'video'),
    ];
    await _pump(
      tester,
      MessageBubble(
        message: rows.first,
        album: rows,
        isMine: false,
        senderName: 'Asha',
      ),
    );
    expect(find.byType(AlbumBubble), findsOneWidget);
    expect(find.byType(SwipeToReply), findsNothing);
    final bars = tester.widgetList<ReactionBar>(find.byType(ReactionBar));
    expect(bars.map((b) => b.messageServerId), [rows.first.serverId]);
    expect(
      find.bySemanticsLabel(
        RegExp(r'^Album, 3 photos and 2 videos, from Asha, 12:41'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  for (final font in [null, 'PlusJakartaSans']) {
    testWidgets('360dp at 200% text (${font ?? 'system'}): no overflow',
        (tester) async {
      await _pump(
        tester,
        MessageBubble(
          message: _row(0),
          album: [for (var i = 0; i < 5; i++) _row(i)],
          isMine: true,
          senderName: 'Asha',
        ),
        large: true,
        fontFamily: font,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('no Text coloured accent or error', (tester) async {
    await _pump(
      tester,
      AlbumBubble(rows: [_row(0), _row(1)], isMine: true),
    );
    final ctx = tester.element(find.byType(AlbumBubble));
    final bad = {ctx.t.accent, ctx.t.error};
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(bad.contains(t.style?.color), isFalse, reason: t.data);
    }
  });
}
