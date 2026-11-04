import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuch_bhi/features/chat/voice_draft_store.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('voice-drafts-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<Directory> baseDir() async => root;

  test(
    'save moves audio and load restores seconds and at most 100 levels',
    () async {
      final source = File('${root.path}/source.m4a')
        ..writeAsBytesSync([1, 2, 3]);
      final levels = List<double>.generate(140, (index) => index / 140);
      await saveVoiceDraft('chat', source, 12, levels, baseDir);
      final draft = await loadVoiceDraft('chat', baseDir);
      expect(await source.exists(), isFalse);
      expect(draft?.seconds, 12);
      expect(draft?.levels.length, lessThanOrEqualTo(100));
    },
  );

  test('invalid marker or missing audio deletes both files', () async {
    final dir = Directory('${root.path}/voice_drafts')
      ..createSync(recursive: true);
    final audio = File('${dir.path}/chat.m4a');
    final sidecar = File('${dir.path}/chat.json');
    await sidecar.writeAsString(
      jsonEncode({'v': 1, 'seconds': 1, 'levels': []}),
    );
    expect(await loadVoiceDraft('chat', baseDir), isNull);
    expect(await sidecar.exists(), isFalse);
    await audio.writeAsBytes([1]);
    await sidecar.writeAsString('{not json');
    expect(await loadVoiceDraft('chat', baseDir), isNull);
    expect(await audio.exists(), isFalse);
    await audio.writeAsBytes([1]);
    await sidecar.writeAsString(
      jsonEncode({'v': 2, 'seconds': 1, 'levels': []}),
    );
    expect(await loadVoiceDraft('chat', baseDir), isNull);
    expect(await sidecar.exists(), isFalse);
  });

  test('saving twice replaces one chat draft with the second audio', () async {
    final first = File('${root.path}/first.m4a')..writeAsBytesSync([1]);
    final second = File('${root.path}/second.m4a')..writeAsBytesSync([2]);
    await saveVoiceDraft('chat', first, 1, [.1], baseDir);
    await saveVoiceDraft('chat', second, 2, [.2], baseDir);
    final draft = await loadVoiceDraft('chat', baseDir);
    expect(draft?.seconds, 2);
    expect(await File('${root.path}/voice_drafts/chat.m4a').readAsBytes(), [2]);
  });

  test('delete and wipe are safe for files and a missing folder', () async {
    final source = File('${root.path}/source.m4a')..writeAsBytesSync([1]);
    await saveVoiceDraft('chat', source, 1, [.1], baseDir);
    await deleteVoiceDraft('chat', baseDir);
    expect(await loadVoiceDraft('chat', baseDir), isNull);
    await wipeVoiceDrafts(baseDir);
    await wipeVoiceDrafts(baseDir);
  });

  test('conversation ids are safely keyed', () async {
    final source = File('${root.path}/source.m4a')..writeAsBytesSync([1]);
    await saveVoiceDraft('a/b:c', source, 1, [.1], baseDir);
    expect(await File('${root.path}/voice_drafts/a_b_c.m4a').exists(), isTrue);
    expect(await File('${root.path}/voice_drafts/a_b_c.json').exists(), isTrue);
  });
}
