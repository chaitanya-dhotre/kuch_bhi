/// Albums 12.5 F7 (decision 21): starring an album stars every row, and
/// Starred shows the album's rows as ONE card — the cover's thumbnail and
/// **3 photos** — whose jump lands on the album item.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:kuch_bhi/core/config/fake_message_repository.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/domain/entities/message.dart';
import 'package:kuch_bhi/features/chat/chat_run_grouping.dart';
import 'package:kuch_bhi/features/chat/providers/message_body_provider.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';
import 'package:kuch_bhi/features/chat/widgets/message_context_menu.dart';
import 'package:kuch_bhi/features/starred_messages/screens/starred_messages_screen.dart';
import 'package:kuch_bhi/infrastructure/offline/connectivity_signal.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

import '../core/sheet_harness.dart';

final _at = DateTime(2026, 11, 1, 12, 41);

Message _row(
  String localId, {
  String? serverId,
  String? album,
  int? index,
  bool starred = false,
  String sender = 'u_me',
}) =>
    Message(
      localId: localId,
      serverId: serverId,
      conversationId: 'c1',
      senderId: sender,
      type: 'image',
      status: 'read',
      createdAt: _at.add(Duration(seconds: index ?? 0)),
      albumId: album,
      albumIndex: index,
      isStarred: starred,
      mediaId: serverId,
    );

/// Star/unstar records the calls; the starred list is seeded per test.
class _Repo extends FakeMessageRepository {
  _Repo(this.starred);
  final List<Message> starred;
  final toggled = <String>[];

  @override
  Future<List<Message>> getStarredMessages(String conversationId) async =>
      starred;

  @override
  Future<void> toggleStar(String localId) async => toggled.add(localId);

  @override
  Future<LocalMediaFile?> getDecryptedMedia(
    String conversationId,
    String messageServerId, {
    bool? thumb = false,
  }) async =>
      LocalMediaFile(file: File('/nonexistent/thumb.jpg'));
}

