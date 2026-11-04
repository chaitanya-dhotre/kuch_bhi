import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'widgets/voice_waveform.dart';

class VoiceDraft {
  const VoiceDraft({
    required this.file,
    required this.seconds,
    required this.levels,
  });

  final File file;
  final int seconds;
  final List<double> levels;
}

String _keyFor(String conversationId) =>
    conversationId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

Future<Directory> _draftDirectory(Future<Directory> Function() baseDir) async =>
    Directory(p.join((await baseDir()).path, 'voice_drafts'));

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (error) {
    // The path is deliberately omitted from diagnostics.
    debugPrint('[VoiceDraft] delete failed: ${error.runtimeType}');
  }
}

Future<void> _deleteFiles(File audio, File sidecar, [File? temporary]) async {
  await _deleteQuietly(audio);
  await _deleteQuietly(sidecar);
  if (temporary != null) await _deleteQuietly(temporary);
}

Future<VoiceDraft?> loadVoiceDraft(
  String conversationId,
  Future<Directory> Function() baseDir,
) async {
  try {
    final dir = await _draftDirectory(baseDir);
    final key = _keyFor(conversationId);
    final audio = File(p.join(dir.path, '$key.m4a'));
    final sidecar = File(p.join(dir.path, '$key.json'));
    final temporary = File(p.join(dir.path, '$key.json.tmp'));
    if (!await audio.exists() || !await sidecar.exists()) {
      await _deleteFiles(audio, sidecar, temporary);
      return null;
    }
    final data = jsonDecode(await sidecar.readAsString());
    if (data is! Map || data['v'] != 1) {
      await _deleteFiles(audio, sidecar, temporary);
      return null;
    }
    final seconds = data['seconds'];
    final rawLevels = data['levels'];
    if (seconds is! int || rawLevels is! List) {
      await _deleteFiles(audio, sidecar, temporary);
      return null;
    }
    final levels = <double>[];
    for (final level in rawLevels) {
      if (level is! num || !level.isFinite) {
        await _deleteFiles(audio, sidecar, temporary);
        return null;
      }
      levels.add(level.toDouble());
    }
    // A kill between the sidecar's write and its rename leaves no marker.
    await _deleteQuietly(temporary);
    return VoiceDraft(file: audio, seconds: seconds, levels: levels);
  } catch (error) {
    debugPrint('[VoiceDraft] load failed: ${error.runtimeType}');
    try {
      final dir = await _draftDirectory(baseDir);
      final key = _keyFor(conversationId);
      await _deleteFiles(
        File(p.join(dir.path, '$key.m4a')),
        File(p.join(dir.path, '$key.json')),
        File(p.join(dir.path, '$key.json.tmp')),
      );
    } catch (cleanupError) {
      debugPrint(
        '[VoiceDraft] load cleanup failed: ${cleanupError.runtimeType}',
      );
    }
    return null;
  }
}

Future<void> saveVoiceDraft(
  String conversationId,
  File audio,
  int seconds,
  List<double> levels,
  Future<Directory> Function() baseDir,
) async {
  try {
    final dir = await _draftDirectory(baseDir);
    await dir.create(recursive: true);
    final key = _keyFor(conversationId);
    final destination = File(p.join(dir.path, '$key.m4a'));
    final sidecar = File(p.join(dir.path, '$key.json'));
    final temporarySidecar = File(p.join(dir.path, '$key.json.tmp'));

    // Move the new audio in first: a failed move leaves the old draft and its
    // marker untouched, so load still finds a complete draft.
    if (destination.path != audio.path) {
      try {
        await audio.rename(destination.path);
      } on FileSystemException {
        await audio.copy(destination.path);
        await audio.delete();
      }
    }

    // Rename over the old marker, never delete it first: audio with no marker
    // reads as junk to loadVoiceDraft, which would delete it.
    await _deleteQuietly(temporarySidecar);

    final rounded = bucketLevels(
      levels,
      100,
    ).map((level) => double.parse(level.toStringAsFixed(2))).toList();
    await temporarySidecar.writeAsString(
      jsonEncode({'v': 1, 'seconds': seconds, 'levels': rounded}),
    );
    await temporarySidecar.rename(sidecar.path);
  } catch (error) {
    debugPrint('[VoiceDraft] save failed: ${error.runtimeType}');
  }
}

Future<void> deleteVoiceDraft(
  String conversationId,
  Future<Directory> Function() baseDir,
) async {
  try {
    final dir = await _draftDirectory(baseDir);
    final key = _keyFor(conversationId);
    await _deleteFiles(
      File(p.join(dir.path, '$key.m4a')),
      File(p.join(dir.path, '$key.json')),
      File(p.join(dir.path, '$key.json.tmp')),
    );
  } catch (error) {
    debugPrint('[VoiceDraft] delete failed: ${error.runtimeType}');
  }
}

Future<void> wipeVoiceDrafts(Future<Directory> Function() baseDir) async {
  try {
    final dir = await _draftDirectory(baseDir);
    if (await dir.exists()) await dir.delete(recursive: true);
  } catch (error) {
    debugPrint('[VoiceDraft] wipe failed: ${error.runtimeType}');
  }
}
