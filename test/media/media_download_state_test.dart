import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/data/local/database/app_database.dart';
import 'package:kuch_bhi/data/local/database/tables/media_blob_table.dart';
import 'package:kuch_bhi/features/chat/providers/chat_provider.dart';
import 'package:kuch_bhi/features/chat/widgets/image_message_bubble.dart';
import 'package:kuch_bhi/features/chat/widgets/video_message_bubble.dart';
import 'package:kuch_bhi/features/media/providers/media_viewer_providers.dart';
import 'package:kuch_bhi/services/media_upload_service.dart';

/// A media bubble whose full file is not on the phone says so; one that is
/// shows the full file at bubble size instead of the small thumbnail.
void main() {
  final fullFile = File('/nonexistent/full_s1.jpg');

  Future<void> pump(WidgetTester tester, Widget bubble,
      {required Stream<File?> local}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mediaFileProvider.overrideWith((ref, r) => LocalMediaFile(
            file: File('/nonexistent/thumb_${r.serverId}.jpg'),
            width: 4,
            height: 3,
            fileSize: 8493466,
            durationSeconds: 42)),
        mediaFullLocalProvider.overrideWith((ref, r) => local),
      ],
      child: MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(body: Center(child: bubble)),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  const photo = ImageMessageBubble(
      conversationId: 'c1', serverId: 's1', isMine: false, isDark: false);
  const video = VideoMessageBubble(
      conversationId: 'c1', serverId: 's1', isMine: false, isDark: false);

  Finder resized() => find.byWidgetPredicate(
      (w) => w is Image && w.image is ResizeImage);

  // Chat calm gate 9 (E1, D-4 A): no disc on a photo; the label still says
  // it is not downloaded, and a tap opens the viewer, which downloads.
  testWidgets('photo not downloaded: no disc, the label says so', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, photo, local: Stream.value(null));
    expect(find.byIcon(Icons.download_rounded), findsNothing);
    expect(resized(), findsNothing);
    expect(
        tester.getSemantics(find.bySemanticsLabel(
            RegExp('^Open image, not downloaded'))),
        isSemantics(isButton: true));
    semantics.dispose();
  });

  testWidgets('photo downloaded: full file at bubble size, no disc',
      (tester) async {
    await pump(tester, photo, local: Stream.value(fullFile));
    expect(find.byIcon(Icons.download_rounded), findsNothing);
    final img = tester.widget<Image>(resized());
    expect(((img.image as ResizeImage).imageProvider as FileImage).file.path,
        fullFile.path);
  });

  testWidgets('photo with an unknown row shows no disc', (tester) async {
    final never = StreamController<File?>();
    addTearDown(never.close);
    await pump(tester, photo, local: never.stream);
    expect(find.byIcon(Icons.download_rounded), findsNothing);
  });

  // Gate 9 (E2): the size joins the duration only on a known "not on disk".
  testWidgets('video not downloaded: play disc, pill with duration and size',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, video, local: Stream.value(null));
    expect(find.byIcon(Icons.download_rounded), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('0:42 · 8.1 MB'), findsOneWidget);
    expect(
        tester.getSemantics(find.bySemanticsLabel(
            RegExp('^Open video, not downloaded'))),
        isSemantics(isButton: true));
    semantics.dispose();
  });

  testWidgets('video downloaded: disc shows play, pill has no size',
      (tester) async {
    await pump(tester, video, local: Stream.value(fullFile));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsNothing);
    expect(find.text('0:42'), findsOneWidget);
  });

  testWidgets('video with an unknown row shows no size', (tester) async {
    final never = StreamController<File?>();
    addTearDown(never.close);
    await pump(tester, video, local: never.stream);
    expect(find.text('0:42'), findsOneWidget);
    expect(find.textContaining('MB'), findsNothing);
  });

  group('mediaFullLocalProvider', () {
    late AppDatabase db;
    late ProviderContainer c;
    late Directory dir;
    const ref = MediaRef('c1', 's1');

    setUp(() async {
      db = AppDatabase.test();
      c = ProviderContainer(
          overrides: [appDatabaseProvider.overrideWithValue(db)]);
      dir = await Directory.systemTemp.createTemp('full_local');
    });
    tearDown(() async {
      c.dispose();
      await db.close();
      await dir.delete(recursive: true);
    });

    Future<File?> read() async {
      final sub = c.listen(mediaFullLocalProvider(ref), (_, __) {});
      addTearDown(sub.close);
      return c.read(mediaFullLocalProvider(ref).future);
    }

    Future<void> row(BlobState state, String? path) =>
        db.mediaBlobDao.insert(MediaBlobTableCompanion.insert(
          blobId: ref.blobId,
          messageId: 's1',
          lastAccess: DateTime.utc(2026, 1, 1),
          state: Value(state),
          localPath: Value(path),
        ));

    test('no row → null (nothing downloaded, nothing started)', () async {
      expect(await read(), isNull);
      expect(await db.mediaBlobDao.byId(ref.blobId), isNull);
    });

    test('ready row with its file on disk → that file', () async {
      final f = File('${dir.path}/s1.jpg')..writeAsBytesSync([1]);
      await row(BlobState.ready, f.path);
      expect((await read())?.path, f.path);
    });

    test('ready row whose file is gone → null', () async {
      await row(BlobState.ready, '${dir.path}/gone.jpg');
      expect(await read(), isNull);
    });

    test('evicted row → null', () async {
      final f = File('${dir.path}/s1.jpg')..writeAsBytesSync([1]);
      await row(BlobState.evicted, f.path);
      expect(await read(), isNull);
    });
  });
}
