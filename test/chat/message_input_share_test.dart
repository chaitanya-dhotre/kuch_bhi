// 12.1 E1–E5, C4, C5: a share handed to a chat runs through the composer's
// existing single / album / document paths, and text lands in the draft.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/core/theme/app_theme.dart';
import 'package:kuch_bhi/domain/repositories/message_repository.dart';
import 'package:kuch_bhi/features/chat/widgets/message_input.dart';
import 'package:kuch_bhi/features/media/screens/media_edit_screen.dart';
import 'package:kuch_bhi/features/share/share_payload.dart';
import 'package:kuch_bhi/infrastructure/repositories/message_repository_impl.dart';
import 'package:kuch_bhi/services/share_in_service.dart';

class _Repo implements MessageRepository {
  final sent = <(String, String)>[]; // (type, file name)

  @override
  Future<void> sendMediaMessage({
    required String conversationId,
    required String mediaType,
    required File mediaFile,
    File? thumbnailFile,
    String? quality,
    int? durationSeconds,
    String? durationText,
    int? videoWidth,
    int? videoHeight,
  }) async {
    sent.add((mediaType, mediaFile.path.split('/').last));
    mediaFile.deleteSync(); // the real send moves it into the blob store
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

late Directory _cache;
var _n = 0;
var _chat = 0;
// The composer's drafts are per chat and live for the process: one chat each.
String get _cid => 'share-c$_chat';

({String path, SharedKind kind, String mime}) _file(
  String name,
  SharedKind kind,
  String mime,
) {
  final f = File('${_cache.path}/share_in/${++_n}/$name')
    ..createSync(recursive: true)
    ..writeAsBytesSync([1, 2, 3]);
  return (path: f.path, kind: kind, mime: mime);
}

({String path, SharedKind kind, String mime}) _photo() =>
    _file('a.jpg', SharedKind.photo, 'image/jpeg');
({String path, SharedKind kind, String mime}) _video() =>
    _file('b.mp4', SharedKind.video, 'video/mp4');
({String path, SharedKind kind, String mime}) _pdf() =>
    _file('report.pdf', SharedKind.document, 'application/pdf');

List<Directory> get _folders => Directory('${_cache.path}/share_in').existsSync()
    ? Directory('${_cache.path}/share_in').listSync().whereType<Directory>().toList()
    : [];

Future<(ProviderContainer, _Repo)> _pump(
  WidgetTester tester,
  ReadyShare? share, {
  bool canSend = true,
  String draft = '',
}) async {
  final repo = _Repo();
  final c = ProviderContainer(
    overrides: [messageRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  if (share != null) c.read(chatShareProvider(_cid).notifier).state = share;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: warmPopLight(),
        home: Scaffold(
          body: _Host(canSend: canSend, draft: draft),
        ),
      ),
    ),
  );
  await tester.pump();
  return (c, repo);
}

class _Host extends StatefulWidget {
  const _Host({required this.canSend, required this.draft});
  final bool canSend;
  final String draft;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool canSend = widget.canSend;
  void allow() => setState(() => canSend = true);
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      MessageInput(
        conversationId: _cid,
        canSendMessages: canSend,
        onSend: (_) {},
      ),
    ],
  );
}