void main() {
  testWidgets('Star on an album stars every row; Unstar clears them all',
      (tester) async {
    final rows = [
      _row('a0', serverId: 's0', album: 's0', index: 0),
      _row('a1', serverId: 's1', album: 's0', index: 1),
      _row('a2', serverId: 's2', album: 's0', index: 2),
    ];
    final repo = _Repo(const []);
    await pumpHost(
      tester,
      SheetLauncher((context, ref) => showMessageMenu(
            context: context,
            ref: ref,
            message: rows.first,
            album: rows,
            isMine: true,
            senderName: 'You',
          )),
      overrides: [
        messageRepositoryProvider.overrideWithValue(repo),
        messageBodyProvider.overrideWith((ref, id) async => null),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    await tapOpen(tester);
    expect(find.text('Star'), findsOneWidget);
    expect(find.text('Copy'), findsNothing, reason: 'F1: no Copy for albums');
    expect(find.text('3 photos'), findsOneWidget, reason: 'F1 album header');
    await tester.tap(find.text('Star'));
    await tester.pumpAndSettle();
    expect(repo.toggled, ['a0', 'a1', 'a2'], reason: 'one star per row');

    // Unstar clears every row.
    final starred = [
      _row('a0', serverId: 's0', album: 's0', index: 0, starred: true),
      _row('a1', serverId: 's1', album: 's0', index: 1, starred: true),
      _row('a2', serverId: 's2', album: 's0', index: 2, starred: true),
    ];
    final repo2 = _Repo(starred);
    await pumpHost(
      tester,
      SheetLauncher((context, ref) => showMessageMenu(
            context: context,
            ref: ref,
            message: starred.first,
            album: starred,
            isMine: true,
            senderName: 'You',
          )),
      overrides: [
        messageRepositoryProvider.overrideWithValue(repo2),
        messageBodyProvider.overrideWith((ref, id) async => null),
        isOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
    await tapOpen(tester);
    expect(find.text('Unstar'), findsOneWidget);
    await tester.tap(find.text('Unstar'));
    await tester.pumpAndSettle();
    expect(repo2.toggled, ['a0', 'a1', 'a2']);
  });

  testWidgets('3 starred album rows + 1 single → 2 cards; the album card '
      'reads 3 photos with the cover thumbnail', (tester) async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    final thumb = File('${Directory.systemTemp.path}/starred_album_thumb.png')
      ..writeAsBytesSync(_png1x1);
    addTearDown(() {
      if (thumb.existsSync()) thumb.deleteSync();
    });
    final repo = _Repo([
      _row('a0', serverId: 's0', album: 's0', index: 0, starred: true),
      _row('a1', serverId: 's1', album: 's0', index: 1, starred: true),
      _row('a2', serverId: 's2', album: 's0', index: 2, starred: true),
      _row('single', serverId: 's9', starred: true, sender: 'u_other'),
    ]);
    Message? jumped;
    await pumpHost(
      tester,
      StarredMessagesScreen(
        conversationId: 'c1',
        onJump: (m) => jumped = m,
      ),
      overrides: [
        messageRepositoryProvider.overrideWithValue(repo),
        messageBodyProvider.overrideWith((ref, id) async => null),
        currentUserIdProvider.overrideWith((ref) async => 'u_me'),
        appDatabaseProvider.overrideWithValue(db),
        mediaFileProvider.overrideWith((ref, r) async =>
            LocalMediaFile(file: thumb, width: 1, height: 1)),
        mediaBlobStatusProvider.overrideWith(
            (ref, r) async => MediaBlobStatus.other),
      ],
    );
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.text('3 photos'), findsOneWidget, reason: 'one album card');
    expect(find.text('You'), findsOneWidget, reason: 'the album card');
    expect(find.text('Contact'), findsOneWidget, reason: 'the single card');
    expect(find.text('Tap to jump to message'), findsNWidgets(2));

    // Tapping the album card pops and jumps with an album row (A6).
    await tester.tap(find.text('3 photos'));
    await tester.pump();
    expect(jumped, isNotNull);
    expect(jumped!.albumId, 's0');
  });

  test('a jumped album row holds the album item in the chat list', () {
    final units = groupChatUnits([
      _row('a2', serverId: 's2', album: 's0', index: 2),
      _row('a1', serverId: 's1', album: 's0', index: 1),
      _row('a0', serverId: 's0', album: 's0', index: 0),
      _row('t', serverId: 'st'),
    ]);
    expect(units.map((u) => u.isAlbum), [true, false]);
    expect(units[0].rows.map((r) => r.localId), ['a0', 'a1', 'a2']);
    // The starred card is rebuilt from the server: localId IS the server id.
    expect(unitHolds(units[0].rows, _row('s1', serverId: 's1')), isTrue);
  });

  testWidgets('a starred row whose siblings are not loaded → a single card',
      (tester) async {
    final db = AppDatabase.test();
    addTearDown(db.close);
    // The local row for s0 has no album id — its siblings were never loaded.
    await db.messagesDao.upsertMessage(
      MessagesTableCompanion.insert(
        localId: 'p0',
        serverId: const Value('s0'),
        conversationId: 'c1',
        senderId: 'u_me',
        type: 'image',
        encryptedBody: '',
        iv: '',
        isStarred: const Value(true),
        createdAt: _at,
        updatedAt: _at,
      ),
    );
    final repo = _Repo([
      _row('s0', serverId: 's0', starred: true),
    ]);
    await pumpHost(
      tester,
      const StarredMessagesScreen(conversationId: 'c1'),
      overrides: [
        messageRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWith((ref) async => 'u_me'),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('photos'), findsNothing,
        reason: 'no album label for a lone row');
    expect(find.text('Tap to jump to message'), findsNothing,
        reason: 'no onJump → no jump line');
  });
}

const _png1x1 = <int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0,
  1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68,
  65, 84, 8, 215, 99, 248, 207, 192, 0, 0, 0, 3, 0, 1, 166, 56, 198, 10, 0,
  0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
];