String _composer(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

// The mic pulse repeats, so pumpAndSettle never settles here.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _popTop(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();

void main() {
  setUp(() {
    _chat++;
    _cache = Directory.systemTemp.createTempSync('share_in_test');
  });
  tearDown(() {
    if (_cache.existsSync()) _cache.deleteSync(recursive: true);
  });

  testWidgets('one photo → the editor opens with that file; closing it '
      'cancels, and the folder is deleted', (tester) async {
    final photo = _photo();
    final (c, repo) = await _pump(
      tester,
      ReadyShare(chatName: 'Asha', files: [photo]),
    );
    await tester.pump();
    final editor = tester.widget<MediaEditScreen>(find.byType(MediaEditScreen));
    expect(editor.file!.path, photo.path);
    expect(editor.type, 'image');
    expect(c.read(chatShareProvider(_cid)), isNull, reason: 'taken once');

    _popTop(tester);
    await _settle(tester);
    expect(repo.sent, isEmpty);
    expect(_folders, isEmpty);
  });

  testWidgets('three photos and videos → the album editor with three',
      (tester) async {
    await _pump(
      tester,
      ReadyShare(chatName: 'Asha', files: [_photo(), _video(), _photo()]),
    );
    await tester.pump();
    final editor = tester.widget<MediaEditScreen>(find.byType(MediaEditScreen));
    expect(editor.items!.map((i) => i.type), ['image', 'video', 'image']);
    _popTop(tester);
    await _settle(tester);
    expect(_folders, isEmpty);
  });

  testWidgets('two documents → "Send to Asha?" / "2 files" → Send sends both '
      'in order; a rebuild does not run it again', (tester) async {
    final (_, repo) = await _pump(
      tester,
      ReadyShare(
        chatName: 'Asha',
        files: [_pdf(), _file('notes.txt', SharedKind.document, 'text/plain')],
      ),
    );
    await _settle(tester);
    expect(find.text('Send to Asha?'), findsOneWidget);
    expect(find.text('2 files'), findsOneWidget);
    await tester.tap(find.text('Send'));
    await _settle(tester);
    expect(repo.sent, [('document', 'report.pdf'), ('document', 'notes.txt')]);
    expect(_folders, isEmpty);

    await tester.pump(const Duration(seconds: 6));
    await _settle(tester);
    expect(find.text('Send to Asha?'), findsNothing);
    expect(repo.sent, hasLength(2));
  });

  testWidgets('one document shows its name; Cancel sends nothing and deletes '
      'the copy', (tester) async {
    final (_, repo) = await _pump(
      tester,
      ReadyShare(chatName: 'Weekend crew', files: [_pdf()]),
    );
    await _settle(tester);
    expect(find.text('Send to Weekend crew?'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(repo.sent, isEmpty);
    expect(_folders, isEmpty);
  });

  testWidgets('photo + document: the editor closed → the document confirm '
      'still follows, then the text', (tester) async {
    await _pump(
      tester,
      ReadyShare(chatName: 'Asha', files: [_photo(), _pdf()], text: 'look'),
    );
    await tester.pump();
    expect(find.byType(MediaEditScreen), findsOneWidget);
    _popTop(tester);
    await _settle(tester);
    expect(find.text('Send to Asha?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(_composer(tester), 'look');
  });

  testWidgets('text into an empty composer, never sent; cursor at the end',
      (tester) async {
    final (_, repo) = await _pump(
      tester,
      const ReadyShare(chatName: 'Asha', text: 'https://example.com/trip'),
    );
    await _settle(tester);
    expect(_composer(tester), 'https://example.com/trip');
    final ctrl = tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(ctrl.selection.baseOffset, ctrl.text.length);
    expect(repo.sent, isEmpty);
  });

  testWidgets('text after a draft goes on a new line', (tester) async {
    final (c, _) = await _pump(tester, null);
    await tester.enterText(find.byType(TextField), 'look at this');
    c.read(chatShareProvider(_cid).notifier).state = const ReadyShare(
      chatName: 'Asha',
      text: 'https://example.com',
    );
    await _settle(tester);
    expect(_composer(tester), 'look at this\nhttps://example.com');
  });

  testWidgets('a composer that can\'t send never runs it and drops the copies',
      (tester) async {
    final (c, repo) = await _pump(
      tester,
      ReadyShare(chatName: 'Asha', files: [_pdf()], text: 'hi'),
      canSend: false,
    );
    await _settle(tester);
    expect(find.text('Send to Asha?'), findsNothing);
    expect(c.read(chatShareProvider(_cid)), isNull);
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(find.text("You can't send messages in this chat."), findsOneWidget);
    expect(repo.sent, isEmpty);
    expect(_folders, isEmpty);
  });

  testWidgets('a page over the chat (an editor already open, a send in '
      'flight) holds the share until it is gone', (tester) async {
    final (c, _) = await _pump(tester, null);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(builder: (_) => const Text('editor')));
    await _settle(tester);
    c.read(chatShareProvider(_cid).notifier).state = ReadyShare(
      chatName: 'Asha',
      files: [_pdf()],
    );
    await _settle(tester);
    expect(find.text('Send to Asha?'), findsNothing, reason: 'held');
    nav.pop();
    await _settle(tester);
    expect(find.text('Send to Asha?'), findsOneWidget);
  });

  testWidgets('a group whose send rule settles after the first frame still '
      'runs the share', (tester) async {
    await _pump(
      tester,
      ReadyShare(chatName: 'Family', files: [_pdf()]),
      canSend: false,
    );
    await _settle(tester);
    expect(find.text('Send to Family?'), findsNothing);
    tester.state<_HostState>(find.byType(_Host)).allow();
    await _settle(tester);
    expect(find.text('Send to Family?'), findsOneWidget);
  });
}
